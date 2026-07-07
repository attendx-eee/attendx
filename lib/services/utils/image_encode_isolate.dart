import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

List<int>? encodeImageToJpegIsolate(Map<String, dynamic> data) {
  try {
    final planes = List<Map<String, dynamic>>.from(data['planes']);
    final int width = data['width'];
    final int height = data['height'];
    final ImageFormatGroup format = data['format'];

    img.Image? targetImage;

    if (format == ImageFormatGroup.bgra8888) {
      final Uint8List rgbaBytes = planes[0]['bytes'];
      targetImage = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgbaBytes.buffer,
        order: img.ChannelOrder.bgra,
      );
    } else {
      targetImage = img.Image(width: width, height: height);

      final Uint8List yPlane = planes[0]['bytes'];
      
      // FALLBACK SAFETY: Check if the device packed everything into plane 0
      final bool isPackedYUV = planes.length < 3;
      
      final Uint8List uPlane = isPackedYUV ? yPlane : planes[1]['bytes'];
      final Uint8List vPlane = isPackedYUV ? yPlane : planes[2]['bytes'];

      final int yRowStride = planes[0]['bytesPerRow'];
      
      // Safe assignment of UV strides based on plane availability
      final int uvRowStride = isPackedYUV ? yRowStride : planes[1]['bytesPerRow'];
      final int uvPixelStride = isPackedYUV ? 2 : (planes[1]['bytesPerPixel'] ?? 1);

      // NV21 packed format: Y plane occupies the first (width * height) bytes.
      // U and V channels are interleaved right after it.
      final int uvOffset = width * height;

      for (int w = 0; w < width; w++) {
        for (int h = 0; h < height; h++) {
          final int yIndex = h * yRowStride + w;
          
          int uIndex;
          int vIndex;

          if (isPackedYUV) {
            // NV21 specific packing index calculation
            final int uvIndex = uvOffset + ((h >> 1) * width) + (w & ~1);
            vIndex = uvIndex;
            uIndex = uvIndex + 1;
          } else {
            final int uvIndex = (h >> 1) * uvRowStride + (w >> 1) * uvPixelStride;
            uIndex = uvIndex;
            vIndex = uvIndex;
          }

          // Guard against out-of-bounds byte parsing on non-standard camera aspect ratios
          if (yIndex >= yPlane.length || uIndex >= uPlane.length || vIndex >= vPlane.length) {
            continue;
          }

          final int yVal = yPlane[yIndex];
          final int uVal = uPlane[uIndex];
          final int vVal = vPlane[vIndex];

          int r = (yVal + (1.370705 * (vVal - 128))).round().clamp(0, 255);
          int g = (yVal - (0.337633 * (uVal - 128)) - (0.698001 * (vVal - 128))).round().clamp(0, 255);
          int b = (yVal + (1.732446 * (uVal - 128))).round().clamp(0, 255);

          targetImage.setPixelRgb(w, h, r, g, b);
        }
      }
    }

    return img.encodeJpg(img.copyRotate(targetImage, angle: 270));
  } catch (e) {
    debugPrint("Isolate color encoding failure: $e");
    return null;
  }
}