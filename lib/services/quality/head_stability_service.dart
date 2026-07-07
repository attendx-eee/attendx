import 'dart:math';

class HeadStabilityService {
  const HeadStabilityService();

  double calculateMovement({
    required double previousX,
    required double previousY,
    required double currentX,
    required double currentY,
  }) {
    return sqrt(
      pow(currentX - previousX, 2) +
      pow(currentY - previousY, 2),
    );
  }

  bool isStable(
    double movement,
    double threshold,
  ) {
    return movement <= threshold;
  }
}