// Native (Android/iOS/desktop) implementation backed by TensorFlow Lite.
// This file must NEVER be imported directly — always go through
// `../face_embedding_service.dart`, which picks the right implementation
// per platform (tflite_flutter uses dart:ffi, which doesn't exist on web).
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:math' as math;

class FaceEmbeddingService {
  static final FaceEmbeddingService instance = FaceEmbeddingService._internal();

  factory FaceEmbeddingService() {
    return instance;
  }

  FaceEmbeddingService._internal();

  Interpreter? interpreter;

  Future<void> initialize() async {
    if (interpreter != null) {
      return;
    }

    interpreter = await Interpreter.fromAsset(
      'assets/models/mobilefacenet.tflite',
    );

    debugPrint('Input Shape: ${interpreter!.getInputTensor(0).shape}');
    debugPrint('Output Shape: ${interpreter!.getOutputTensor(0).shape}');
  }

  List<double> generateEmbedding(img.Image croppedFace) {
    // 1. Resize to model requirements
    final resized = img.copyResize(croppedFace, width: 112, height: 112);

    // 2. Pre-allocate a 4D Dart List structure matching shape [1, 112, 112, 3]
    var input = List.generate(
      1,
      (_) => List.generate(
        112,
        (_) => List.generate(
          112,
          (_) => List.filled(3, 0.0),
        ),
      ),
    );

    // 3. Populate the 4D array with normalized pixel values
    for (int y = 0; y < 112; y++) {
      for (int x = 0; x < 112; x++) {
        final pixel = resized.getPixel(x, y);

        input[0][y][x][0] = (pixel.r - 127.5) / 127.5; // Red
        input[0][y][x][1] = (pixel.g - 127.5) / 127.5; // Green
        input[0][y][x][2] = (pixel.b - 127.5) / 127.5; // Blue
      }
    }

    // 4. Output buffer matching shape [1, 192]
    var output = List.generate(1, (_) => List.filled(192, 0.0));

    // 5. Run inference
    interpreter!.run(input, output);

    return List<double>.from(output[0]);
  }

  /// Flip test-time-augmentation: runs inference on [croppedFace] AND its
  /// horizontal mirror, then averages the two raw embeddings before
  /// normalizing. This is a standard face-verification accuracy technique
  /// (used in FaceNet/ArcFace/InsightFace deployments) — averaging a face
  /// with its mirror cancels out small left/right lighting and angle
  /// asymmetries that a single frame bakes into the embedding, producing a
  /// more stable, canonical vector. Same identity ends up scoring higher
  /// (closer to 1.0) against itself; a different person's score barely
  /// moves — so it tightens genuine-match confidence without raising
  /// false-accept risk. Costs one extra inference (MobileFaceNet is tiny,
  /// so this is still fast on-device).
  List<double> generateEmbeddingTTA(img.Image croppedFace) {
    final original = generateEmbedding(croppedFace);
    final flipped = generateEmbedding(img.flipHorizontal(croppedFace));

    if (original.length != flipped.length || original.isEmpty) {
      return normalizeEmbedding(original);
    }

    final averaged = List<double>.generate(
      original.length,
      (i) => (original[i] + flipped[i]) / 2,
    );

    return normalizeEmbedding(averaged);
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
