import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceCropService {
  bool isImageTooDark(img.Image image) {
    int totalLuminance = 0;
    for (var pixel in image) {
      // Standard luminance formula
      totalLuminance += (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).toInt();
    }
    double averageLuminance = totalLuminance / (image.width * image.height);
    
    // 0 is pitch black, 255 is pure white. 
    // Anything below 40-50 is generally too dark for reliable facial recognition.
    return averageLuminance < 45.0; 
  }
  Future<img.Image?> cropFace(File imageFile, Face face) async {
  final bytes = await imageFile.readAsBytes();
  img.Image? original = img.decodeImage(bytes);
  if (original == null) return null;

  // 1. Eye landmarks for alignment
  final leftEye = face.landmarks[FaceLandmarkType.leftEye];
  final rightEye = face.landmarks[FaceLandmarkType.rightEye];
  img.Image alignedImage = original;

  if (leftEye != null && rightEye != null) {
    final dx = rightEye.position.x - leftEye.position.x;
    final dy = rightEye.position.y - leftEye.position.y;
    final angle = math.atan2(dy, dx) * (180 / math.pi);

    // Rotate around image center (supported by copyRotate)
    alignedImage = img.copyRotate(original, angle: angle);
  }

  // 2. Adaptive padding (10% of face box height)
  final box = face.boundingBox;
  final padding = (box.height * 0.1).toInt();

  int x = box.left.toInt() - padding;
  int y = box.top.toInt() - padding;
  int width = box.width.toInt() + (padding * 2);
  int height = box.height.toInt() + (padding * 2);

  // Boundary checks
  x = x.clamp(0, alignedImage.width - 1);
  y = y.clamp(0, alignedImage.height - 1);
  if (x + width > alignedImage.width) width = alignedImage.width - x;
  if (y + height > alignedImage.height) height = alignedImage.height - y;

  // 3. Crop
  img.Image cropped = img.copyCrop(alignedImage, x: x, y: y, width: width, height: height);

  // 4. Resize to standard embedding size (e.g., 112x112) with bicubic interpolation
  final resized = img.copyResize(cropped, width: 112, height: 112, interpolation: img.Interpolation.cubic);

  return resized;
}

}