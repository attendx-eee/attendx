import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:math' as math;

class EyeDistanceResult {
  final bool passed;
  final double normalizedDistance;

  const EyeDistanceResult({
    required this.passed,
    required this.normalizedDistance,
  });
}

class EyeDistanceService {
  const EyeDistanceService();

  EyeDistanceResult evaluate(
    Face face,
    double frameWidth,
  ) {
    final leftEye =
        face.landmarks[FaceLandmarkType.leftEye];

    final rightEye =
        face.landmarks[FaceLandmarkType.rightEye];

    if (leftEye == null || rightEye == null) {
      return const EyeDistanceResult(
        passed: false,
        normalizedDistance: 0,
      );
    }

    final dx =
        leftEye.position.x -
        rightEye.position.x;

    final dy =
        leftEye.position.y -
        rightEye.position.y;

    final distance =
        math.sqrt(dx * dx + dy * dy);

    final normalized =
        distance / frameWidth;

    return EyeDistanceResult(
      passed:
          normalized >= 0.15 &&
          normalized <= 0.40,
      normalizedDistance: normalized,
    );
  }
}