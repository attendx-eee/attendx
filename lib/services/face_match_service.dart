import 'package:flutter/foundation.dart';
import 'dart:math';

class FaceMatchService {
  
  // Your existing math...
  double cosineSimilarity(List<double> a, List<double> b) {
    double dot = 0;
    double normA = 0;
    double normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    return dot / (sqrt(normA) * sqrt(normB));
  }

bool verifyUser(
  List<double> liveEmbedding,
  List<double> enrolledEmbedding,
  {double threshold = 0.65}
) {

  double score =
      cosineSimilarity(
        liveEmbedding,
        enrolledEmbedding,
      );

  debugPrint("Match Score: $score");

  return score >= threshold;
}
}