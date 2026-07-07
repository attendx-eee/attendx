import 'package:flutter/material.dart';

import '../models/enrollment_flow_state.dart';

class EnrollmentGuideColorService {
  const EnrollmentGuideColorService();

  Color getColor(EnrollmentFlowState state) {
    switch (state) {
      case EnrollmentFlowState.warmingUp:
        return Colors.grey;

      case EnrollmentFlowState.waitingForFace:
        return Colors.orange;

      case EnrollmentFlowState.aligningFace:
        return Colors.redAccent;

      case EnrollmentFlowState.waitingForBlink:
        return Colors.green;

      case EnrollmentFlowState.waitingForStability:
        return Colors.blue;

      case EnrollmentFlowState.livenessVerified:
        return Colors.green;

      case EnrollmentFlowState.waitingForPose:
        return Colors.deepPurple;

      case EnrollmentFlowState.capturing:
        return Colors.greenAccent;

      case EnrollmentFlowState.processing:
        return Colors.lightBlue;

      case EnrollmentFlowState.uploading:
        return Colors.cyan;

      case EnrollmentFlowState.completed:
        return Colors.green;

      case EnrollmentFlowState.lowLight:
        return Colors.amber;

      case EnrollmentFlowState.failed:
        return Colors.red;

      default:
        return Colors.white;
    }
  }
}