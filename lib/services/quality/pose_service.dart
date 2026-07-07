import '../../models/face_pose.dart';
import '../../models/quality_thresholds.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class PoseResult {
  final FacePose pose;

  final bool accepted;

  final double yaw;

  final double pitch;

  final double roll;

  const PoseResult({
    required this.pose,
    required this.accepted,
    required this.yaw,
    required this.pitch,
    required this.roll,
  });
}

class PoseService {
  const PoseService();

  PoseResult evaluate(
    Face face,
  ) {
    final yaw =
        face.headEulerAngleY ?? 0;

    final pitch =
        face.headEulerAngleX ?? 0;

    final roll =
        face.headEulerAngleZ ?? 0;

    FacePose pose =
        FacePose.invalid;

    if (yaw.abs() < 10 &&
        pitch.abs() < 10 &&
        roll.abs() < 10) {
      pose = FacePose.front;
    }
    else if (yaw > 15 &&
             yaw < 35) {
      pose = FacePose.left;
    }
    else if (yaw < -15 &&
             yaw > -35) {
      pose = FacePose.right;
    }
    else if (pitch > 15 &&
             pitch < 30) {
      pose = FacePose.up;
    }
    else if (pitch < -15 &&
             pitch > -30) {
      pose = FacePose.down;
    }

    final accepted =
        yaw.abs() <=
            QualityThresholds.maxYaw &&
        pitch.abs() <=
            QualityThresholds.maxPitch &&
        roll.abs() <=
            QualityThresholds.maxRoll;

    return PoseResult(
      pose: pose,
      accepted: accepted,
      yaw: yaw,
      pitch: pitch,
      roll: roll,
    );
  }


  FacePose detect(Face face) {

  final yaw = face.headEulerAngleY ?? 0;
  final pitch = face.headEulerAngleX ?? 0;

  if (yaw > 15) {
    return FacePose.left;
  }

  if (yaw < -15) {
    return FacePose.right;
  }

  if (pitch > 12) {
    return FacePose.up;
  }

  if (pitch < -12) {
    return FacePose.down;
  }

  return FacePose.front;
}
}

