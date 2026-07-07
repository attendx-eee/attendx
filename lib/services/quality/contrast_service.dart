import 'package:image/image.dart' as img;
import 'dart:math' as math;

class ContrastService {
  const ContrastService();

  double calculateContrast(
    img.Image image,
  ) {
    final gray = img.grayscale(image);

    double mean = 0;

    final pixelCount =
        gray.width * gray.height;

    for (final pixel in gray) {
      mean += pixel.r;
    }

    mean /= pixelCount;

    double variance = 0;

    for (final pixel in gray) {
      final diff =
          pixel.r - mean;

      variance +=
          diff * diff;
    }

    variance /= pixelCount;

    return math.sqrt(variance);
  }

  bool isContrastValid(
    img.Image image,
    double threshold,
  ) {
    final contrast =
        calculateContrast(image);

    return contrast >= threshold;
  }
}