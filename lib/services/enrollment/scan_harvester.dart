import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../quality/face_quality_score.dart';

/// A region of head rotation the scan needs to cover.
///
/// Bins are angular, not photographic. The old flow asked for "2 photos
/// facing left"; this asks for "some good frames while your head is
/// between 18 and 34 degrees left", which is a thing a person does
/// naturally while turning their head, and which the camera can satisfy
/// from whichever frames in that window happen to be sharpest.
enum ScanBin {
  centre,
  left,
  farLeft,
  right,
  farRight,
  up,
  down;

  String get label => switch (this) {
        ScanBin.centre => 'Centre',
        ScanBin.left => 'Left',
        ScanBin.farLeft => 'Far left',
        ScanBin.right => 'Right',
        ScanBin.farRight => 'Far right',
        ScanBin.up => 'Up',
        ScanBin.down => 'Down',
      };

  /// The key this bin is stored under in Firestore.
  ///
  /// Centre is written as `front` to match what every earlier enrollment
  /// used. Matching itself iterates whatever keys it finds, so the name
  /// is irrelevant there — but other code has looked for `front` by name
  /// to decide whether a face is enrolled at all, and inventing a new
  /// vocabulary silently broke it. Keeping the shared name costs nothing
  /// and avoids a whole class of bug.
  String get storageKey => this == ScanBin.centre ? 'front' : name;
}

/// One accepted frame: its embedding and what it scored.
class ScanSample {
  final List<double> embedding;
  final FaceQuality quality;
  final ScanBin bin;

  const ScanSample({
    required this.embedding,
    required this.quality,
    required this.bin,
  });
}

/// What the harvester decided about a frame — drives the on-screen hint.
enum ScanFeedback {
  /// Kept, and it improved the bin.
  accepted,

  /// Fine, but this bin already holds better frames.
  redundant,

  /// Too similar to something already kept — a still head produces these
  /// endlessly and they add nothing to a template.
  duplicate,

  /// Failed quality. [ScanHarvester.lastFailure] says why.
  poorQuality,

  /// Head isn't in any bin the scan still needs.
  outOfRange,
}

/// Collects the best frames from a continuous head-turn scan.
///
/// The design goal is that enrollment feels like a scan rather than a
/// photo shoot: the student sweeps their head, the camera runs flat out,
/// and the decision about *which* frames end up in the template is made
/// here, silently, by quality — never by asking the student to hold
/// still and pose for a count.
///
/// Two ideas from the face-recognition literature shape this:
///
/// - Aggregating ~10 or more embeddings is where verification accuracy
///   stops improving, so the targets below add up to roughly that.
/// - *Which* frames you aggregate matters more than how many: selecting
///   the best few, spread across frontal and profile views, recovers
///   most of the available accuracy. Hence per-bin best-K rather than
///   "the first K that passed".
/// How thorough a scan needs to be.
///
/// Students are matched by a camera at the door and, from this release,
/// by a phone sweeping a classroom — at distance, at whatever angle they
/// happen to be sitting. That demands a wide template.
///
/// Staff are only ever matched one-to-one, close up, having deliberately
/// presented themselves to confirm who they are. A frontal template is
/// enough for that, and asking a lecturer to sweep their head through
/// seven positions for a convenience feature is a good way to have them
/// not bother.
enum ScanProfile {
  /// Seven angle bins, ~15 frames. Used for students.
  full,

  /// Frontal only, but more of it — six good frames instead of four,
  /// since there's no angular spread to lend the template variety.
  frontalOnly,
}

class ScanHarvester {
  final ScanProfile profile;

  ScanHarvester({this.profile = ScanProfile.full});

  /// How many frames to keep per bin. Small on purpose — these are the
  /// best of potentially hundreds, and a bin's second-best frame is
  /// already very close to its best.
  static const Map<ScanBin, int> _fullTargets = {
    ScanBin.centre: 4,
    ScanBin.left: 2,
    ScanBin.farLeft: 2,
    ScanBin.right: 2,
    ScanBin.farRight: 2,
    ScanBin.up: 2,
    ScanBin.down: 2,
  };

  static const Map<ScanBin, int> _frontalTargets = {ScanBin.centre: 6};

  Map<ScanBin, int> get targets =>
      profile == ScanProfile.full ? _fullTargets : _frontalTargets;

  /// Bins the scan cannot finish without. The extremes are desirable but
  /// optional: some people simply won't turn far enough, and refusing to
  /// enroll them over it is worse than a slightly narrower template.
  static const Set<ScanBin> _fullRequired = {
    ScanBin.centre,
    ScanBin.left,
    ScanBin.right,
  };

  Set<ScanBin> get requiredBins =>
      profile == ScanProfile.full ? _fullRequired : const {ScanBin.centre};

  /// Above this cosine similarity a frame is the same frame again — the
  /// head barely moved between captures. Keeping both would weight the
  /// template towards whichever moment the student happened to pause.
  static const double duplicateCeiling = 0.985;

  /// The template is rejected below this mean quality even if every
  /// required bin filled up.
  static const double minTemplateScore = 55;

  final Map<ScanBin, List<ScanSample>> _bins = {
    for (final bin in ScanBin.values) bin: <ScanSample>[],
  };

  /// Why the last frame was rejected, for the on-screen hint.
  String? lastFailure;

  int _framesSeen = 0;
  int _framesKept = 0;

  int get framesSeen => _framesSeen;
  int get framesKept => _framesKept;

  /// Which bin a head at this angle belongs to, or null if it's between
  /// bins (the gaps are deliberate — they stop a slow sweep from
  /// dribbling near-identical frames into two neighbouring bins).
  static ScanBin? binFor(double yaw, double pitch) {
    final absYaw = yaw.abs();
    final absPitch = pitch.abs();

    // Vertical bins are only considered while the head is roughly
    // square-on horizontally; a head both turned and tilted is an
    // awkward view that matches poorly against anything.
    if (absYaw <= 12) {
      if (pitch <= -14 && pitch >= -32) return ScanBin.up;
      if (pitch >= 14 && pitch <= 32) return ScanBin.down;
    }

    if (absPitch > 14) return null;

    if (absYaw <= 8) return ScanBin.centre;

    if (yaw < 0) {
      if (yaw <= -16 && yaw >= -30) return ScanBin.left;
      if (yaw < -30 && yaw >= -50) return ScanBin.farLeft;
      return null;
    }

    if (yaw >= 16 && yaw <= 30) return ScanBin.right;
    if (yaw > 30 && yaw <= 50) return ScanBin.farRight;
    return null;
  }

  static double _cosine(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0;
    double dot = 0, na = 0, nb = 0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    final denom = math.sqrt(na) * math.sqrt(nb);
    return denom == 0 ? 0 : dot / denom;
  }

  /// Offers a frame to the harvester.
  ///
  /// Cheap enough to call on every camera frame: the expensive work
  /// (quality measurement, embedding) has already happened by the time
  /// this is reached, and the rejection paths below are all O(bin size),
  /// where a bin holds at most four entries.
  ScanFeedback offer({
    required List<double> embedding,
    required FaceQuality quality,
  }) {
    _framesSeen++;
    lastFailure = null;

    if (!quality.isUsable) {
      lastFailure = quality.primaryFailure;
      return ScanFeedback.poorQuality;
    }

    if (quality.score < FaceQualityScorer.minKeepScore) {
      lastFailure = 'Hold steady';
      return ScanFeedback.poorQuality;
    }

    final bin = binFor(quality.yaw, quality.pitch);
    if (bin == null) return ScanFeedback.outOfRange;

    final samples = _bins[bin]!;

    for (final existing in samples) {
      if (_cosine(embedding, existing.embedding) > duplicateCeiling) {
        // Nearly the same view — but if this one is sharper, swap it in
        // rather than discarding it. Over a sweep this quietly upgrades
        // each bin towards its best possible frame.
        if (quality.score > existing.quality.score + 3) {
          samples.remove(existing);
          samples.add(ScanSample(
            embedding: embedding,
            quality: quality,
            bin: bin,
          ));
          _framesKept++;
          return ScanFeedback.accepted;
        }
        return ScanFeedback.duplicate;
      }
    }

    // A frontal-only profile has no target for the side bins, so frames
    // from those angles are simply not wanted.
    final target = targets[bin] ?? 0;
    if (target == 0) return ScanFeedback.outOfRange;

    if (samples.length < target) {
      samples.add(
          ScanSample(embedding: embedding, quality: quality, bin: bin));
      _framesKept++;
      return ScanFeedback.accepted;
    }

    // Bin is full: keep this frame only if it beats the weakest one in
    // it. This is what makes a longer sweep produce a better template
    // instead of just a bigger one.
    samples.sort((a, b) => a.quality.score.compareTo(b.quality.score));
    final weakest = samples.first;

    if (quality.score > weakest.quality.score + 2) {
      samples.removeAt(0);
      samples.add(
          ScanSample(embedding: embedding, quality: quality, bin: bin));
      _framesKept++;
      return ScanFeedback.accepted;
    }

    return ScanFeedback.redundant;
  }

  /// 0-1 completion for a bin. Bins this profile doesn't collect read as
  /// complete, so they never hold up progress.
  double progressFor(ScanBin bin) {
    final target = targets[bin] ?? 0;
    if (target == 0) return 1;
    return (_bins[bin]!.length / target).clamp(0.0, 1.0);
  }

  /// 0-1 across every required bin — what the progress ring shows.
  double get progress {
    var filled = 0.0;
    for (final bin in requiredBins) {
      filled += progressFor(bin);
    }
    return (filled / requiredBins.length).clamp(0.0, 1.0);
  }

  bool isBinComplete(ScanBin bin) =>
      _bins[bin]!.length >= (targets[bin] ?? 0);

  /// Every required bin has its quota.
  bool get hasRequiredCoverage => requiredBins.every(isBinComplete);

  /// Bins still short of their quota, required ones first — this is what
  /// picks the next instruction to show.
  List<ScanBin> get outstandingBins {
    final required = requiredBins.where((b) => !isBinComplete(b)).toList();
    final optional = ScanBin.values
        .where((b) =>
            (targets[b] ?? 0) > 0 &&
            !requiredBins.contains(b) &&
            !isBinComplete(b))
        .toList();
    return [...required, ...optional];
  }

  int get sampleCount =>
      _bins.values.fold(0, (acc, list) => acc + list.length);

  List<ScanSample> get allSamples =>
      [for (final list in _bins.values) ...list];

  /// Mean quality of everything kept — the headline number on the
  /// enrollment scorecard.
  double get meanQuality {
    final samples = allSamples;
    if (samples.isEmpty) return 0;
    return samples.map((s) => s.quality.score).reduce((a, b) => a + b) /
        samples.length;
  }

  /// How many distinct bins hold at least one frame. A template spread
  /// over six bins generalises better than one with the same number of
  /// frames crowded into two.
  int get binsCovered =>
      _bins.values.where((list) => list.isNotEmpty).length;

  /// Embeddings grouped by bin name, ready for the enrollment document.
  ///
  /// Grouped rather than flattened because the matcher scores a live
  /// face against each pose group and takes the best — averaging a
  /// front-facing template together with a profile one produces a vector
  /// that resembles neither.
  Map<String, List<List<double>>> groupedEmbeddings() {
    final out = <String, List<List<double>>>{};
    _bins.forEach((bin, samples) {
      if (samples.isEmpty) return;
      // Best first, so anything downstream that truncates keeps the good
      // ones.
      final sorted = [...samples]
        ..sort((a, b) => b.quality.score.compareTo(a.quality.score));
      out[bin.storageKey] = sorted.map((s) => s.embedding).toList();
    });
    return out;
  }

  /// Quality-weighted mean of one bin's embeddings, L2-normalised.
  ///
  /// Weighting by quality rather than taking a flat mean stops one
  /// marginal frame from dragging a bin's representative vector away
  /// from the three good ones beside it.
  static List<double> weightedFuse(List<ScanSample> samples) {
    if (samples.isEmpty) return const [];

    final dim = samples.first.embedding.length;
    final acc = List<double>.filled(dim, 0);
    var totalWeight = 0.0;

    for (final s in samples) {
      // Squared so the gap between a good and a mediocre frame actually
      // tells, instead of everything landing within a few percent.
      final w = math.pow(s.quality.score / 100, 2).toDouble();
      if (w <= 0) continue;
      totalWeight += w;
      for (var i = 0; i < dim; i++) {
        acc[i] += s.embedding[i] * w;
      }
    }

    if (totalWeight == 0) return const [];

    var magnitude = 0.0;
    for (var i = 0; i < dim; i++) {
      acc[i] /= totalWeight;
      magnitude += acc[i] * acc[i];
    }

    magnitude = math.sqrt(magnitude);
    if (magnitude == 0) return acc;

    for (var i = 0; i < dim; i++) {
      acc[i] /= magnitude;
    }
    return acc;
  }

  /// One representative vector per covered bin.
  Map<String, List<double>> fusedByBin() {
    final out = <String, List<double>>{};
    _bins.forEach((bin, samples) {
      if (samples.isEmpty) return;
      final fused = weightedFuse(samples);
      if (fused.isNotEmpty) out[bin.storageKey] = fused;
    });
    return out;
  }

  /// Final verdict on the harvest.
  EnrollmentGrade grade() {
    final samples = allSamples;

    if (!hasRequiredCoverage) {
      final missing =
          requiredBins.where((b) => !isBinComplete(b)).map((b) => b.label);
      return EnrollmentGrade(
        passed: false,
        meanQuality: meanQuality,
        sampleCount: samples.length,
        binsCovered: binsCovered,
        reason: 'The scan missed ${missing.join(', ')}. '
            'Turn your head slowly all the way through each direction.',
      );
    }

    if (meanQuality < minTemplateScore) {
      return EnrollmentGrade(
        passed: false,
        meanQuality: meanQuality,
        sampleCount: samples.length,
        binsCovered: binsCovered,
        reason: 'The frames captured were too poor to enroll from. '
            'Move somewhere brighter and scan again, keeping the phone '
            'steady.',
      );
    }

    return EnrollmentGrade(
      passed: true,
      meanQuality: meanQuality,
      sampleCount: samples.length,
      binsCovered: binsCovered,
      reason: null,
    );
  }

  void reset() {
    for (final list in _bins.values) {
      list.clear();
    }
    _framesSeen = 0;
    _framesKept = 0;
    lastFailure = null;
  }

  void debugDump() {
    _bins.forEach((bin, samples) {
      debugPrint('${bin.name}: ${samples.length}/${targets[bin]} '
          '${samples.map((s) => s.quality.score.toStringAsFixed(0)).join(",")}');
    });
  }
}

/// The scorecard stored alongside the template.
///
/// Kept on the enrollment document so a later false rejection can be
/// explained ("this template was built from six poor frames") instead of
/// guessed at, and so an admin can find and re-enroll the weak ones
/// before they cause trouble at the gate.
class EnrollmentGrade {
  final bool passed;
  final double meanQuality;
  final int sampleCount;
  final int binsCovered;

  /// Why it failed, in words a student can act on. Null when passed.
  final String? reason;

  const EnrollmentGrade({
    required this.passed,
    required this.meanQuality,
    required this.sampleCount,
    required this.binsCovered,
    required this.reason,
  });

  /// Coarse band for display.
  String get band {
    if (meanQuality >= 78) return 'excellent';
    if (meanQuality >= 66) return 'good';
    if (meanQuality >= 55) return 'fair';
    return 'poor';
  }

  Map<String, dynamic> toMap() => {
        'meanQuality': double.parse(meanQuality.toStringAsFixed(2)),
        'sampleCount': sampleCount,
        'binsCovered': binsCovered,
        'band': band,
      };
}
