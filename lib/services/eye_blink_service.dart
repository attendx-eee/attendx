import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class BlinkService {
  bool hasSeenEyesOpen = false;
  bool hasSeenEyesClosed = false;

  bool checkBlink(Face face) {
    double leftEyeOpenProb = face.leftEyeOpenProbability ?? 1.0;
    double rightEyeOpenProb = face.rightEyeOpenProbability ?? 1.0;

    if (leftEyeOpenProb > 0.80 && rightEyeOpenProb > 0.80) {
      hasSeenEyesOpen = true;
    }

    if (hasSeenEyesOpen && leftEyeOpenProb < 0.20 && rightEyeOpenProb < 0.20) {
      hasSeenEyesClosed = true;
    }

    if (hasSeenEyesClosed && leftEyeOpenProb > 0.80 && rightEyeOpenProb > 0.80) {
      // Blink cycle completed
      resetBlinkState();
      return true;
    }
    return false;
  }

  void resetBlinkState() {
    hasSeenEyesOpen = false;
    hasSeenEyesClosed = false;
  }
}
