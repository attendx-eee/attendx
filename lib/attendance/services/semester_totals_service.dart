import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../admin/models/period_model.dart';
import '../../admin/services/holiday_service.dart';
import '../../core/constants/app_config.dart';
import '../../faculty/models/period_attendance.dart';
import '../../faculty/services/period_attendance_service.dart';
import '../../services/attendance_service.dart';
import '../../timetable/services/schedule_resolver.dart';
import '../models/day_summary.dart';
import '../models/manual_attendance_model.dart';
import 'manual_attendance_service.dart';

/// What a month has on the timetable, ahead of anyone marking anything.
///
/// Kept apart from [AttendanceTotals] because it is a property of the
/// month rather than of a student: every student in the year has the
/// same plan, and it counts the whole month including days that have not
/// happened yet. "Twelve theory classes this month, three held so far"
/// is two different facts and they need two different sources.
class MonthPlan {
  final int theory;
  final int lab;

  const MonthPlan({this.theory = 0, this.lab = 0});

  int get total => theory + lab;

  bool get isEmpty => total == 0;
}

/// A month resolved once: which days had classes, and what those classes
/// were after cancellations and extra classes were applied.
///
/// This exists because of what the previous version cost. Ranking sixty
/// students meant, per student, walking every day of the semester and
/// awaiting the timetable and the overrides for each one — the values
/// came back from a cache, but every `await` still yields to the event
/// loop, so the console spent its time bouncing through tens of
/// thousands of microtasks rather than doing arithmetic. The work is the
/// same for all sixty; only the register numbers differ.
class _MonthContext {
  /// Working days in the month, in order, including days still to come.
  final List<DateTime> days;

  /// dateId -> the classes that actually stood that day.
  final Map<String, List<PeriodModel>> periods;

  /// dateId -> periodNo -> what was marked.
  final Map<String, Map<int, PeriodAttendance>> records;

  /// uid -> dateId -> the day-level mark an admin or CR made by hand.
  ///
  /// Fetched for the whole year group in one query, because every
  /// student needs their own and going one at a time would put sixty
  /// round trips back into a screen that just had them removed.
  final Map<String, Map<String, ManualAttendance>> manual;

  const _MonthContext({
    required this.days,
    required this.periods,
    required this.records,
    required this.manual,
  });
}

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
/// class nobody has marked yet has not been missed. The timetable figure
/// is still worth showing, which is what [planFor] is for; it is context
/// beside the percentage, never underneath it.
class SemesterTotalsService {
  SemesterTotalsService._();

  static final SemesterTotalsService instance = SemesterTotalsService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// department|year|month -> that month's period records for the year.
  final Map<String, List<PeriodAttendance>> _monthCache = {};

  /// department|year|month -> the resolved month.
  final Map<String, _MonthContext> _contexts = {};

  /// department|year|weekday -> the timetable for that day.
  final Map<String, List<PeriodModel>> _scheduleCache = {};

  void clearCache() {
    _monthCache.clear();
    _contexts.clear();
    _scheduleCache.clear();
    ScheduleResolver.instance.clearCache();
  }

  /// Forgets one month, leaving every other month and the timetable
  /// alone.
  ///
  /// Marking attendance changes exactly one month for one year group.
  /// The screens used to call [clearCache] after every save, which threw
  /// away the whole semester and the timetable with it — so correcting a
  /// single day re-read six months of records, for every student on the
  /// screen, before anything repainted. That is the lag.
  void invalidateMonth({
    required String department,
    required int year,
    required DateTime month,
  }) {
    final key = _key(department, year, month);
    _monthCache.remove(key);
    _contexts.remove(key);
  }

  String _key(String department, int year, DateTime month) =>
      '$department|$year|${month.year}-'
      '${month.month.toString().padLeft(2, '0')}';

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

  /// Resolves a month once, for everybody.
  Future<_MonthContext> _contextFor({
    required String department,
    required int year,
    required DateTime month,
  }) async {
    final key = _key(department, year, month);

    final cached = _contexts[key];
    if (cached != null) return cached;

    await HolidayService.instance.all();

    final records = await _recordsFor(
      department: department,
      year: year,
      month: month,
    );

    final byDate = <String, Map<int, PeriodAttendance>>{};
    for (final r in records) {
      byDate.putIfAbsent(r.date, () => {})[r.periodNo] = r;
    }

    // Day-level marks for the whole year group. These are what an admin
    // sets on the calendar, and until now they reached the calendar
    // colours and nothing else — a month marked present by hand totalled
    // zero classes held.
    var manual = <String, Map<String, ManualAttendance>>{};
    try {
      manual = await ManualAttendanceService.instance.forMonth(
        department: department,
        year: year,
        monthId: '${month.year}-'
            '${month.month.toString().padLeft(2, '0')}',
      );
    } catch (e) {
      debugPrint('Manual marks fetch failed: $e');
    }

    // One query for the month's cancellations and extra classes, rather
    // than one per day. Without this a cancelled class still counts
    // against the whole year, and a class the CR added in a free period
    // counts for nobody.
    final overrides = await ScheduleResolver.instance.preloadMonth(
      department: department,
      year: year,
      month: month,
    );

    final days = <DateTime>[];
    final periods = <String, List<PeriodModel>>{};

    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(month.year, month.month, d);

      // Closed days have no scheduled periods, which keeps holidays out
      // of the denominator without a second check anywhere else.
      if (!HolidayService.instance.isWorkingDay(date, year: year)) continue;

      final base = await _scheduleFor(
        department: department,
        year: year,
        weekday: AppConfig.dayName(date),
      );

      final resolved = ScheduleResolver.apply(
        base: base,
        overrides: overrides[AppConfig.dateId(date)] ?? const [],
      );

      if (resolved.isEmpty) continue;

      days.add(date);
      periods[AppConfig.dateId(date)] = resolved;
    }

    final ctx = _MonthContext(
      days: days,
      periods: periods,
      records: byDate,
      manual: manual,
    );

    _contexts[key] = ctx;

    return ctx;
  }

  /// The per-student arithmetic, with no network and no awaits.
  AttendanceTotals _totalsFrom(
    _MonthContext ctx,
    String uid,
    String batch,
  ) {
    final totals = AttendanceTotals();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final marks = ctx.manual[uid];

    for (final date in ctx.days) {
      if (date.isAfter(today)) break;

      final id = AppConfig.dateId(date);

      totals.add(DaySummaryBuilder.build(
        date: date,
        uid: uid,
        periods: ctx.periods[id] ?? const [],
        records: ctx.records[id] ?? const {},
        studentBatch: batch,
        dayStatus: marks?[id]?.status,
      ));
    }

    return totals;
  }

  /// What the timetable holds for a month, whole month, everybody.
  ///
  /// Counts days that have not happened yet, which is the point: "24
  /// theory classes this month" is a plan, and a student wants to know
  /// it on the 3rd, not only in hindsight.
  Future<MonthPlan> planFor({
    required String department,
    required int year,
    required DateTime month,
    String batch = '',
  }) async {
    final ctx = await _contextFor(
      department: department,
      year: year,
      month: month,
    );

    var theory = 0;
    var lab = 0;

    for (final date in ctx.days) {
      final periods =
          ctx.periods[AppConfig.dateId(date)] ?? const <PeriodModel>[];

      for (final p in periods) {
        if (p.isFree || p.subject.isEmpty) continue;

        // A lab split by batch is only this student's class if it is
        // their batch — same rule the totals use, or the plan and the
        // percentage would be counting different things.
        if (p.batch.isNotEmpty && batch.isNotEmpty && p.batch != batch) {
          continue;
        }

        // Same test DaySummaryBuilder uses. If these two ever disagree
        // the plan says four labs and the percentage counts three.
        if (p.classType.toLowerCase() == 'lab') {
          lab++;
        } else {
          theory++;
        }
      }
    }

    return MonthPlan(theory: theory, lab: lab);
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

    final totals = AttendanceTotals();

    for (final month in months ?? semesterMonths()) {
      final ctx = await _contextFor(
        department: department,
        year: year,
        month: month,
      );

      totals.merge(_totalsFrom(ctx, uid, batch));
    }

    return totals;
  }

  /// One student, split month by month.
  ///
  /// Keyed by `yyyy-MM`. Built from the same contexts as everything
  /// else, so the months add up to the semester figure exactly rather
  /// than approximately.
  Future<Map<String, AttendanceTotals>> byMonth({
    required String uid,
    required Map<String, dynamic> studentData,
    List<DateTime>? months,
  }) async {
    final department = AppConfig.departmentOf(studentData);
    final year = AppConfig.yearOf(studentData);
    final batch = (studentData['batch'] ?? '').toString();

    final out = <String, AttendanceTotals>{};

    for (final month in months ?? semesterMonths()) {
      final ctx = await _contextFor(
        department: department,
        year: year,
        month: month,
      );

      final id = '${month.year}-'
          '${month.month.toString().padLeft(2, '0')}';

      out[id] = _totalsFrom(ctx, uid, batch);
    }

    return out;
  }

  /// How many classes each subject has actually held this semester.
  ///
  /// Counted from the registers, not the timetable: the question is
  /// whether the syllabus will finish, and a class that was scheduled
  /// but never held does not move a subject any closer to done.
  ///
  /// Keyed by subject name, because that is what the timetable and the
  /// period records both carry — subject *ids* only exist in master
  /// data and never made it onto a period.
  Future<Map<String, int>> heldBySubject({
    required String department,
    required int year,
    List<DateTime>? months,
  }) async {
    final held = <String, int>{};

    for (final month in months ?? semesterMonths()) {
      final records = await _recordsFor(
        department: department,
        year: year,
        month: month,
      );

      // A lab split across batches is registered once per batch, and
      // that is one class taught twice, not two classes of syllabus.
      // Counting distinct date+period slots collapses them.
      final seen = <String, Set<String>>{};
      for (final r in records) {
        if (r.subject.isEmpty) continue;
        seen.putIfAbsent(r.subject, () => {}).add('${r.date}|${r.periodNo}');
      }

      seen.forEach((subject, slots) {
        held[subject] = (held[subject] ?? 0) + slots.length;
      });
    }

    return held;
  }

  /// Totals for a whole year group, computed from one shared resolve.
  ///
  /// [students] is uid -> student document. The months are resolved once
  /// and reused for everybody, so ranking sixty students costs one round
  /// of reads plus sixty passes of arithmetic — not sixty rounds of
  /// reads.
  Future<Map<String, AttendanceTotals>> forGroup({
    required Map<String, Map<String, dynamic>> students,
    List<DateTime>? months,
  }) async {
    final window = months ?? semesterMonths();
    final result = <String, AttendanceTotals>{};

    // Resolve every month each year group needs, once, before touching a
    // single student.
    final needed = <String, ({String department, int year})>{};

    for (final data in students.values) {
      final department = AppConfig.departmentOf(data);
      final year = AppConfig.yearOf(data);
      needed['$department|$year'] = (department: department, year: year);
    }

    final contexts = <String, List<_MonthContext>>{};

    for (final entry in needed.entries) {
      final resolved = <_MonthContext>[];

      for (final month in window) {
        resolved.add(await _contextFor(
          department: entry.value.department,
          year: entry.value.year,
          month: month,
        ));
      }

      contexts[entry.key] = resolved;
    }

    for (final entry in students.entries) {
      final data = entry.value;
      final group = '${AppConfig.departmentOf(data)}|'
          '${AppConfig.yearOf(data)}';
      final batch = (data['batch'] ?? '').toString();

      final totals = AttendanceTotals();
      for (final ctx in contexts[group] ?? const <_MonthContext>[]) {
        totals.merge(_totalsFrom(ctx, entry.key, batch));
      }

      result[entry.key] = totals;
    }

    return result;
  }
}
