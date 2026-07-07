import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// A face enrollment candidate loaded from Firestore.
class FaceCandidate {
  final String uid;

  /// pose name -> 192-dim embedding
  final Map<String, List<double>> poseEmbeddings;

  /// Fused all-pose vector used for fast prefiltering.
  final List<double> centroid;

  const FaceCandidate({
    required this.uid,
    required this.poseEmbeddings,
    required this.centroid,
  });

  factory FaceCandidate.fromDoc(String uid, Map<String, dynamic> data) {
    final raw = data['embeddings'];
    final poses = <String, List<double>>{};

    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is List) {
          poses[key.toString()] =
              value.map((e) => (e as num).toDouble()).toList();
        }
      });
    }

    List<double> centroid;
    final storedCentroid = data['centroid'];

    if (storedCentroid is List && storedCentroid.isNotEmpty) {
      centroid = storedCentroid.map((e) => (e as num).toDouble()).toList();
    } else {
      // Older v1 enrollments have no centroid — derive one on the fly.
      centroid = AdaptiveFaceService.fuse(poses.values.toList());
    }

    return FaceCandidate(
      uid: uid,
      poseEmbeddings: poses,
      centroid: centroid,
    );
  }
}

/// Outcome of an identification attempt.
class FaceIdentityResult {
  final String? uid;
  final String bestPose;
  final double bestScore;

  /// Gap between the best candidate and the runner-up (1:N only).
  final double margin;

  final bool accepted;

  const FaceIdentityResult({
    required this.uid,
    required this.bestPose,
    required this.bestScore,
    required this.margin,
    required this.accepted,
  });
}

/// Face matching that learns and grows:
///
/// - identify(): centroid prefilter (fast), pose-level scoring for the top
///   candidates only, and a runner-up margin check so two similar-looking
///   students can never be confused silently.
/// - learnFromMatch(): after every confident verification the matched pose
///   template is nudged toward the live embedding (exponential moving
///   average), so the profile keeps up with glasses, hairstyles, lighting
///   and aging. Original enrollment vectors are kept as immutable anchors —
///   adaptation that drifts too far from the anchor is rejected, which
///   prevents template poisoning.
/// - Tracks a rolling match-score average; when it decays, the profile is
///   flagged so the student can be advised to re-enroll.
class AdaptiveFaceService {
  AdaptiveFaceService._();

  static final AdaptiveFaceService instance = AdaptiveFaceService._();

  // ------------------------------------------------------------- tuning
  /// Minimum similarity to accept a match at all.
  static const double matchThreshold = 0.75;

  /// In 1:N mode the winner must beat the runner-up by this much.
  static const double identificationMargin = 0.04;

  /// Only learn from matches at least this confident...
  static const double learnThreshold = 0.82;

  /// ...but skip near-identical frames (nothing new to learn).
  static const double nearDuplicateCeiling = 0.995;

  /// How far each verification pulls the template (0 = frozen, 1 = replace).
  static const double adaptationRate = 0.15;

  /// Adapted template must stay at least this similar to its anchor.
  static const double anchorDriftFloor = 0.60;

  /// Rolling-average decay flagging: suggest re-enroll below this score...
  static const double agingScoreFloor = 0.78;

  /// ...once we have enough samples to trust the average.
  static const int agingMinSamples = 10;

  /// Pose-level scan is limited to the strongest candidates by centroid.
  static const int prefilterTopK = 3;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // -------------------------------------------------------------- math

  static double cosine(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return -1.0;

    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denom = math.sqrt(normA) * math.sqrt(normB);
    return denom == 0 ? -1.0 : dot / denom;
  }

  static List<double> normalize(List<double> v) {
    double sum = 0;
    for (final x in v) {
      sum += x * x;
    }
    final mag = math.sqrt(sum);
    if (mag == 0) return v;
    return v.map((x) => x / mag).toList();
  }

  /// Average multiple embeddings into one normalized vector.
  static List<double> fuse(List<List<double>> embeddings) {
    final valid = embeddings.where((e) => e.isNotEmpty).toList();
    if (valid.isEmpty) return [];

    final dim = valid.first.length;
    final out = List<double>.filled(dim, 0.0);

    for (final e in valid) {
      if (e.length != dim) continue;
      for (int i = 0; i < dim; i++) {
        out[i] += e[i];
      }
    }
    for (int i = 0; i < dim; i++) {
      out[i] /= valid.length;
    }

    return normalize(out);
  }

  // ---------------------------------------------------------- identify

  /// Matches [live] against [candidates].
  ///
  /// Efficient at scale: every candidate is scored once against its
  /// centroid, then only the top [prefilterTopK] get the detailed
  /// per-pose comparison.
  FaceIdentityResult identify(
    List<double> live,
    List<FaceCandidate> candidates,
  ) {
    if (candidates.isEmpty) {
      return const FaceIdentityResult(
          uid: null, bestPose: '', bestScore: -1, margin: 0, accepted: false);
    }

    // Stage 1: centroid prefilter.
    final ranked = candidates
        .map((c) => MapEntry(c, cosine(live, c.centroid)))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final shortlist = ranked.take(prefilterTopK).map((e) => e.key).toList();

    // Stage 2: pose-level scoring on the shortlist.
    String? bestUid;
    String bestPose = '';
    double bestScore = -1.0;
    double secondBestOtherUser = -1.0;

    for (final candidate in shortlist) {
      double candidateBest = -1.0;
      String candidatePose = '';

      candidate.poseEmbeddings.forEach((pose, vector) {
        final s = cosine(live, vector);
        if (s > candidateBest) {
          candidateBest = s;
          candidatePose = pose;
        }
      });

      if (candidateBest > bestScore) {
        if (bestUid != null && bestUid != candidate.uid) {
          secondBestOtherUser = math.max(secondBestOtherUser, bestScore);
        }
        bestScore = candidateBest;
        bestPose = candidatePose;
        bestUid = candidate.uid;
      } else if (candidate.uid != bestUid) {
        secondBestOtherUser = math.max(secondBestOtherUser, candidateBest);
      }
    }

    final margin =
        secondBestOtherUser < 0 ? 1.0 : bestScore - secondBestOtherUser;

    final passesThreshold = bestScore >= matchThreshold;
    final passesMargin =
        candidates.length <= 1 || margin >= identificationMargin;

    return FaceIdentityResult(
      uid: bestUid,
      bestPose: bestPose,
      bestScore: bestScore,
      margin: margin,
      accepted: passesThreshold && passesMargin,
    );
  }

  // ------------------------------------------------------------- learn

  /// Adapts the matched pose template toward [live] after a confident
  /// verification, updates the centroid and rolling stats.
  ///
  /// Returns true if the template was adapted. Never throws — learning
  /// must never break a successful login.
  Future<bool> learnFromMatch({
    required String uid,
    required List<double> live,
    required FaceIdentityResult result,
  }) async {
    try {
      if (result.uid != uid || result.bestPose.isEmpty) return false;

      final docRef =
          _firestore.collection('student_face_enrollments').doc(uid);
      final snapshot = await docRef.get();
      if (!snapshot.exists) return false;

      final data = snapshot.data()!;
      final rawEmbeddings = data['embeddings'];
      if (rawEmbeddings is! Map) return false;

      final poses = <String, List<double>>{};
      rawEmbeddings.forEach((key, value) {
        if (value is List) {
          poses[key.toString()] =
              value.map((e) => (e as num).toDouble()).toList();
        }
      });

      // Migrate v1 docs: freeze current templates as anchors.
      Map<String, dynamic> anchors;
      bool migrating = false;

      if (data['anchorEmbeddings'] is Map) {
        anchors = Map<String, dynamic>.from(data['anchorEmbeddings'] as Map);
      } else {
        anchors = poses.map((k, v) => MapEntry(k, List<double>.from(v)));
        migrating = true;
      }

      final score = result.bestScore;
      final shouldAdapt =
          score >= learnThreshold && score < nearDuplicateCeiling;

      bool adapted = false;

      if (shouldAdapt && poses.containsKey(result.bestPose)) {
        final old = poses[result.bestPose]!;

        if (old.length == live.length) {
          final blended = List<double>.generate(
            old.length,
            (i) =>
                (1 - adaptationRate) * old[i] + adaptationRate * live[i],
          );
          final updated = normalize(blended);

          // Anchor drift guard: never wander away from enrollment identity.
          final anchorRaw = anchors[result.bestPose];
          final anchor = anchorRaw is List
              ? anchorRaw.map((e) => (e as num).toDouble()).toList()
              : <double>[];

          if (anchor.isEmpty || cosine(updated, anchor) >= anchorDriftFloor) {
            poses[result.bestPose] = updated;
            adapted = true;
          }
        }
      }

      // Rolling stats — the profile's health record.
      final int verificationCount =
          ((data['verificationCount'] ?? 0) as num).toInt() + 1;
      final double prevAvg =
          ((data['avgMatchScore'] ?? score) as num).toDouble();
      final double avgScore = prevAvg * 0.8 + score * 0.2;

      final bool reenrollRecommended =
          verificationCount >= agingMinSamples && avgScore < agingScoreFloor;

      final update = <String, dynamic>{
        'verificationCount': verificationCount,
        'avgMatchScore': avgScore,
        'lastMatchScore': score,
        'lastMatchedPose': result.bestPose,
        'lastVerifiedAt': FieldValue.serverTimestamp(),
        'reenrollRecommended': reenrollRecommended,
        'enrollmentVersion': 2,
      };

      if (migrating) {
        update['anchorEmbeddings'] = anchors;
      }

      if (adapted) {
        update['embeddings'] = poses;
        update['centroid'] = fuse(poses.values.toList());
        update['adaptationCount'] =
            ((data['adaptationCount'] ?? 0) as num).toInt() + 1;
        update['lastAdaptedAt'] = FieldValue.serverTimestamp();
      } else if (data['centroid'] == null) {
        update['centroid'] = fuse(poses.values.toList());
      }

      await docRef.set(update, SetOptions(merge: true));

      debugPrint(
          'AdaptiveFace: uid=$uid score=${score.toStringAsFixed(3)} adapted=$adapted avg=${avgScore.toStringAsFixed(3)}');

      return adapted;
    } catch (e) {
      debugPrint('AdaptiveFace learning skipped: $e');
      return false;
    }
  }

  /// Whether this profile has been flagged for re-enrollment.
  static bool isAgingProfile(Map<String, dynamic> enrollmentData) {
    return enrollmentData['reenrollRecommended'] == true;
  }
}
