import 'dart:math' as math;

import '../../models/quality_thresholds.dart';

/// A single frame's measured quality, plus the unified score derived
/// from it.
///
/// The app already measures sharpness, brightness, contrast, occupancy,
/// centering and head pose separately, and until now used each one as an
/// independent pass/fail gate. A gate can only ever answer "is this
/// usable" — it can't answer "is this one better than that one", which
/// is exactly the question a continuous scan has to answer hundreds of
/// times a second as frames stream past.
///
/// So the sub-measures are also folded into one 0-100 scalar, the same
/// shape as the unified quality score in ISO/IEC 29794-5 (whose whole
/// premise is that a scalar predicting recognition outcome is what lets
/// you rank and discard samples). The weights below are ours, not the
/// standard's — this is the pattern, not an implementation of it.
class FaceQuality {
  /// Laplacian variance. Higher is sharper.
  final double sharpness;

  /// Mean luma, 0-255.
  final double brightness;

  /// Luma standard deviation.
  final double contrast;

  /// Face box area as a fraction of the frame.
  final double occupancy;

  /// Distance of the face centre from the frame centre, as a fraction of
  /// the frame's half-diagonal. 0 = dead centre.
  final double centerOffset;

  final double yaw;
  final double pitch;
  final double roll;

  /// 0-100. Higher is better.
  final double score;

  /// Every reason this frame is unusable. Empty means it passed.
  final List<String> failures;

  const FaceQuality({
    required this.sharpness,
    required this.brightness,
    required this.contrast,
    required this.occupancy,
    required this.centerOffset,
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.score,
    required this.failures,
  });

  bool get isUsable => failures.isEmpty;

  /// The single worst thing about this frame — what to actually tell the
  /// student. Showing all six failures at once is noise they can't act on.
  String? get primaryFailure => failures.isEmpty ? null : failures.first;

  @override
  String toString() =>
      'FaceQuality(score: ${score.toStringAsFixed(1)}, '
      'sharp: ${sharpness.toStringAsFixed(0)}, '
      'bright: ${brightness.toStringAsFixed(0)}, '
      'yaw: ${yaw.toStringAsFixed(1)})';
}

/// Scores a captured frame and says whether it's fit to enroll.
class FaceQualityScorer {
  const FaceQualityScorer._();

  static const FaceQualityScorer instance = FaceQualityScorer._();

  // ------------------------------------------------------------------
  // Weights. Sharpness dominates deliberately: a blurred face is the one
  // defect that no amount of good lighting or framing rescues, and it's
  // also the defect a moving head produces most often — which is the
  // whole situation a scanning enrollment puts the camera in.
  // ------------------------------------------------------------------
  static const double _wSharpness = 0.34;
  static const double _wBrightness = 0.18;
  static const double _wContrast = 0.14;
  static const double _wOccupancy = 0.14;
  static const double _wCentering = 0.10;
  static const double _wPose = 0.10;

  /// Frames below this are never kept, however few we have. A template
  /// built from bad frames is worse than a short one — it teaches the
  /// matcher the wrong thing about a face.
  static const double minKeepScore = 45;

  /// A frame at or above this is good enough to stop looking for better
  /// in that part of the sweep.
  static const double excellentScore = 78;

  /// Sharpness needed at all, before scoring. Below this the frame is
  /// motion-blurred and its embedding is noise.
  static const double _hardSharpnessFloor = 120;

  /// Maps a value to 0-1 by how close it sits to the middle of an
  /// acceptable band, so "comfortably mid-range" beats "only just legal".
  static double _bandScore(double value, double min, double max) {
    if (max <= min) return 0;
    if (value <= min || value >= max) return 0;

    final mid = (min + max) / 2;
    final halfSpan = (max - min) / 2;
    return (1 - ((value - mid).abs() / halfSpan)).clamp(0.0, 1.0);
  }

  /// Maps an open-ended "more is better" value to 0-1, flattening out
  /// once it's comfortably past [good] — a razor-sharp frame isn't twice
  /// as useful as a sharp one.
  static double _risingScore(double value, double floor, double good) {
    if (value <= floor) return 0;
    if (value >= good) return 1;
    return ((value - floor) / (good - floor)).clamp(0.0, 1.0);
  }

  /// Smaller is better, reaching 0 at [worst].
  static double _fallingScore(double value, double worst) {
    if (worst <= 0) return 0;
    return (1 - (value.abs() / worst)).clamp(0.0, 1.0);
  }

  /// Scores one frame.
  ///
  /// [sharpnessThreshold] comes from the per-device table — the same
  /// lens produces very different Laplacian variance across phones, so a
  /// fixed number would over-reject on soft cameras and under-reject on
  /// crisp ones.
  ///
  /// [maxYaw] is passed in rather than taken from QualityThresholds
  /// because a scanning enrollment deliberately wants off-centre frames:
  /// during the sweep a 30 degree yaw is the point, not a defect.
  FaceQuality score({
    required double sharpness,
    required double brightness,
    required double contrast,
    required double occupancy,
    required double centerOffset,
    required double yaw,
    required double pitch,
    required double roll,
    required double sharpnessThreshold,
    double maxYaw = QualityThresholds.maxYaw,
    double maxPitch = QualityThresholds.maxPitch,
    double maxRoll = QualityThresholds.maxRoll,
  }) {
    final failures = <String>[];

    // Ordered by how actionable the message is: a student can fix their
    // framing and their lighting; they can't fix "contrast".
    if (occupancy < QualityThresholds.minFaceOccupancy) {
      failures.add('Move closer');
    } else if (occupancy > QualityThresholds.maxFaceOccupancy) {
      failures.add('Move back a little');
    }

    // Centring is scored but never fails a frame.
    //
    // It still nudges the ranking below — given two otherwise equal
    // frames, the better-centred one is preferable — but a face that
    // ML Kit found, at a sensible size, in decent light, is usable
    // wherever it sits in the preview. Treating it as a hard failure
    // rejected good frames on handsets where the offset reads high for
    // reasons that have nothing to do with the student.

    if (brightness < QualityThresholds.minBrightness) {
      failures.add('Find brighter light');
    } else if (brightness > QualityThresholds.maxBrightness) {
      failures.add('Too bright — move out of direct light');
    }

    if (sharpness < math.max(_hardSharpnessFloor, sharpnessThreshold)) {
      failures.add('Hold steady');
    }

    if (contrast < QualityThresholds.minContrast) {
      failures.add('Lighting is too flat');
    }

    if (roll.abs() > maxRoll) {
      failures.add('Keep your head upright');
    }

    if (yaw.abs() > maxYaw) {
      failures.add('Turn back towards the camera');
    }

    if (pitch.abs() > maxPitch) {
      failures.add('Level your head');
    }

    // Sub-scores. Each is 0-1; the weighted sum becomes the 0-100 score.
    final sharpnessScore =
        _risingScore(sharpness, sharpnessThreshold, sharpnessThreshold * 3);

    final brightnessScore = _bandScore(
      brightness,
      QualityThresholds.minBrightness,
      QualityThresholds.maxBrightness,
    );

    final contrastScore =
        _risingScore(contrast, QualityThresholds.minContrast, 75);

    final occupancyScore = _bandScore(
      occupancy,
      QualityThresholds.minFaceOccupancy,
      QualityThresholds.maxFaceOccupancy,
    );

    final centeringScore = _fallingScore(centerOffset, 0.5);

    // Pose contributes via roll only. Yaw and pitch are the axes the
    // sweep is deliberately moving through, so penalising them here
    // would rank the whole point of the exercise as poor quality.
    final poseScore = _fallingScore(roll, maxRoll);

    final raw = sharpnessScore * _wSharpness +
        brightnessScore * _wBrightness +
        contrastScore * _wContrast +
        occupancyScore * _wOccupancy +
        centeringScore * _wCentering +
        poseScore * _wPose;

    return FaceQuality(
      sharpness: sharpness,
      brightness: brightness,
      contrast: contrast,
      occupancy: occupancy,
      centerOffset: centerOffset,
      yaw: yaw,
      pitch: pitch,
      roll: roll,
      score: (raw * 100).clamp(0.0, 100.0),
      failures: failures,
    );
  }
}
