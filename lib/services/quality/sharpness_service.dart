import 'package:image/image.dart' as img;
import '../../models/quality_thresholds.dart';
import 'dart:math' as math;


class SharpnessService {
  const SharpnessService();

  double calculateLaplacianVariance(
    img.Image image,
  ) {
    final gray = img.grayscale(image);

    final width = gray.width;
    final height = gray.height;

    final List<double> laplacianValues = [];

    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {

        final center =
            gray.getPixel(x, y).r.toDouble();

        final top =
            gray.getPixel(x, y - 1).r.toDouble();

        final bottom =
            gray.getPixel(x, y + 1).r.toDouble();

        final left =
            gray.getPixel(x - 1, y).r.toDouble();

        final right =
            gray.getPixel(x + 1, y).r.toDouble();

        final laplacian =
            (-4 * center) +
            top +
            bottom +
            left +
            right;

        laplacianValues.add(laplacian);
      }
    }

    final mean =
        laplacianValues.reduce(
              (a, b) => a + b,
            ) /
            laplacianValues.length;

    double variance = 0;

    for (final value
        in laplacianValues) {

      variance +=
          (value - mean) *
          (value - mean);
    }

    return variance /
        laplacianValues.length;
  }

double _calculateTenengrad(img.Image image) {
  final gray = img.grayscale(image);
  final width = gray.width;
  final height = gray.height;

  double sum = 0.0;
  int count = 0;

  // Sobel kernels
  final gx = [[-1,0,1],[-2,0,2],[-1,0,1]];
  final gy = [[-1,-2,-1],[0,0,0],[1,2,1]];

  for (int y = 1; y < height - 1; y++) {
    for (int x = 1; x < width - 1; x++) {
      double gradX = 0.0;
      double gradY = 0.0;

      for (int ky = -1; ky <= 1; ky++) {
        for (int kx = -1; kx <= 1; kx++) {
          final pixel = gray.getPixel(x + kx, y + ky).r.toDouble();
          gradX += gx[ky + 1][kx + 1] * pixel;
          gradY += gy[ky + 1][kx + 1] * pixel;
        }
      }

      final magnitude = math.sqrt(gradX * gradX + gradY * gradY);
      sum += magnitude;
      count++;
    }
  }

  return sum / count;
}

/// The combined sharpness figure, before any threshold is applied.
///
/// Split out from [isSharpEnough] because the scanning enrollment needs
/// to *rank* frames against each other, not just accept or reject them —
/// a yes/no answer can't tell you which of two usable frames to keep.
double calculateSharpness(img.Image image) {
  final laplacianScore = calculateLaplacianVariance(image);
  final sobelScore = _calculateTenengrad(image);
  return (laplacianScore * 0.6) + (sobelScore * 0.4);
}

bool isSharpEnough(img.Image image, {double? dynamicThreshold}) {
  final threshold = dynamicThreshold ?? QualityThresholds.minSharpness;
  return calculateSharpness(image) > threshold;
}


}