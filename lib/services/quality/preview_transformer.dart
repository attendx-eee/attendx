import 'dart:math' as math;
import 'package:flutter/material.dart';

class PreviewTransformer {
  const PreviewTransformer();

  Matrix4 buildMatrix({
    required Size imageSize,
    required Size previewSize,
    required bool isFrontCamera,
    required int sensorOrientation,
  }) {
    final double rotatedWidth = imageSize.height;
    final double rotatedHeight = imageSize.width;

    final double scale = math.max(
      previewSize.width / rotatedWidth,
      previewSize.height / rotatedHeight,
    );

    Matrix4 matrix = Matrix4.identity();

    matrix *= Matrix4.translationValues(
      previewSize.width / 2,
      previewSize.height / 2,
      0,
    );

    matrix *= Matrix4.rotationZ(
      sensorOrientation == 270
          ? math.pi / 2
          : -math.pi / 2,
    );

    if (isFrontCamera) {
      matrix *= Matrix4.diagonal3Values(-1, 1, 1);
    }

    matrix *= Matrix4.diagonal3Values(
      scale,
      scale,
      1,
    );

    matrix *= Matrix4.translationValues(
      -imageSize.width / 2,
      -imageSize.height / 2,
      0,
    );

    return matrix;
  }
}