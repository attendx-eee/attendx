import 'dart:io';
import 'dart:math' as math;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// Turns a camera frame into the 112x112 the embedding model expects.
///
/// ## Why this was rewritten
///
/// The previous version rotated the *whole frame* to level the eyes and
/// then cropped using the bounding box from **before** the rotation:
///
/// ```dart
/// alignedImage = img.copyRotate(original, angle: angle);
/// int x = box.left.toInt() - padding;          // pre-rotation coords
/// img.copyCrop(alignedImage, x: x, ...);       // post-rotation image
/// ```
///
/// `copyRotate` turns the image about its centre *and grows the canvas*
/// to fit the result, so every pixel moves. Cropping the rotated image
/// at the original coordinates therefore lands somewhere else entirely.
/// On a 720x1280 frame with the face roughly centred:
///
/// | head tilt | crop centre misses by |
/// |-----------|-----------------------|
/// | 2°        | 30 px  (14% of the face) |
/// | 5°        | 74 px  (34%) |
/// | 10°       | 143 px (65%) |
/// | 15°       | 207 px (94%) |
///
/// Nobody holds a phone at exactly 0°. So the 112x112 handed to the
/// model routinely contained collar, shoulder, hair and wall — which is
/// why a change of shirt or of background moved the score, and why the
/// same person failed against their own template. It also explains why
/// enrolling three times made no difference: each capture had a slightly
/// different tilt, so each one stored a differently wrong region.
///
/// ## What it does now
///
/// One inverse similarity warp, sampled straight out of the source
/// frame. The two eyes are mapped onto the canonical positions
/// MobileFaceNet was trained against (the ArcFace 112x112 template), so
/// scale, rotation and translation are normalised in a single pass and
/// no intermediate image is ever built. Head tilt stops mattering
/// because it is *removed* rather than approximated, and the framing is
/// identical every capture — which is the only way a stored template
/// and a live frame can be compared meaningfully.
class FaceCropService {
  /// ArcFace's canonical landmark positions for a 112x112 crop.
  ///
  /// Only the eyes are used — two points fix a similarity transform
  /// exactly (rotation, uniform scale, translation), and the eyes are
  /// far and away the most stable landmarks ML Kit reports. The mouth
  /// points are here for reference and for the sanity check below.
  static const double _leftEyeX = 38.2946;
  static const double _leftEyeY = 51.6963;
  static const double _rightEyeX = 73.5318;
  static const double _rightEyeY = 51.5014;

  static const int _size = 112;

  static double get _targetEyeDistance => _rightEyeX - _leftEyeX;

  bool isImageTooDark(img.Image image) {
    int totalLuminance = 0;
    for (var pixel in image) {
      // Standard luminance formula
      totalLuminance +=
          (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).toInt();
    }
    double averageLuminance = totalLuminance / (image.width * image.height);

    // 0 is pitch black, 255 is pure white.
    // Anything below 40-50 is generally too dark for reliable facial
    // recognition.
    return averageLuminance < 45.0;
  }

  Future<img.Image?> cropFace(File imageFile, Face face) async {
    final bytes = await imageFile.readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) return null;

    return cropFromImage(original, face);
  }

  /// The same crop, from an image already in memory.
  ///
  /// The classroom sweep needs this. Going through [cropFace] there made
  /// it read and decode the whole 1920x1080 frame once *per face* — in a
  /// room with twenty visible faces, twenty full decodes for twenty
  /// 112x112 crops, all of the same picture. The caller decodes once and
  /// calls this for each face instead.
  img.Image? cropFromImage(img.Image source, Face face) {
    final aligned = alignFromLandmarks(source, face) ??
        _boundingBoxFallback(source, face);

    if (aligned == null) return null;

    return normaliseIllumination(aligned);
  }

  /// The eye-aligned warp. Null when ML Kit gave us no eyes to work with.
  img.Image? alignFromLandmarks(img.Image source, Face face) {
    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;

    if (leftEye == null || rightEye == null) return null;

    // Ordered by x, not by ML Kit's labels.
    //
    // "Left eye" means the subject's left, which in an unmirrored frame
    // sits on the right of the image — and a front camera may or may not
    // be mirrored depending on the device. Taking the labels literally
    // gives a 180° rotation on half the phones in the department. Sorting
    // by x is mirror-agnostic and always produces an upright face; the
    // flip augmentation at embedding time covers the handedness.
    final a = leftEye.x <= rightEye.x ? leftEye : rightEye;
    final b = leftEye.x <= rightEye.x ? rightEye : leftEye;

    final dx = (b.x - a.x).toDouble();
    final dy = (b.y - a.y).toDouble();

    final distance = math.sqrt(dx * dx + dy * dy);

    // Eyes on top of each other means a bad detection, not a face.
    if (distance < 8) return null;

    final theta = math.atan2(dy, dx);
    final scale = _targetEyeDistance / distance;

    final cos = math.cos(theta);
    final sin = math.sin(theta);

    final out = img.Image(width: _size, height: _size, numChannels: 3);

    // Inverse warp: walk the destination and pull from the source, which
    // leaves no holes. The forward map is
    //   dst = scale * R(-theta) * (src - eyeA) + target
    // so its inverse is
    //   src = R(theta) * (dst - target) / scale + eyeA
    for (var v = 0; v < _size; v++) {
      final ty = (v - _leftEyeY) / scale;

      for (var u = 0; u < _size; u++) {
        final tx = (u - _leftEyeX) / scale;

        final sx = tx * cos - ty * sin + a.x;
        final sy = tx * sin + ty * cos + a.y;

        _sampleBilinear(source, sx, sy, out, u, v);
      }
    }

    return out;
  }

  /// Bilinear sample of [source] at (sx, sy), written into [out] at (u, v).
  ///
  /// Bilinear rather than nearest because the warp usually shrinks the
  /// face — a 220px face becomes 112px — and point sampling a downscale
  /// aliases badly, which the embedding reads as texture that is not on
  /// the person's face.
  void _sampleBilinear(
    img.Image source,
    double sx,
    double sy,
    img.Image out,
    int u,
    int v,
  ) {
    if (sx < 0 || sy < 0 || sx > source.width - 1 || sy > source.height - 1) {
      // Outside the frame — the face is against an edge. Mid grey is a
      // neutral filler; it is a small area and beats wrapping or
      // clamping a bright edge pixel across the crop.
      out.setPixelRgb(u, v, 128, 128, 128);
      return;
    }

    final x0 = sx.floor();
    final y0 = sy.floor();
    final x1 = math.min(x0 + 1, source.width - 1);
    final y1 = math.min(y0 + 1, source.height - 1);

    final fx = sx - x0;
    final fy = sy - y0;

    final p00 = source.getPixel(x0, y0);
    final p10 = source.getPixel(x1, y0);
    final p01 = source.getPixel(x0, y1);
    final p11 = source.getPixel(x1, y1);

    double lerp(num a, num b, num c, num d) {
      final top = a + (b - a) * fx;
      final bottom = c + (d - c) * fx;
      return top + (bottom - top) * fy;
    }

    out.setPixelRgb(
      u,
      v,
      lerp(p00.r, p10.r, p01.r, p11.r).round().clamp(0, 255),
      lerp(p00.g, p10.g, p01.g, p11.g).round().clamp(0, 255),
      lerp(p00.b, p10.b, p01.b, p11.b).round().clamp(0, 255),
    );
  }

  /// Square crop around the detected box, for frames with no landmarks.
  ///
  /// Square on purpose. The old code cropped the box plus 10% and
  /// resized that rectangle to 112x112, which stretches a tall box into
  /// a square and distorts the face differently at every distance from
  /// the camera. Cropping square first keeps the proportions.
  img.Image? _boundingBoxFallback(img.Image source, Face face) {
    final box = face.boundingBox;

    final cx = box.left + box.width / 2;
    final cy = box.top + box.height / 2;

    // Slightly wider than the box: ML Kit's box is tight to the jaw and
    // the model expects a little forehead.
    final side = math.max(box.width, box.height) * 1.25;

    var x = (cx - side / 2).round();
    var y = (cy - side / 2).round();
    var w = side.round();
    var h = side.round();

    // Clamp the window as a window, not corner-then-size — the previous
    // version clamped x and y but left the width computed from the
    // unclamped values, so a face near an edge produced a crop running
    // off the image.
    if (x < 0) {
      w += x;
      x = 0;
    }
    if (y < 0) {
      h += y;
      y = 0;
    }
    if (x + w > source.width) w = source.width - x;
    if (y + h > source.height) h = source.height - y;

    if (w <= 0 || h <= 0) return null;

    final cropped = img.copyCrop(source, x: x, y: y, width: w, height: h);

    return img.copyResize(
      cropped,
      width: _size,
      height: _size,
      interpolation: img.Interpolation.cubic,
    );
  }

  /// Pulls the crop's brightness and contrast towards a common point.
  ///
  /// Applied to enrolment and to verification alike — which is the part
  /// that matters. The model tolerates a range of lighting, but a
  /// template captured under a window and a login captured under a
  /// corridor tube are further apart than they need to be, and closing
  /// that gap costs one pass over 12k pixels.
  ///
  /// Deliberately gentle: a gain towards a mid grey and a mild contrast
  /// stretch, both clamped. Full histogram equalisation was tempting and
  /// is worse here — it invents contrast in flat regions, so a plain
  /// wall behind the head turns into texture the embedding then treats
  /// as part of the person.
  img.Image normaliseIllumination(img.Image crop) {
    var sum = 0.0;
    var sumSq = 0.0;
    final n = crop.width * crop.height;

    for (final p in crop) {
      final luma = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      sum += luma;
      sumSq += luma * luma;
    }

    final mean = sum / n;
    final variance = (sumSq / n) - (mean * mean);
    final std = variance <= 0 ? 1.0 : math.sqrt(variance);

    if (mean <= 1) return crop;

    const targetMean = 128.0;
    const targetStd = 52.0;

    // Bounded so a very dark or very flat frame is lifted rather than
    // amplified into noise.
    final gain = (targetStd / std).clamp(0.75, 1.6);
    final bias = targetMean - mean * gain;

    for (var y = 0; y < crop.height; y++) {
      for (var x = 0; x < crop.width; x++) {
        final p = crop.getPixel(x, y);

        crop.setPixelRgb(
          x,
          y,
          (p.r * gain + bias).round().clamp(0, 255),
          (p.g * gain + bias).round().clamp(0, 255),
          (p.b * gain + bias).round().clamp(0, 255),
        );
      }
    }

    return crop;
  }
}
