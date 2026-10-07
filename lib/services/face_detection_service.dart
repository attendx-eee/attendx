import 'dart:io';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Finds faces in an image.
///
/// Two profiles, because the two jobs are not alike. Enrolment and login
/// look at one cooperative face filling the frame at arm's length, where
/// speed is what matters and a missed frame costs nothing — there is
/// always another. A classroom sweep looks at eighty faces across a
/// room, most of them small, and a face the detector never reports is a
/// student the system cannot mark no matter how good the recogniser is.
class FaceDetectionService {
  final FaceDetector detector;

  /// Arm's length, one face, speed first.
  FaceDetectionService()
      : detector = FaceDetector(
          options: FaceDetectorOptions(
            performanceMode: FaceDetectorMode.fast,
            enableLandmarks: true,
            enableClassification: true,
            enableTracking: true,
          ),
        );

  /// Across a room, many faces, most of them small.
  ///
  /// Two settings, and the first one was a real hole. ML Kit's
  /// `minFaceSize` defaults to **0.1** — a tenth of the frame's width —
  /// and nothing here had ever set it. The classroom recogniser was
  /// meanwhile willing to work with faces down to 0.055, so on a
  /// 1920-wide frame it would accept a 106px face while the detector
  /// was silently refusing to report anything under 192px. Every
  /// student between those two sizes, which is most of a room past the
  /// front rows, was never detected at all. Not misrecognised — never
  /// seen. No threshold, model or template would have made a difference.
  ///
  /// It is set a little below the recogniser's floor so that detection
  /// is never the thing deciding who can be marked; the recogniser's own
  /// limit, which is about whether the crop carries usable detail,
  /// stays the only limit that matters.
  ///
  /// `accurate` because Google's own guidance is that the fast mode
  /// "will tend to detect fewer faces" — a trade worth making at arm's
  /// length and the wrong one here. It costs runtime, which the frame
  /// stride and the per-frame embedding budget have already paid for.
  ///
  /// Classification is off: a smile and open eyes decide nothing about
  /// attendance, and it is work done on every face in every frame.
  FaceDetectionService.classroom()
      : detector = FaceDetector(
          options: FaceDetectorOptions(
            performanceMode: FaceDetectorMode.accurate,
            minFaceSize: 0.05,
            enableLandmarks: true,
            enableClassification: false,
            enableTracking: true,
          ),
        );

  Future<List<Face>> detectFaces(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    return await detector.processImage(inputImage);
  }

  void dispose() => detector.close();
}
