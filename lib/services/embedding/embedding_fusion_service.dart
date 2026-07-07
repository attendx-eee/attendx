import 'dart:math' as math;

class EmbeddingFusionService {
  const EmbeddingFusionService();

  List<double> average(List<List<double>> embeddings) {
    if (embeddings.isEmpty) {
      return [];
    }

    final dimension = embeddings.first.length;

    final result = List<double>.filled(dimension, 0.0);

    for (final embedding in embeddings) {
      for (int i = 0; i < dimension; i++) {
        result[i] += embedding[i];
      }
    }

    for (int i = 0; i < dimension; i++) {
      result[i] /= embeddings.length;
    }

    // Normalize the averaged vector
    double magnitude = 0.0;

    for (final value in result) {
      magnitude += value * value;
    }

    magnitude = math.sqrt(magnitude);

    if (magnitude == 0) {
      return result;
    }

    for (int i = 0; i < dimension; i++) {
      result[i] /= magnitude;
    }

    return result;
  }
}