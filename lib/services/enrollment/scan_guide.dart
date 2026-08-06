import 'scan_harvester.dart';

/// What the student is being asked to do right now.
enum ScanPhase {
  /// No face, or not yet framed.
  findFace,

  /// Face is framed; hold still while the centre bin fills.
  holdStill,

  /// Mid-sweep.
  turnLeft,
  turnRight,
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

    if (harvester.hasRequiredCoverage) {
      // Required bins are done. Give the optional extremes a short
      // chance to fill — they widen the template — but never block on
      // them, so a student who can't turn far still finishes.
      final outstanding = harvester.outstandingBins;
      if (outstanding.isEmpty) return ScanPhase.complete;
      return _phaseForBin(outstanding.first) ?? ScanPhase.finishing;
    }

    // Centre first: it's the view most logins will present, and it's the
    // easiest to get right while the student is still settling.
    if (!harvester.isBinComplete(ScanBin.centre)) return ScanPhase.holdStill;

    final outstanding = harvester.outstandingBins;
    if (outstanding.isEmpty) return ScanPhase.complete;

    return _phaseForBin(outstanding.first) ?? ScanPhase.finishing;
  }

  static ScanPhase? _phaseForBin(ScanBin bin) => switch (bin) {
        ScanBin.centre => ScanPhase.holdStill,
        ScanBin.left || ScanBin.farLeft => ScanPhase.turnLeft,
        ScanBin.right || ScanBin.farRight => ScanPhase.turnRight,
        ScanBin.up => ScanPhase.tiltUp,
        ScanBin.down => ScanPhase.tiltDown,
      };

  /// The headline instruction.
  static String title(ScanPhase phase) => switch (phase) {
        ScanPhase.findFace => 'Position your face in the circle',
        ScanPhase.holdStill => 'Hold still',
        ScanPhase.turnLeft => 'Slowly turn your head left',
        ScanPhase.turnRight => 'Slowly turn your head right',
        ScanPhase.tiltUp => 'Slowly tilt your head up',
        ScanPhase.tiltDown => 'Slowly tilt your head down',
        ScanPhase.finishing => 'Almost there — keep moving slowly',
        ScanPhase.complete => 'Scan complete',
      };

  /// The quieter second line.
  static String subtitle(ScanPhase phase) => switch (phase) {
        ScanPhase.findFace =>
          'Hold the phone at eye level, arm\'s length away',
        ScanPhase.holdStill => 'Capturing your face',
        ScanPhase.turnLeft ||
        ScanPhase.turnRight =>
          'Keep your eyes on the screen as you turn',
        ScanPhase.tiltUp || ScanPhase.tiltDown => 'Nice and slow',
        ScanPhase.finishing => 'Just rounding out the scan',
        ScanPhase.complete => 'Saving your face profile',
      };

  void reset() {
    _phase = ScanPhase.findFace;
    _lastChange = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
