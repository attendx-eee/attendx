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

  /// Periods scheduled but not yet marked by anyone.
  final int unmarked;

  const DaySummary({
    required this.date,
    this.theoryAttended = 0,
    this.theoryTotal = 0,
    this.labAttended = 0,
    this.labTotal = 0,
    this.unmarked = 0,
  });

  int get attended => theoryAttended + labAttended;
  int get total => theoryTotal + labTotal;

  /// Periods that have actually been marked one way or the other.
  int get marked => total - unmarked;

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

/// Rolls day summaries up over a month or a semester.
class AttendanceTotals {
  int theoryAttended = 0;
  int theoryTotal = 0;
  int labAttended = 0;
  int labTotal = 0;

  /// Days with at least one period attended.
  int daysPresent = 0;

  /// Days with periods scheduled and marked, none attended.
  int daysAbsent = 0;

  /// Days attended in part.
  int daysPartial = 0;

  void add(DaySummary day) {
    theoryAttended += day.theoryAttended;
    theoryTotal += day.theoryTotal;
    labAttended += day.labAttended;
    labTotal += day.labTotal;

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

  int get attended => theoryAttended + labAttended;
  int get total => theoryTotal + labTotal;

  double get theoryPercent =>
      theoryTotal == 0 ? 0 : (theoryAttended / theoryTotal) * 100;

  double get labPercent =>
      labTotal == 0 ? 0 : (labAttended / labTotal) * 100;

  /// Overall percentage by *periods*, not by days.
  ///
  /// Counting days would let someone who attends one period of a
  /// six-period day score the same as someone who sat through all six.
  double get overallPercent => total == 0 ? 0 : (attended / total) * 100;

  bool get isShortTheory => theoryTotal > 0 && theoryPercent < 75;
  bool get isShortLab => labTotal > 0 && labPercent < 75;
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
    var theoryAttended = 0, theoryTotal = 0;
    var labAttended = 0, labTotal = 0, unmarked = 0;

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
        unmarked++;
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
      unmarked: unmarked,
    );
  }
}
