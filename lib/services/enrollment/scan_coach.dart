import 'dart:ui';

/// Something standing between the camera and a usable frame.
///
/// Ordered by priority, most blocking first. Only one is ever shown: a
/// student who is too far away *and* badly lit needs to fix one thing at
/// a time, and a screen listing both teaches them to read neither.
enum CoachIssue {
  noFace,
  multipleFaces,
  partiallyOutOfFrame,
  tooDark,
  tooBright,
  tooFar,
  tooClose,
  headTilted,
  tooBlurry,

  /// Nothing wrong — the sweep instruction can show.
  none,
}

/// Decides what single line of text the enrollment screen shows.
///
/// The problem this solves is flicker. Frames arrive several times a
/// second and each one has its own opinion; wiring that straight to a
/// label produces text that changes faster than anyone can read, which
/// users experience as the app malfunctioning rather than as advice.
///
/// The fix has two halves, split by responsibility:
///
/// - **Here:** a new issue must persist for [_confirmAfter] before it's
///   accepted as true. A single bad frame as someone blinks or shifts is
///   not worth reacting to.
/// - **In the enrollment screen:** whatever this decides is then held on
///   screen for a minimum duration, enforced at the one point every
///   status writer funnels through — including the liveness and
///   alignment prompts, which never come through here at all. That
///   placement matters: debouncing only the coach still left those
///   others free to overwrite the label on any frame.
class ScanCoach {
  /// How long a problem must persist before it counts as real.
  ///
  /// This is the coach's only timing responsibility: deciding *what is
  /// true*, not how long it stays on screen. A single bad frame as
  /// someone blinks or shifts isn't worth reacting to; half a second of
  /// it is.
  ///
  /// How long the resulting message is *displayed* is enforced
  /// separately, at the point every status writer in the enrollment
  /// screen funnels through. Holding it in both places would compound —
  /// half a second to notice plus nearly two to display — and make the
  /// scan feel unresponsive rather than calm.
  static const Duration _confirmAfter = Duration(milliseconds: 500);

  CoachIssue _current = CoachIssue.noFace;

  CoachIssue _candidate = CoachIssue.noFace;
  DateTime _candidateSince = DateTime.fromMillisecondsSinceEpoch(0);

  CoachIssue get current => _current;

  bool get isBlocked => _current != CoachIssue.none;

  /// Feeds one frame's findings in and returns the issue to display.
  CoachIssue update(CoachIssue observed) {
    final now = DateTime.now();

    if (observed != _candidate) {
      _candidate = observed;
      _candidateSince = now;
    }

    if (observed == _current) return _current;

    if (now.difference(_candidateSince) >= _confirmAfter) {
      _current = observed;
    }

    return _current;
  }

  /// Works out what's wrong with a frame.
  ///
  /// [faceBox] and [frame] are in the same coordinate space. Everything
  /// else has already been measured by the quality services.
  static CoachIssue diagnose({
    required int faceCount,
    Rect? faceBox,
    Size? frame,
    double? brightness,
    double? occupancy,
    double? roll,
    double? sharpness,
    double? sharpnessFloor,
    required double minOccupancy,
    required double maxOccupancy,
    required double minBrightness,
    required double maxBrightness,
    required double maxRoll,
  }) {
    if (faceCount == 0) return CoachIssue.noFace;
    if (faceCount > 1) return CoachIssue.multipleFaces;

    // Clipped by the frame edge.
    //
    // Only flagged when the box has actually run past the boundary, not
    // when it merely approaches one. An inset margin sounds safer and
    // isn't: it turns "sitting near the top of the preview" into "your
    // face is cut off", which is wrong, unactionable, and was blocking
    // perfectly good scans on real handsets.
    //
    // ML Kit clamps its boxes to the frame, so a genuinely cut-off face
    // produces one that reaches or crosses the edge exactly. That's a
    // reliable signal on every device; a percentage inset is not.
    if (faceBox != null && frame != null && frame.width > 0) {
      final clipped = faceBox.left <= 0 ||
          faceBox.top <= 0 ||
          faceBox.right >= frame.width ||
          faceBox.bottom >= frame.height;

      if (clipped) return CoachIssue.partiallyOutOfFrame;
    }

    // Lighting before framing: no amount of repositioning rescues a
    // frame the sensor can't expose properly.
    if (brightness != null) {
      if (brightness < minBrightness) return CoachIssue.tooDark;
      if (brightness > maxBrightness) return CoachIssue.tooBright;
    }

    if (occupancy != null) {
      if (occupancy < minOccupancy) return CoachIssue.tooFar;
      if (occupancy > maxOccupancy) return CoachIssue.tooClose;
    }

    // Centring is deliberately NOT a blocking check any more.
    //
    // It was the least reliable thing here: the offset depended on a
    // coordinate transform that differs by camera, mirroring and
    // handset, and it fired on faces that were plainly well placed. It
    // also earns nothing — occupancy already guarantees the face is a
    // sensible size, and ML Kit cannot detect a face that isn't
    // substantially in shot. The guide outline remains as a hint, which
    // is all it should ever have been.

    if (roll != null && roll.abs() > maxRoll) return CoachIssue.headTilted;

    // Blur last. During a head turn some motion blur is expected and
    // transient; complaining about it first would mean complaining
    // through most of a healthy sweep.
    if (sharpness != null &&
        sharpnessFloor != null &&
        sharpness < sharpnessFloor) {
      return CoachIssue.tooBlurry;
    }

    return CoachIssue.none;
  }

  /// The line the student reads. Plain, specific, and phrased as the
  /// action to take rather than the defect detected — "Move a little
  /// closer", not "Face occupancy below threshold".
  static String message(CoachIssue issue) => switch (issue) {
        CoachIssue.noFace => 'No face detected — look at the screen',
        CoachIssue.multipleFaces =>
          'More than one face — only you should be in view',
        CoachIssue.partiallyOutOfFrame =>
          'Your face is at the edge — move it into view',
        CoachIssue.tooDark => 'Too dark — face a window or turn a light on',
        CoachIssue.tooBright =>
          'Too bright — move out of direct light or glare',
        CoachIssue.tooFar => 'Move a little closer',
        CoachIssue.tooClose => 'Move the phone back a little',
        CoachIssue.headTilted => 'Keep your head upright',
        CoachIssue.tooBlurry => 'Hold the phone steady',
        CoachIssue.none => '',
      };

  /// A second line explaining why it matters, shown under the message.
  static String detail(CoachIssue issue) => switch (issue) {
        CoachIssue.noFace =>
          'Hold the phone at eye level, about an arm\'s length away',
        CoachIssue.multipleFaces =>
          'Someone else in shot could be enrolled by mistake',
        CoachIssue.partiallyOutOfFrame =>
          'The camera needs your whole face in shot',
        CoachIssue.tooDark || CoachIssue.tooBright =>
          'Even, indirect light works best',
        CoachIssue.tooFar || CoachIssue.tooClose =>
          'Your face should fill most of the circle',
        CoachIssue.headTilted => 'Level, not tilted to one side',
        CoachIssue.tooBlurry => 'Rest your elbow on something if you can',
        CoachIssue.none => '',
      };

  void reset() {
    _current = CoachIssue.noFace;
    _candidate = CoachIssue.noFace;
    _candidateSince = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
