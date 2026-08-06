import 'package:flutter/material.dart';

import '../models/enrollment_flow_state.dart';
import '../models/enrollment_guide_style.dart';

class EnrollmentGuideStyleService {
  const EnrollmentGuideStyleService();

  EnrollmentGuideStyle getStyle(EnrollmentFlowState state) {
    switch (state) {
      case EnrollmentFlowState.warmingUp:
        return const EnrollmentGuideStyle(
          borderColor: Colors.grey,
          iconColor: Colors.grey,
          textColor: Colors.white,
          icon: Icons.hourglass_empty,
        );

      case EnrollmentFlowState.waitingForFace:
        return const EnrollmentGuideStyle(
          borderColor: Colors.orange,
          iconColor: Colors.orange,
          textColor: Colors.white,
          icon: Icons.face,
        );

      case EnrollmentFlowState.aligningFace:
        return const EnrollmentGuideStyle(
          borderColor: Colors.redAccent,
          iconColor: Colors.redAccent,
          textColor: Colors.white,
          icon: Icons.center_focus_strong,
        );

      case EnrollmentFlowState.waitingForBlink:
        return const EnrollmentGuideStyle(
          borderColor: Colors.green,
          iconColor: Colors.green,
          textColor: Colors.white,
          icon: Icons.remove_red_eye,
        );

      case EnrollmentFlowState.waitingForStability:
        return const EnrollmentGuideStyle(
          borderColor: Colors.blue,
          iconColor: Colors.blue,
          textColor: Colors.white,
          icon: Icons.pan_tool_alt,
        );

      case EnrollmentFlowState.livenessVerified:
        return const EnrollmentGuideStyle(
          borderColor: Colors.green,
          iconColor: Colors.green,
          textColor: Colors.white,
          icon: Icons.verified_user,
        );

      case EnrollmentFlowState.waitingForPose:
        return const EnrollmentGuideStyle(
          borderColor: Colors.deepPurple,
          iconColor: Colors.deepPurple,
          textColor: Colors.white,
          icon: Icons.threed_rotation,
        );

      case EnrollmentFlowState.capturing:
        return const EnrollmentGuideStyle(
          borderColor: Colors.greenAccent,
          iconColor: Colors.greenAccent,
          textColor: Colors.white,
          icon: Icons.camera_alt,
        );

      case EnrollmentFlowState.processing:
        return const EnrollmentGuideStyle(
          borderColor: Colors.lightBlue,
          iconColor: Colors.lightBlue,
          textColor: Colors.white,
          icon: Icons.memory,
        );

      case EnrollmentFlowState.checkingDuplicate:
        return const EnrollmentGuideStyle(
          borderColor: Colors.cyan,
          iconColor: Colors.cyan,
          textColor: Colors.white,
          icon: Icons.fact_check_outlined,
        );

      case EnrollmentFlowState.uploading:
        return const EnrollmentGuideStyle(
          borderColor: Colors.cyan,
          iconColor: Colors.cyan,
          textColor: Colors.white,
          icon: Icons.cloud_upload,
        );

      case EnrollmentFlowState.completed:
        return const EnrollmentGuideStyle(
          borderColor: Colors.green,
          iconColor: Colors.green,
          textColor: Colors.white,
          icon: Icons.check_circle,
        );

      case EnrollmentFlowState.lowLight:
        return const EnrollmentGuideStyle(
          borderColor: Colors.amber,
          iconColor: Colors.amber,
          textColor: Colors.white,
          icon: Icons.lightbulb,
        );

      case EnrollmentFlowState.failed:
        return const EnrollmentGuideStyle(
          borderColor: Colors.red,
          iconColor: Colors.red,
          textColor: Colors.white,
          icon: Icons.error,
        );

      default:
        return const EnrollmentGuideStyle(
          borderColor: Colors.white,
          iconColor: Colors.white,
          textColor: Colors.white,
          icon: Icons.help_outline,
        );
    }
  }
}