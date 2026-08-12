import '../../admin/models/period_model.dart';
import '../../faculty/models/period_attendance.dart';

/// How much of a day a student actually attended.
enum DayAttendance {
  /// Every scheduled period marked present.
  full,

  /// Some but not all — two classes scheduled, one attended.
  partial,

  /// Scheduled periods, none attended.
  absent,

  /// Nothing scheduled: Sunday, a holiday, or a free day for this year.
  noClass,

  /// Periods were scheduled but nobody has marked them yet.
  ///
  /// Deliberately distinct from [absent]. A class the lecturer hasn't
  /// got round to marking is not a class the student missed, and
  /// collapsing the two would invent absences every time a scan was
  /// delayed.
  notMarked,
}

/// One student's day, counted period by period.
///
/// Theory and lab are kept apart throughout rather than summed. They're
/// scheduled differently — a lab is one long block for a single batch,
/// theory is several short ones for the whole year — so a combined
/// percentage flatters anyone whose labs happen to fall on light days
/// and punishes the reverse. Colleges also tend to apply the 75% rule to
/// each separately.
class DaySummary {
  final DateTime date;

  final int theoryAttended;
  final int theoryTotal;

  final int labAttended;
  final int labTotal;

  /// Scheduled but not yet marked by anyone, split the same way as the
  /// totals — the calendar tile colours theory and lab independently, so
  /// it has to know which half is still waiting rather than just how
  /// many periods are.
  final int theoryUnmarked;
  final int labUnmarked;

  const DaySummary({
    required this.date,
    this.theoryAttended = 0,
    this.theoryTotal = 0,
    this.labAttended = 0,
    this.labTotal = 0,
    this.theoryUnmarked = 0,
    this.labUnmarked = 0,
  });

  int get attended => theoryAttended + labAttended;
  int get total => theoryTotal + labTotal;

  int get unmarked => theoryUnmarked + labUnmarked;

  /// Periods that have actually been marked one way or the other.
  int get marked => total - unmarked;

  int get theoryMarked => theoryTotal - theoryUnmarked;
  int get labMarked => labTotal - labUnmarked;

  double get theoryRatio =>
      theoryTotal == 0 ? 0 : theoryAttended / theoryTotal;

  double get labRatio => labTotal == 0 ? 0 : labAttended / labTotal;

  DayAttendance get status {
    if (total == 0) return DayAttendance.noClass;
    if (marked == 0) return DayAttendance.notMarked;
    if (attended == 0) return DayAttendance.absent;
    if (attended >= marked) return DayAttendance.full;
    return DayAttendance.partial;
  }

  /// "1/2", "3/3" — what the day is worth.
  String get fraction => '$attended/$total';

  /// 0-1 across everything scheduled. A day half attended counts half,
  /// rather than as a whole present or a whole absence.
  double get ratio => total == 0 ? 0 : attended / total;

  bool get hasTheory => theoryTotal > 0;
  bool get hasLab => labTotal > 0;

  /// A short line for the day sheet: "Theory 1/2 · Lab 1/1".
  String get breakdown {
    final parts = <String>[
      if (hasTheory) 'Theory $theoryAttended/$theoryTotal',
      if (hasLab) 'Lab $labAttended/$labTotal',
    ];
    return parts.join('  •  ');
  }
}

/// How much a period is worth.
///
/// A lab is a three-hour block that replaces three ordinary periods, so
/// counting it as one class alongside a fifty-minute lecture understates
/// it badly — a student who skips every lab and attends every lecture
/// would read as comfortably above the line.
///
/// These weights only move the *combined* figure. Within a single kind
/// they cancel out: theory attendance is theory attended over theory
/// held, and multiplying both sides by two changes nothing.
class ClassWeight {
  ClassWeight._();

  static const int theory = 2;
  static const int lab = 3;
}

/// Rolls day summaries up over a month or a semester.
///
/// Percentages are taken over classes that were actually **held and
/// registered**, not over everything on the timetable. A class nobody
/// has marked yet hasn't been missed, and putting it in the denominator
/// drags every student down for their lecturer's paperwork.
class AttendanceTotals {
  int theoryAttended = 0;
  int labAttended = 0;

  /// Registered by somebody — a faculty scan, a CR, or an admin.
  int theoryHeld = 0;
  int labHeld = 0;

  /// On the timetable, whether or not anyone has marked them. Shown as
  /// context ("18 of 24 classes registered so far"), never used as a
  /// denominator.
  int theoryScheduled = 0;
  int labScheduled = 0;

  /// Days with at least one period attended.
  int daysPresent = 0;

  /// Days with periods scheduled and marked, none attended.
  int daysAbsent = 0;

  /// Days attended in part.
  int daysPartial = 0;

  void add(DaySummary day) {
    theoryAttended += day.theoryAttended;
    labAttended += day.labAttended;

    theoryHeld += day.theoryMarked;
    labHeld += day.labMarked;

    theoryScheduled += day.theoryTotal;
    labScheduled += day.labTotal;

    switch (day.status) {
      case DayAttendance.full:
        daysPresent++;
      case DayAttendance.partial:
        daysPresent++;
        daysPartial++;
      case DayAttendance.absent:
        daysAbsent++;
      case DayAttendance.noClass:
      case DayAttendance.notMarked:
        break;
    }
  }

  /// Folds another roll-up in. Used to build a semester from months.
  void merge(AttendanceTotals other) {
    theoryAttended += other.theoryAttended;
    labAttended += other.labAttended;
    theoryHeld += other.theoryHeld;
    labHeld += other.labHeld;
    theoryScheduled += other.theoryScheduled;
    labScheduled += other.labScheduled;
    daysPresent += other.daysPresent;
    daysAbsent += other.daysAbsent;
    daysPartial += other.daysPartial;
  }

  int get attended => theoryAttended + labAttended;
  int get held => theoryHeld + labHeld;
  int get scheduled => theoryScheduled + labScheduled;

  // ---------------------------------------------------------- weighted

  int get attendedPoints =>
      theoryAttended * ClassWeight.theory + labAttended * ClassWeight.lab;

  int get heldPoints =>
      theoryHeld * ClassWeight.theory + labHeld * ClassWeight.lab;

  double get theoryPercent =>
      theoryHeld == 0 ? 0 : (theoryAttended / theoryHeld) * 100;

  double get labPercent =>
      labHeld == 0 ? 0 : (labAttended / labHeld) * 100;

  /// The headline number: attended points over held points.
  ///
  /// Weighted, so a missed lab costs what a missed lab is worth. This is
  /// the only figure the weights change, and it is the one every screen
  /// must agree on.
  double get overallPercent =>
      heldPoints == 0 ? 0 : (attendedPoints / heldPoints) * 100;

  bool get isShortTheory => theoryHeld > 0 && theoryPercent < 75;
  bool get isShortLab => labHeld > 0 && labPercent < 75;
  bool get isShortOverall => heldPoints > 0 && overallPercent < 75;

  /// "34 of 41 classes registered so far" — how complete the picture is.
  bool get hasUnregistered => scheduled > held;
}

/// Builds a [DaySummary] from a day's timetable and its marked periods.
class DaySummaryBuilder {
  const DaySummaryBuilder._();

  /// [periods] is the year's schedule for that weekday; [records] the
  /// period_attendance documents already saved for that date.
  ///
  /// [studentBatch] filters lab periods: a lab for batch B says nothing
  /// about a student in batch A, who wasn't expected there.
  static DaySummary build({
    required DateTime date,
    required String uid,
    required List<PeriodModel> periods,
    required Map<int, PeriodAttendance> records,
    String studentBatch = '',
  }) {
    var theoryAttended = 0, theoryTotal = 0, theoryUnmarked = 0;
    var labAttended = 0, labTotal = 0, labUnmarked = 0;

    for (final period in periods) {
      if (period.isFree || period.subject.isEmpty) continue;

      // Not this student's batch — not their class.
      if (period.batch.isNotEmpty &&
          studentBatch.isNotEmpty &&
          period.batch != studentBatch) {
        continue;
      }

      final isLab = period.classType.toLowerCase() == 'lab';

      if (isLab) {
        labTotal++;
      } else {
        theoryTotal++;
      }

      final record = records[period.periodNo];

      // A record scoped to other students says nothing about this one,
      // so it counts as unmarked rather than as an absence.
      if (record == null || !record.covers(uid)) {
        if (isLab) {
          labUnmarked++;
        } else {
          theoryUnmarked++;
        }
        continue;
      }

      if (record.wasPresent(uid)) {
        if (isLab) {
          labAttended++;
        } else {
          theoryAttended++;
        }
      }
    }

    return DaySummary(
      date: date,
      theoryAttended: theoryAttended,
      theoryTotal: theoryTotal,
      labAttended: labAttended,
      labTotal: labTotal,
      theoryUnmarked: theoryUnmarked,
      labUnmarked: labUnmarked,
    );
  }
}
