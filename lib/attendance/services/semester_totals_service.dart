import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../admin/models/period_model.dart';
import '../../admin/services/holiday_service.dart';
import '../../core/constants/app_config.dart';
import '../../faculty/models/period_attendance.dart';
import '../../faculty/services/period_attendance_service.dart';
import '../../services/attendance_service.dart';
import '../models/day_summary.dart';

/// The single place a student's attendance figures are computed.
///
/// Before this existed, four screens each worked it out their own way —
/// the admin ranking counted whole days from gate events, the student's
/// class card counted periods from registers, and the dashboard alert
/// summed a monthly map. They disagreed by ten points or more on the
/// same student, and every one of them was defensible in isolation.
/// Whichever number is right, showing three is worse than showing any
/// one of them.
///
/// Everything here is period-based and weighted: a lab is worth
/// [ClassWeight.lab], a theory class [ClassWeight.theory]. Percentages
/// are over classes actually **held** — registered by a faculty scan, a
/// CR or an admin — rather than over the whole timetable, because a
/// class nobody has marked yet has not been missed.
class SemesterTotalsService {
  SemesterTotalsService._();

  static final SemesterTotalsService instance = SemesterTotalsService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// department|year|month -> that month's period records for the year.
  ///
  /// Filled once per screen load. Ranking sixty students without it
  /// means sixty identical queries per month, which is both slow and a
  /// waste of the free read quota.
  final Map<String, List<PeriodAttendance>> _monthCache = {};

  /// department|year|weekday -> the timetable for that day.
  final Map<String, List<PeriodModel>> _scheduleCache = {};

  void clearCache() {
    _monthCache.clear();
    _scheduleCache.clear();
  }

  /// Every month from the semester's start to the current one.
  List<DateTime> semesterMonths() {
    final start = AttendanceService.instance.semesterStart();
    final now = DateTime.now();

    final months = <DateTime>[];
    var cursor = DateTime(start.year, start.month);
    final end = DateTime(now.year, now.month);

    while (!cursor.isAfter(end)) {
      months.add(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1);
    }

    return months.isEmpty ? [end] : months;
  }

  Future<List<PeriodAttendance>> _recordsFor({
    required String department,
    required int year,
    required DateTime month,
  }) async {
    final monthId =
        '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final key = '$department|$year|$monthId';

    final cached = _monthCache[key];
    if (cached != null) return cached;

    try {
      final snap = await _firestore
          .collection(PeriodAttendanceService.collectionName)
          .where('department', isEqualTo: department)
          .where('year', isEqualTo: year)
          .where('month', isEqualTo: monthId)
          .get();

      final records =
          snap.docs.map(PeriodAttendance.fromFirestore).toList();

      _monthCache[key] = records;
      return records;
    } catch (e) {
      debugPrint('Period records fetch failed ($key): $e');
      // Not cached — a dropped request should be retried, not baked in
      // as "this month had no classes".
      return const [];
    }
  }

  Future<List<PeriodModel>> _scheduleFor({
    required String department,
    required int year,
    required String weekday,
  }) async {
    final key = '$department|$year|$weekday';

    final cached = _scheduleCache[key];
    if (cached != null) return cached;

    final periods = await AttendanceService.instance.scheduledPeriods(
      department: department,
      year: year,
      weekday: weekday,
    );

    _scheduleCache[key] = periods;
    return periods;
  }

  /// One student's totals across [months].
  ///
  /// Pass the same [months] everywhere. Two screens covering different
  /// windows will report different percentages and both will be right,
  /// which is exactly the confusion this class exists to end.
  Future<AttendanceTotals> forStudent({
    required String uid,
    required Map<String, dynamic> studentData,
    List<DateTime>? months,
  }) async {
    final department = AppConfig.departmentOf(studentData);
    final year = AppConfig.yearOf(studentData);
    final batch = (studentData['batch'] ?? '').toString();

    await HolidayService.instance.all();

    final totals = AttendanceTotals();
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);

    for (final month in months ?? semesterMonths()) {
      final records = await _recordsFor(
        department: department,
        year: year,
        month: month,
      );

      final byDate = <String, Map<int, PeriodAttendance>>{};
      for (final r in records) {
        byDate.putIfAbsent(r.date, () => {})[r.periodNo] = r;
      }

      final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

      for (var d = 1; d <= daysInMonth; d++) {
        final date = DateTime(month.year, month.month, d);
        if (date.isAfter(todayMidnight)) break;

        // Closed days have no scheduled periods, which keeps holidays
        // out of the denominator without a second check here.
        if (!HolidayService.instance.isWorkingDay(date, year: year)) {
          continue;
        }

        final periods = await _scheduleFor(
          department: department,
          year: year,
          weekday: AppConfig.dayName(date),
        );

        if (periods.isEmpty) continue;

        totals.add(DaySummaryBuilder.build(
          date: date,
          uid: uid,
          periods: periods,
          records: byDate[AppConfig.dateId(date)] ?? const {},
          studentBatch: batch,
        ));
      }
    }

    return totals;
  }

  /// Totals for a whole year group, computed from one shared fetch.
  ///
  /// [students] is uid -> student document. The month records and the
  /// timetable are read once and reused for everybody, so ranking sixty
  /// students costs about the same as looking at one.
  Future<Map<String, AttendanceTotals>> forGroup({
    required Map<String, Map<String, dynamic>> students,
    List<DateTime>? months,
  }) async {
    final window = months ?? semesterMonths();
    final result = <String, AttendanceTotals>{};

    for (final entry in students.entries) {
      result[entry.key] = await forStudent(
        uid: entry.key,
        studentData: entry.value,
        months: window,
      );
    }

    return result;
  }
}
