import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import '../../models/get_device_model.dart';
import '../../models/quality_thresholds.dart';

class CalibrationService {
  double? calibratedSharpnessThreshold;

  Future<void> calibrateSharpnessThreshold(
      Future<List<double>> Function() collectScores) async {
    final scores = await collectScores();
    if (scores.isEmpty) return;

    scores.sort();
    final median = scores[scores.length ~/ 2];

    final deviceModel = await getDeviceModel();
    final deviceBaseline =
        DeviceQualityThresholds.getSharpnessThreshold(deviceModel);

    calibratedSharpnessThreshold = math.max(deviceBaseline, median * 0.6);

    debugPrint("Calibrated sharpness threshold for $deviceModel → $calibratedSharpnessThreshold");
  }
}

