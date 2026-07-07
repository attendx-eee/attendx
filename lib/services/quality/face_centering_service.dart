import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class FaceCenteringResult {
  final bool passed;
  final double normalizedOffsetX;
  final double normalizedOffsetY;
  final double distance;
  final double marginRatio;

  const FaceCenteringResult({
    required this.passed,
    required this.normalizedOffsetX,
    required this.normalizedOffsetY,
    required this.distance,
    required this.marginRatio,
  });
}

class FaceCenteringService {
  const FaceCenteringService();

  FaceCenteringResult evaluate({
    required Rect faceRect,
    required Rect guideRect,
    required Size screenSize,
  }) {
    final Offset faceCenter = faceRect.center;
    final Offset guideCenter = guideRect.center;

    final dx = faceCenter.dx - guideCenter.dx;
    final dy = faceCenter.dy - guideCenter.dy;

    final normalizedOffsetX = dx / (guideRect.width / 2);
    final normalizedOffsetY = dy / (guideRect.height / 2);

    final distance = (faceCenter - guideCenter).distance;

    // Orientation check
    final bool isPortrait = screenSize.height > screenSize.width;

    // Much looser tolerances (allow offsets up to ~1.0)
    final double adaptiveToleranceX = isPortrait ? 1.0 : 1.2;
    final double adaptiveToleranceY = isPortrait ? 1.0 : 1.2;

    // Margin ratio: overlap between face rect and guide rect
    final overlap = guideRect.intersect(faceRect);
    final marginRatio = (overlap.width * overlap.height) /
        (faceRect.width * faceRect.height);

    // Pass if offsets are within tolerance OR margin ratio is strong
    final passed = (normalizedOffsetX.abs() <= adaptiveToleranceX &&
                    normalizedOffsetY.abs() <= adaptiveToleranceY) ||
                   marginRatio > 0.3; // accept if at least 30% overlap

    if (kDebugMode) {
      debugPrint(
          "Centering → dx: ${dx.toStringAsFixed(2)}, dy: ${dy.toStringAsFixed(2)}, "
          "normX: ${normalizedOffsetX.toStringAsFixed(3)}, normY: ${normalizedOffsetY.toStringAsFixed(3)}, "
          "marginRatio: ${(marginRatio * 100).toStringAsFixed(1)}%, passed: $passed");
    }

    return FaceCenteringResult(
      passed: passed,
      normalizedOffsetX: normalizedOffsetX,
      normalizedOffsetY: normalizedOffsetY,
      distance: distance,
      marginRatio: marginRatio,
    );
  }
}
