class FaceAlignmentResult {
  final bool passed;
  final double score;

  const FaceAlignmentResult({
    required this.passed,
    required this.score,
  });
}

class FaceAlignmentService {
  const FaceAlignmentService();

  FaceAlignmentResult evaluate({
    required bool occupancyPassed,
    required bool centeringPassed,
    required bool posePassed,
    required bool eyeDistancePassed,
  }) {
    double score = 0;

    if (occupancyPassed) {
      score += 25;
    }

    if (centeringPassed) {
      score += 25;
    }

    if (posePassed) {
      score += 25;
    }

    if (eyeDistancePassed) {
      score += 25;
    }

    return FaceAlignmentResult(
      passed: score >= 75,
      score: score,
    );
  }
}