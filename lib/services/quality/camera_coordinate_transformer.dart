import 'dart:math' as math;
import 'package:flutter/material.dart';

class CameraCoordinateTransformer {
  const CameraCoordinateTransformer();

  Rect transformRect({
    required Rect rect,
    required Size imageSize,
    required Size previewSize,
    required bool isFrontCamera,
  }) {
    // Check if sensor reports landscape
    final bool imageLandscape = imageSize.width > imageSize.height;

    // Rotate image size if needed
    final Size rotatedImageSize = imageLandscape
        ? Size(imageSize.height, imageSize.width)
        : imageSize;

    // Scale factor (BoxFit.cover)
    final double scale = math.max(
      previewSize.width / rotatedImageSize.width,
      previewSize.height / rotatedImageSize.height,
    );

    final double scaledWidth = rotatedImageSize.width * scale;
    final double scaledHeight = rotatedImageSize.height * scale;

    // Crop offsets
    final double dx = (scaledWidth - previewSize.width) / 2;
    final double dy = (scaledHeight - previewSize.height) / 2;

    // Rotate coordinates from sensor to screen
    double left = imageSize.height - rect.bottom;
    double top = rect.left;
    double right = imageSize.height - rect.top;
    double bottom = rect.right;

    // Apply scale
    left *= scale;
    right *= scale;
    top *= scale;
    bottom *= scale;

    // Remove crop
    left -= dx;
    right -= dx;
    top -= dy;
    bottom -= dy;

        debugPrint(
      "TransformRect → "
      "Input: ${rect.left},${rect.top},${rect.right},${rect.bottom} "
      "→ Output: ${left.toStringAsFixed(1)},${top.toStringAsFixed(1)},"
      "${right.toStringAsFixed(1)},${bottom.toStringAsFixed(1)} "
      "Scale: ${scale.toStringAsFixed(3)} "
      "FrontCam: $isFrontCamera"
    );


    // Mirror horizontally for front camera
    if (isFrontCamera) {
      final double mirroredLeft = previewSize.width - right;
      final double mirroredRight = previewSize.width - left;
      left = mirroredLeft;
      right = mirroredRight;
    }

    // Clamp to preview bounds (avoid overflow)
    left = left.clamp(0.0, previewSize.width);
    right = right.clamp(0.0, previewSize.width);
    top = top.clamp(0.0, previewSize.height);
    bottom = bottom.clamp(0.0, previewSize.height);

    return Rect.fromLTRB(left, top, right, bottom);
  }

  

  Offset transformPoint({
    required Offset point,
    required Size imageSize,
    required Size previewSize,
    required bool isFrontCamera,
  }) {
    final rect = transformRect(
      rect: Rect.fromCenter(center: point, width: 1, height: 1),
      imageSize: imageSize,
      previewSize: previewSize,
      isFrontCamera: isFrontCamera,
    );
    return rect.center;
  }
}
