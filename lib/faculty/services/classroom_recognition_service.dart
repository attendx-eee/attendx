import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../services/adaptive_face_service.dart';

/// One student the scan has seen, and how sure it is.
class Sighting {
  final String uid;
  final String name;
  final String regNo;

  /// Frames this student has been confidently matched in.
  int hits;

  /// Best similarity seen across those frames.
  double bestScore;

  /// Where they were last seen, for the on-screen label.
  Rect? lastBox;

  DateTime lastSeen;

  Sighting({
    required this.uid,
    required this.name,
    required this.regNo,
    this.hits = 0,
    this.bestScore = 0,
    this.lastBox,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  /// Seen often enough to be marked present without a human agreeing.
  bool get confirmed => hits >= ClassroomRecognitionService.confirmHits;
}

/// What to draw over one face in the preview.
class FaceLabel {
  final Rect box;

  /// Null while the face is still unidentified.
  final String? name;

  final bool confirmed;
  final double score;

  const FaceLabel({
    required this.box,
    required this.name,
    required this.confirmed,
    required this.score,
  });
}

/// Recognises many students at once from a live classroom camera.
///
/// Built on the model the app already ships — ML Kit for detection, the
/// TFLite embedder, and [AdaptiveFaceService] for matching. Nothing new
/// is trained. What's new is everything around it, because recognising
/// one cooperative face at arm's length and recognising thirty faces
/// across a room are different problems:
///
/// - **The gallery is loaded once.** Matching re-reads no Firestore; the
///   year's templates sit in memory for the whole scan.
/// - **Small faces are skipped.** Published classroom systems lose
///   accuracy badly past a few metres, and a face 20px wide produces an
///   embedding that is essentially noise — noise that will still match
///   *somebody* at 0.75. Refusing to guess is better than guessing
///   wrong.
/// - **Nobody is marked present on one frame.** A student must be
///   matched in several separate frames before they count. A single
///   frame is a coin toss at classroom distances; agreement across
///   frames is not.
///
/// The last point is what makes the difference between a demo and
/// something you'd let decide whether a student is marked absent.
class ClassroomRecognitionService {
  ClassroomRecognitionService._();

  static final ClassroomRecognitionService instance =
      ClassroomRecognitionService._();

  /// Confident matches needed before a student counts as present.
  static const int confirmHits = 3;

  /// Faces narrower than this fraction of the frame are ignored. Roughly
  /// the back of a normal classroom — beyond it, the crop carries too
  /// few pixels for the embedder to say anything trustworthy.
  static const double minFaceWidthRatio = 0.055;

  /// Stricter than the login threshold. A wrong face at the gate is one
  /// annoyed student who taps again; a wrong face here silently marks
  /// the wrong person present and someone else absent.
  static const double matchThreshold = 0.80;

  /// And it must beat the runner-up by this much. Thirty classmates make
  /// near-misses far likelier than a one-to-one login ever does.
  static const double margin = 0.06;

  final Map<String, Sighting> _sightings = {};

  List<FaceCandidate> _gallery = const [];
  Map<String, ({String name, String regNo})> _directory = const {};

  bool get isReady => _gallery.isNotEmpty;

  int get gallerySize => _gallery.length;

  /// Everyone confirmed so far, best matches first.
  List<Sighting> get confirmed {
    final list = _sightings.values.where((s) => s.confirmed).toList()
      ..sort((a, b) => b.bestScore.compareTo(a.bestScore));
    return list;
  }

  /// Seen at least once but not yet often enough to count.
  List<Sighting> get tentative =>
      _sightings.values.where((s) => !s.confirmed).toList();

  /// Loads the year's face templates into memory.
  ///
  /// [enrollments] is the raw `student_face_enrollments` data; [students]
  /// maps uid to the name and roll number shown on screen. Only students
  /// with both are usable — a template with no student record can't be
  /// labelled, and a student with no template can't be recognised.
  void loadGallery({
    required Map<String, Map<String, dynamic>> enrollments,
    required Map<String, ({String name, String regNo})> students,
  }) {
    final candidates = <FaceCandidate>[];

    enrollments.forEach((uid, data) {
      if (!students.containsKey(uid)) return;
      try {
        candidates.add(FaceCandidate.fromDoc(uid, data));
      } catch (e) {
        debugPrint('Skipping unreadable template for $uid: $e');
      }
    });

    _gallery = candidates;
    _directory = students;
    _sightings.clear();
  }

  /// Whether a face is big enough to bother identifying.
  bool isFaceUsable(Rect box, double frameWidth) =>
      frameWidth > 0 && (box.width / frameWidth) >= minFaceWidthRatio;

  /// Identifies one face's embedding.
  ///
  /// Returns the sighting it belongs to, or null if nothing matched
  /// confidently. Call once per detected face per processed frame.
  Sighting? identify({
    required List<double> embedding,
    required Rect box,
  }) {
    if (_gallery.isEmpty) return null;

    final result =
        AdaptiveFaceService.instance.identify(embedding, _gallery);

    final uid = result.uid;
    if (uid == null) return null;

    // AdaptiveFaceService.accepted uses the login thresholds. A
    // classroom needs stricter ones, so its raw scores are re-judged
    // here rather than trusting that verdict.
    if (result.bestScore < matchThreshold) return null;
    if (_gallery.length > 1 && result.margin < margin) return null;

    final who = _directory[uid];
    if (who == null) return null;

    final sighting = _sightings.putIfAbsent(
      uid,
      () => Sighting(uid: uid, name: who.name, regNo: who.regNo),
    );

    sighting.hits++;
    sighting.bestScore = math.max(sighting.bestScore, result.bestScore);
    sighting.lastBox = box;
    sighting.lastSeen = DateTime.now();

    return sighting;
  }

  /// A face already confirmed near this position, if any.
  ///
  /// Lets the caller skip the expensive embedding step for students who
  /// are already counted and haven't moved — the single biggest saving
  /// available, since most of a scan is spent re-recognising the same
  /// people sitting still.
  Sighting? confirmedNear(Rect box) {
    for (final s in _sightings.values) {
      if (!s.confirmed || s.lastBox == null) continue;
      if (DateTime.now().difference(s.lastSeen).inSeconds > 3) continue;

      final overlap = s.lastBox!.intersect(box);
      if (overlap.width <= 0 || overlap.height <= 0) continue;

      final overlapArea = overlap.width * overlap.height;
      final boxArea = box.width * box.height;
      if (boxArea > 0 && overlapArea / boxArea > 0.6) return s;
    }
    return null;
  }

  /// Uids to mark present: everyone confirmed.
  List<String> get presentUids => confirmed.map((s) => s.uid).toList();

  void reset() => _sightings.clear();

  /// Frees the in-memory gallery. Worth calling when the scan screen
  /// closes — a year's templates are a few hundred KB of doubles.
  void dispose() {
    _gallery = const [];
    _directory = const {};
    _sightings.clear();
  }
}
