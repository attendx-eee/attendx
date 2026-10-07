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

/// One face followed across frames.
///
/// ML Kit assigns a tracking id to each face it follows, and keeps it
/// while that face stays in view. That is what lets the sweep stop
/// re-recognising somebody it has already decided about: the expensive
/// part of a frame is the embedding, and a face whose track is resolved
/// needs no embedding at all.
///
/// Evidence accumulates per track and must agree. A track that matches
/// three different students across three frames is a track producing
/// noise, and noise should not mark anybody present.
class _Track {
  /// Who this track currently looks like.
  String? uid;

  /// Frames in a row that agreed on [uid].
  int agreeing = 0;

  double bestScore = 0;

  /// Resolved — stop embedding this face.
  bool locked = false;

  Rect box;
  DateTime lastSeen;

  _Track({required this.box, DateTime? lastSeen})
      : lastSeen = lastSeen ?? DateTime.now();
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
/// one cooperative face at arm's length and recognising eighty faces
/// across a room are different problems:
///
/// - **The gallery is loaded once.** Matching re-reads no Firestore; the
///   year's templates sit in memory for the whole scan.
/// - **Small faces are skipped.** A face 20px wide produces an embedding
///   that is essentially noise — noise that will still match *somebody*.
///   Refusing to guess is better than guessing wrong.
/// - **Nobody is marked present on one frame.** A student must be
///   matched in several frames, and those frames must agree, before they
///   count.
/// - **A resolved face is never looked at twice.** Tracking ids carry a
///   decision forward, so the sweep back across the room spends its
///   effort on whoever is still unaccounted for.
///
/// What it does not do is claim to find everybody. Back rows, bowed
/// heads and one student sitting behind another are not recognition
/// failures to be tuned away; they are people the camera cannot see. The
/// scan hands whatever it could not resolve to the review screen, where
/// a human closes the gap in seconds. Marking the *wrong* student is the
/// error worth engineering against, and every threshold here is set for
/// that rather than for a higher headline count.
class ClassroomRecognitionService {
  ClassroomRecognitionService._();

  static final ClassroomRecognitionService instance =
      ClassroomRecognitionService._();

  /// Agreeing frames needed before a student counts as present.
  static const int confirmHits = 3;

  /// Faces narrower than this fraction of the frame are ignored. Roughly
  /// the back of a normal classroom — beyond it, the crop carries too
  /// few pixels for the embedder to say anything trustworthy.
  static const double minFaceWidthRatio = 0.055;

  /// Lower than the login bar, and deliberately so.
  ///
  /// A login is one face at arm's length filling the frame; a classroom
  /// probe is a small, noisy, obliquely-lit face thirty feet away, and
  /// the same person scores lower simply because of that. Holding the
  /// login threshold here does not buy safety, it just refuses everybody
  /// past the third row. The safety comes from [margin] and from
  /// [confirmHits] agreeing frames, which a wrong match rarely sustains.
  static const double matchThreshold = 0.70;

  /// And it must beat the runner-up by this much. Eighty classmates make
  /// near-misses far likelier than a one-to-one login ever does, so this
  /// is the check doing most of the work against a wrong name.
  static const double margin = 0.07;

  /// A track is forgotten this long after it was last seen.
  static const Duration trackMemory = Duration(seconds: 2);

  final Map<String, Sighting> _sightings = {};

  /// ML Kit tracking id -> what we have decided about that face.
  final Map<int, _Track> _tracks = {};

  List<FaceCandidate> _gallery = const [];
  Map<String, ({String name, String regNo})> _directory = const {};

  bool get isReady => _gallery.isNotEmpty;

  int get gallerySize => _gallery.length;

  /// Templates built before the crop fix, which cannot be matched.
  ///
  /// Worth counting and saying out loud. A stale template is not scored
  /// badly, it is refused outright — so a class where everybody enrolled
  /// on an older build recognises nobody at all, and the lecturer sees
  /// grey boxes with no explanation and concludes the camera is broken.
  /// It is not; it has nothing to compare against.
  int get staleCount => _gallery.where((c) => c.isStale).length;

  /// Templates that can actually be matched.
  int get usableCount => _gallery.length - staleCount;

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
    _tracks.clear();
  }

  /// Whether a face is big enough to bother identifying.
  bool isFaceUsable(Rect box, double frameWidth) =>
      frameWidth > 0 && (box.width / frameWidth) >= minFaceWidthRatio;

  /// Drops tracks for faces that have left the frame.
  ///
  /// Call once per processed frame, before looking at any face.
  void beginFrame() {
    final now = DateTime.now();
    _tracks.removeWhere((_, t) => now.difference(t.lastSeen) > trackMemory);
  }

  /// Registers that [trackingId] is visible at [box] this frame, and
  /// reports what is already known about it.
  ///
  /// Returns null when this face still needs an embedding. Returns the
  /// sighting when the track is already resolved — the caller can draw
  /// the label and skip the expensive part entirely, which is what makes
  /// the sweep back across the room cheap.
  Sighting? seen({required int? trackingId, required Rect box}) {
    final track = _trackFor(trackingId, box);

    track.box = box;
    track.lastSeen = DateTime.now();

    if (!track.locked || track.uid == null) return null;

    final sighting = _sightings[track.uid];
    if (sighting == null) return null;

    sighting.lastBox = box;
    sighting.lastSeen = DateTime.now();

    return sighting;
  }

  /// Whether this face is worth spending an embedding on.
  bool needsEmbedding(int? trackingId) {
    final track = _lookup(trackingId);
    return track == null || !track.locked;
  }

  /// Identifies one face's embedding.
  ///
  /// Matched against the **whole** gallery, including students already
  /// counted. Dropping them would be faster and is wrong: their face is
  /// still in the room, and a gallery without them answers "who is this"
  /// with the nearest remaining stranger. They are recognised as
  /// themselves and simply not counted again.
  Sighting? identify({
    required List<double> embedding,
    required Rect box,
    int? trackingId,
  }) {
    if (_gallery.isEmpty) return null;

    final track = _trackFor(trackingId, box);
    track.box = box;
    track.lastSeen = DateTime.now();

    final result =
        AdaptiveFaceService.instance.identify(embedding, _gallery);

    final uid = result.uid;

    // AdaptiveFaceService.accepted uses the login thresholds. A
    // classroom needs its own, so its raw scores are re-judged here
    // rather than trusting that verdict.
    if (uid == null ||
        result.bestScore < matchThreshold ||
        (_gallery.length > 1 && result.margin < margin)) {
      // A frame that says nothing costs one step of progress rather than
      // all of it. Clearing the run outright was too harsh: a face at
      // the edge of a moving frame misses occasionally, and throwing
      // away two good frames for one bad one meant the people hardest to
      // catch were also the slowest to confirm. A run still cannot
      // survive on scattered guesses — it decays as fast as it builds.
      if (track.agreeing > 0) track.agreeing--;
      return null;
    }

    final who = _directory[uid];
    if (who == null) return null;

    // Agreement is per track. A track that changes its mind starts over.
    if (track.uid == uid) {
      track.agreeing++;
    } else {
      track.uid = uid;
      track.agreeing = 1;
    }

    track.bestScore = math.max(track.bestScore, result.bestScore);

    final sighting = _sightings.putIfAbsent(
      uid,
      () => Sighting(uid: uid, name: who.name, regNo: who.regNo),
    );

    // Counted once per agreeing frame of *this* track. Without the
    // per-track accounting, one student held in view for a second
    // confirmed themselves on consecutive near-identical frames, which
    // is one piece of evidence counted three times.
    sighting.hits = math.max(sighting.hits, track.agreeing);
    sighting.bestScore = math.max(sighting.bestScore, result.bestScore);
    sighting.lastBox = box;
    sighting.lastSeen = DateTime.now();

    // Resolved: stop embedding this face while it stays in view.
    if (sighting.confirmed) track.locked = true;

    return sighting;
  }

  _Track? _lookup(int? trackingId) =>
      trackingId == null ? null : _tracks[trackingId];

  /// The track for this face, creating one if the id is new.
  ///
  /// Faces with no tracking id — ML Kit drops them when a face is
  /// momentarily lost — fall back to whichever live track overlaps the
  /// box most, so a flicker in tracking does not throw away the evidence
  /// already gathered about that person.
  _Track _trackFor(int? trackingId, Rect box) {
    if (trackingId != null) {
      return _tracks.putIfAbsent(trackingId, () => _Track(box: box));
    }

    final overlapping = _overlapping(box);
    if (overlapping != null) return overlapping;

    // Negative keys cannot collide with ML Kit's own ids. Counted rather
    // than derived from the map's size, which shrinks as tracks expire
    // and would hand a new face the key of one just forgotten.
    final key = --_anonymousTrackKey;
    return _tracks.putIfAbsent(key, () => _Track(box: box));
  }

  int _anonymousTrackKey = 0;

  _Track? _overlapping(Rect box) {
    _Track? best;
    var bestRatio = 0.5;

    final area = box.width * box.height;
    if (area <= 0) return null;

    for (final track in _tracks.values) {
      final overlap = track.box.intersect(box);
      if (overlap.width <= 0 || overlap.height <= 0) continue;

      final ratio = (overlap.width * overlap.height) / area;
      if (ratio > bestRatio) {
        bestRatio = ratio;
        best = track;
      }
    }

    return best;
  }

  /// Uids to mark present: everyone confirmed.
  List<String> get presentUids => confirmed.map((s) => s.uid).toList();

  void reset() {
    _sightings.clear();
    _tracks.clear();
  }

  /// Frees the in-memory gallery. Worth calling when the scan screen
  /// closes — a year's templates are a few hundred KB of doubles.
  void dispose() {
    _gallery = const [];
    _directory = const {};
    _sightings.clear();
    _tracks.clear();
  }
}
