import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class OccupancyService {
  const OccupancyService();

  double calculateOccupancy({
    required Face face,
    required double frameWidth,
    required double frameHeight,
  }) {
    final faceArea =
        face.boundingBox.width *
        face.boundingBox.height;

    final frameArea =
        frameWidth *
        frameHeight;

    return faceArea / frameArea;
  }

  bool isOccupancyValid(
    double occupancy,
    double min,
    double max,
  ) {
    return occupancy >= min &&
           occupancy <= max;
  }
}