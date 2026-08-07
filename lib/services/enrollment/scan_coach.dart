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
  offCentre,
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
/// Two pieces of hysteresis fix it, the same shape of solution Apple's
/// enrollment uses:
///
/// - **A new issue must persist** for [_confirmAfter] before it's shown.
///   A single bad frame as someone blinks or shifts is not worth
///   announcing.
/// - **Once shown, a message stays** for [_minDisplay] even if the
///   condition clears. Text that appears and vanishes within 200ms may
///   as well not have appeared.
///
/// The exception is [CoachIssue.noFace], which is promoted immediately —
/// if the camera has lost the face entirely, waiting half a second to
/// say so is the one case where delay is worse than flicker.
class ScanCoach {
  static const Duration _confirmAfter = Duration(milliseconds: 450);
  static const Duration _minDisplay = Duration(milliseconds: 1400);

  /// A face this close to the frame edge is probably clipped.
  static const double _edgeMargin = 0.04;

  CoachIssue _current = CoachIssue.noFace;
  DateTime _currentSince = DateTime.fromMillisecondsSinceEpoch(0);

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

    final settled = now.difference(_candidateSince) >= _confirmAfter;
    final heldLongEnough = now.difference(_currentSince) >= _minDisplay;

    // Losing the face is urgent enough to skip the wait; so is the
    // moment everything comes right, because holding a stale complaint
    // over a good frame is what makes a scan feel unresponsive.
    final urgent =
        observed == CoachIssue.noFace || observed == CoachIssue.none;

    if ((settled && heldLongEnough) || (urgent && settled)) {
      _current = observed;
      _currentSince = now;
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
    double? centerOffset,
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

    // Clipped by the frame edge. Checked before anything else that
    // depends on the face box, because measurements taken from half a
    // face are wrong rather than merely bad — a chin cut off by the
    // bottom edge reads as a small, badly-centred face, and the advice
    // that follows would send the student the wrong way.
    if (faceBox != null && frame != null && frame.width > 0) {
      final mx = frame.width * _edgeMargin;
      final my = frame.height * _edgeMargin;

      final clipped = faceBox.left < mx ||
          faceBox.top < my ||
          faceBox.right > frame.width - mx ||
          faceBox.bottom > frame.height - my;

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

    if (centerOffset != null && centerOffset > 0.45) {
      return CoachIssue.offCentre;
    }

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
          'Only part of your face is visible — fit it all in the circle',
        CoachIssue.tooDark => 'Too dark — face a window or turn a light on',
        CoachIssue.tooBright =>
          'Too bright — move out of direct light or glare',
        CoachIssue.tooFar => 'Move a little closer',
        CoachIssue.tooClose => 'Move the phone back a little',
        CoachIssue.offCentre => 'Centre your face in the circle',
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
          'A cut-off face can\'t be matched later',
        CoachIssue.tooDark || CoachIssue.tooBright =>
          'Even, indirect light works best',
        CoachIssue.tooFar || CoachIssue.tooClose =>
          'Your face should fill most of the circle',
        CoachIssue.offCentre => 'Line your nose up with the middle',
        CoachIssue.headTilted => 'Level, not tilted to one side',
        CoachIssue.tooBlurry => 'Rest your elbow on something if you can',
        CoachIssue.none => '',
      };

  void reset() {
    _current = CoachIssue.noFace;
    _candidate = CoachIssue.noFace;
    _currentSince = DateTime.fromMillisecondsSinceEpoch(0);
    _candidateSince = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
