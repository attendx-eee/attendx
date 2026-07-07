// models/calibration_frame.dart
import 'dart:io';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

class CalibrationFrame {
  final File file;
  final Face face;
  final img.Image? croppedFace;

  CalibrationFrame({
    required this.file,
    required this.face,
    this.croppedFace,
  });
}

