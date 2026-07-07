import 'package:image/image.dart' as img;

class BrightnessService {
  const BrightnessService();

  double calculateBrightness(
  img.Image image,
) {
  double total = 0;

  final count =
      image.width * image.height;

  for (final pixel in image) {
    total +=
        (0.299 * pixel.r) +
        (0.587 * pixel.g) +
        (0.114 * pixel.b);
  }

  return total / count;
}

  bool isBrightnessValid(
    img.Image image,
  ) {
    final brightness =
        calculateBrightness(image);

    return brightness >= 0.25 &&
        brightness <= 0.80;
  }
}