import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../admin/models/period_model.dart';
import '../../core/constants/app_config.dart';
import '../models/timetable_override_model.dart';

/// What actually happened on a given date, as opposed to what the
/// master timetable says usually happens.
///
/// Overrides used to be display-only. The CR could cancel a class and
/// the dashboard would show it struck through, but every attendance
/// calculation still read the plain weekly grid — so a cancelled class
/// counted as held and every student in the year lost a class they were
/// never offered. In the other direction there was no way to *add* a
/// class at all.
///
/// Everything that asks "which classes were there on this date" goes
/// through here now, so a cancellation and an extra class both land in
/// the attendance figures without any screen having to remember to
/// apply them.
class ScheduleResolver {
  ScheduleResolver._();

  static final ScheduleResolver instance = ScheduleResolver._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String collectionName = 'timetable_overrides';

  /// department|year|date -> overrides for that day.
  final Map<String, List<TimetableOverride>> _cache = {};

  void clearCache() => _cache.clear();

  Future<List<TimetableOverride>> overridesFor({
    required String department,
    required int year,
    required String date,
  }) async {
    final key = '$department|$year|$date';

    final cached = _cache[key];
    if (cached != null) return cached;

    try {
      final snap = await _firestore
          .collection(collectionName)
          .where('department', isEqualTo: department)
          .where('year', isEqualTo: year)
          .where('date', isEqualTo: date)
          .get();

      final list =
          snap.docs.map(TimetableOverride.fromFirestore).toList();

      _cache[key] = list;
      return list;
    } catch (e) {
      // Not cached: a dropped read should be retried rather than
      // remembered as "no changes today", which would quietly reinstate
      // a cancelled class.
      debugPrint('Override fetch failed ($key): $e');
      return const [];
    }
  }

  /// Loads a whole month's overrides in one query.
  ///
  /// Walking a semester day by day would otherwise mean one read per
  /// date per student. Range-queried on the `date` string, which sorts
  /// correctly because it is zero-padded yyyy-MM-dd.
  ///
  /// Returns date -> overrides, and fills the per-date cache so
  /// [resolve] finds them without going back to the network.
  Future<Map<String, List<TimetableOverride>>> preloadMonth({
    required String department,
    required int year,
    required DateTime month,
  }) async {
    final prefix =
        '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final result = <String, List<TimetableOverride>>{};

    try {
      final snap = await _firestore
          .collection(collectionName)
          .where('department', isEqualTo: department)
          .where('year', isEqualTo: year)
          .where('date', isGreaterThanOrEqualTo: '$prefix-01')
          .where('date', isLessThanOrEqualTo: '$prefix-31')
          .get();

      for (final doc in snap.docs) {
        final o = TimetableOverride.fromFirestore(doc);
        result.putIfAbsent(o.date, () => []).add(o);
      }

      // Cache every date in the month, including the empty ones, so a
      // day with no changes doesn't trigger its own lookup later.
      final days = DateTime(month.year, month.month + 1, 0).day;
      for (var d = 1; d <= days; d++) {
        final date = '$prefix-${d.toString().padLeft(2, '0')}';
        _cache['$department|$year|$date'] = result[date] ?? const [];
      }
    } catch (e) {
      debugPrint('Override month preload failed ($prefix): $e');
    }

    return result;
  }

  /// Lays [overrides] over the weekday timetable in [base].
  ///
  /// Pure, so the layering rules can be reasoned about — and tested —
  /// without a network.
  static List<PeriodModel> apply({
    required List<PeriodModel> base,
    required List<TimetableOverride> overrides,
  }) {
    if (overrides.isEmpty) return base;

    final byPeriod = {for (final o in overrides) o.periodNo: o};
    final out = <PeriodModel>[];

    for (final period in base) {
      final change = byPeriod[period.periodNo];

      if (change == null) {
        out.add(period);
        continue;
      }

      switch (change.type) {
        case OverrideType.cancelled:
          // Dropped entirely. A class that didn't happen can't be
          // attended, and counting it makes the whole year look worse
          // for a decision taken above them.
          break;

        case OverrideType.replacement:
          out.add(PeriodModel(
            periodNo: period.periodNo,
            startTime: change.startTime.isEmpty
                ? period.startTime
                : change.startTime,
            endTime:
                change.endTime.isEmpty ? period.endTime : change.endTime,
            subject: change.newSubject.isEmpty
                ? period.subject
                : change.newSubject,
            facultyId: period.facultyId,
            facultyName: change.newFacultyName.isEmpty
                ? period.facultyName
                : change.newFacultyName,
            room: change.newRoom.isEmpty ? period.room : change.newRoom,
            classType: period.classType,
            batch: period.batch,
            isFree: false,
            status: period.status,
          ));

        case OverrideType.roomChange:
          out.add(PeriodModel(
            periodNo: period.periodNo,
            startTime: period.startTime,
            endTime: period.endTime,
            subject: period.subject,
            facultyId: period.facultyId,
            facultyName: period.facultyName,
            room: change.newRoom.isEmpty ? period.room : change.newRoom,
            classType: period.classType,
            batch: period.batch,
            isFree: false,
            status: period.status,
          ));

        default:
          out.add(period);
      }
    }

    // Extra classes occupy slots the master timetable left empty, so
    // they are added rather than merged. Guarded against a slot that
    // stopped being vacant since the CR booked it — the timetable wins,
    // because a real class has a room and a lecturer behind it.
    final taken = out.map((p) => p.periodNo).toSet();

    for (final o in overrides) {
      if (o.type != OverrideType.extraClass) continue;
      if (taken.contains(o.periodNo)) continue;

      out.add(PeriodModel(
        periodNo: o.periodNo,
        startTime: o.startTime,
        endTime: o.endTime,
        subject: o.newSubject,
        facultyId: '',
        facultyName: o.newFacultyName,
        room: o.newRoom,
        classType: o.classType,
        batch: o.batch,
        isFree: false,
        status: 'approved',
      ));
    }

    out.sort((a, b) => a.periodNo.compareTo(b.periodNo));
    return out;
  }

  /// The effective timetable for one date.
  Future<List<PeriodModel>> resolve({
    required String department,
    required int year,
    required DateTime date,
    required List<PeriodModel> base,
  }) async {
    final overrides = await overridesFor(
      department: department,
      year: year,
      date: AppConfig.dateId(date),
    );

    return apply(base: base, overrides: overrides);
  }

  /// Period numbers the year has free on [date].
  ///
  /// What the CR picks from when adding an extra class. A slot already
  /// holding a class isn't offered, and neither is one another extra
  /// class has already claimed.
  Future<List<int>> vacantPeriods({
    required String department,
    required int year,
    required DateTime date,
    required List<PeriodModel> base,
    int periodsPerDay = 7,
  }) async {
    final resolved = await resolve(
      department: department,
      year: year,
      date: date,
      base: base,
    );

    final busy = resolved.map((p) => p.periodNo).toSet();

    return [
      for (var n = 1; n <= periodsPerDay; n++)
        if (!busy.contains(n)) n,
    ];
  }
}
