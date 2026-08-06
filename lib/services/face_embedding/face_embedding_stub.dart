// Web stub: TensorFlow Lite (dart:ffi) is unavailable on the web, so this
// keeps the app compiling. All face features are hidden on web, so
// generateEmbedding should never actually be called there.
import 'dart:math' as math;

import 'package:image/image.dart' as img;

class FaceEmbeddingService {
  static final FaceEmbeddingService instance = FaceEmbeddingService._internal();

  factory FaceEmbeddingService() {
    return instance;
  }

  FaceEmbeddingService._internal();

  /// Kept for API parity with the native implementation. Always null here.
  Object? interpreter;

  Future<void> initialize() async {
    // No-op on web — there is no on-device model.
  }

  List<double> generateEmbedding(img.Image croppedFace) {
    throw UnsupportedError(
      'Face recognition is not available on the web. Use the mobile app.',
    );
  }

  /// Kept for API parity with the native implementation — never reachable
  /// on web (face features are hidden there).
  List<double> generateEmbeddingTTA(img.Image croppedFace) {
    throw UnsupportedError(
      'Face recognition is not available on the web. Use the mobile app.',
    );
  }

  List<double> normalizeEmbedding(List<double> embedding) {
    double sum = 0;

    for (double v in embedding) {
      sum += v * v;
    }

    double magnitude = math.sqrt(sum);
    if (magnitude == 0) return embedding;

    return embedding.map((e) => e / magnitude).toList();
  }
}
