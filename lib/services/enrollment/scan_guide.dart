import 'scan_harvester.dart';

/// What the student is being asked to do right now.
enum ScanPhase {
  /// No face, or not yet framed.
  findFace,

  /// Face is framed; hold still while the centre bin fills.
  holdStill,

  /// Mid-sweep. Deliberately not "left" and "right": which way a given
  /// yaw sign corresponds to depends on the camera and whether the
  /// preview is mirrored, so the scan asks for a side rather than
  /// naming one it can't be sure of.
  turnOneWay,
  turnOtherWay,

  tiltUp,
  tiltDown,

  /// Every required bin is full; the optional ones are being topped up.
  finishing,

  /// Done.
  complete,
}

/// Turns harvester state into one instruction at a time.
///
/// Separated from the enrollment screen because the sequencing rules —
/// what to ask next, when to stop asking, how long to leave an
/// instruction up before it starts to nag — are logic, and they were
/// previously tangled through the widget's setState calls where they
/// couldn't be reasoned about or changed safely.
class ScanGuide {
  /// Don't swap the instruction faster than this. A sweep briefly passes
  /// through bins on its way elsewhere, and an instruction that flickers
  /// between "turn left" and "turn right" is unusable.
  static const Duration minHoldTime = Duration(milliseconds: 900);

  ScanPhase _phase = ScanPhase.findFace;
  DateTime _lastChange = DateTime.fromMillisecondsSinceEpoch(0);

  ScanPhase get phase => _phase;

  /// Recomputes the instruction. Returns true if it changed, so the
  /// caller can decide whether a re-render (or haptic) is warranted.
  bool update({
    required ScanHarvester harvester,
    required bool faceDetected,
  }) {
    final next = _resolve(harvester: harvester, faceDetected: faceDetected);

    if (next == _phase) return false;

    // Losing the face and finishing are both urgent enough to bypass the
    // hold: one means the student needs to act now, the other means
    // they can stop.
    final urgent =
        next == ScanPhase.findFace || next == ScanPhase.complete;

    if (!urgent &&
        DateTime.now().difference(_lastChange) < minHoldTime) {
      return false;
    }

    _phase = next;
    _lastChange = DateTime.now();
    return true;
  }

  ScanPhase _resolve({
    required ScanHarvester harvester,
    required bool faceDetected,
  }) {
    if (!faceDetected) return ScanPhase.findFace;

    // Centre first: it's the view most logins will present, and the
    // easiest to get right while the student is still settling.
    if (!harvester.isBinComplete(ScanBin.centre)) return ScanPhase.holdStill;

    if (harvester.hasRequiredCoverage) {
      // Required coverage is in. Anything else is a bonus collected
      // during the short grace period before the scan closes itself —
      // so the instruction invites it rather than demanding it, and the
      // student is never left waiting on an angle nobody needs.
      final wantsMore = harvester.targets.keys
          .any((bin) => !harvester.isBinComplete(bin));

      if (!wantsMore) return ScanPhase.complete;

      if (!harvester.isBinComplete(ScanBin.up) &&
          harvester.targets.containsKey(ScanBin.up)) {
        return ScanPhase.tiltUp;
      }

      return ScanPhase.finishing;
    }

    // Then the two sides, counted rather than named.
    //
    // The old code asked for whichever required bin came first in the
    // set — always `left`. If this camera's yaw sign runs the other way,
    // turning left filled `right`, `left` never completed, and the
    // instruction never advanced. Asking for "one side" and then "the
    // other" is correct whichever way the sign runs.
    if (!harvester.hasOneSide) return ScanPhase.turnOneWay;
    return ScanPhase.turnOtherWay;
  }

  /// The headline instruction.
  static String title(ScanPhase phase) => switch (phase) {
        ScanPhase.findFace => 'Position your face in the frame',
        ScanPhase.holdStill => 'Hold still',
        ScanPhase.turnOneWay => 'Slowly turn your head to one side',
        ScanPhase.turnOtherWay => 'Now slowly turn to the other side',
        ScanPhase.tiltUp => 'Slowly tilt your head up',
        ScanPhase.tiltDown => 'Slowly tilt your head down',
        ScanPhase.finishing => 'Almost done — turn your head a little',
        ScanPhase.complete => 'Scan complete',
      };

  /// The quieter second line.
  static String subtitle(ScanPhase phase) => switch (phase) {
        ScanPhase.findFace =>
          'Hold the phone at eye level, arm\'s length away',
        ScanPhase.holdStill => 'Capturing your face',
        ScanPhase.turnOneWay ||
        ScanPhase.turnOtherWay =>
          'Keep your eyes on the screen as you turn',
        ScanPhase.tiltUp || ScanPhase.tiltDown => 'Nice and slow',
        ScanPhase.finishing => 'Optional — this finishes on its own',
        ScanPhase.complete => 'Saving your face profile',
      };

  void reset() {
    _phase = ScanPhase.findFace;
    _lastChange = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
