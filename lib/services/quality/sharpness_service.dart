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

bool isSharpEnough(img.Image image, {double? dynamicThreshold}) {
  final laplacianScore = calculateLaplacianVariance(image);
  final sobelScore = _calculateTenengrad(image);

  final threshold = dynamicThreshold ?? QualityThresholds.minSharpness;
  final combinedScore = (laplacianScore * 0.6) + (sobelScore * 0.4);

  ("Sharpness → Laplacian: $laplacianScore, Sobel: $sobelScore, Combined: $combinedScore");

  return combinedScore > threshold;
}


}