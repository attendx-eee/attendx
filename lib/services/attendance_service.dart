import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../admin/models/period_model.dart';
import '../admin/services/timetable_service.dart';
import '../core/constants/app_config.dart';

/// Attendance derived from Raspberry Pi check-in/check-out events.
///
/// The Pi writes one document per student per day to
/// [AppConfig.attendanceEventsCollection] with `checkIn` (first face match
/// at the entrance) and `checkOut` (latest exit). This service turns those
/// raw timestamps into attendance against the timetable:
///
/// - Present: checked in no later than [AppConfig.presentGraceMinutes]
///   (20 min) after the first scheduled period starts — or any time before
///   the last period ends.
/// - Late: present, but check-in was more than
///   [AppConfig.onTimeGraceMinutes] (10 min) after the first period start.
/// - Absent: a scheduled college day with no valid check-in.
class AttendanceService {
  AttendanceService._();

  static final AttendanceService instance = AttendanceService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// (department|year|weekday) -> periods. Avoids re-reading the timetable.
  final Map<String, List<PeriodModel>> _scheduleCache = {};

  CollectionReference<Map<String, dynamic>> get _events =>
      _firestore.collection(AppConfig.attendanceEventsCollection);

  /// Today's raw event doc for the student (feeds the dashboard card).
  Future<DocumentSnapshot<Map<String, dynamic>>> todayEvent(String uid) {
    return _events
        .doc(AppConfig.attendanceEventDocId(uid, DateTime.now()))
        .get();
  }

  /// Scheduled (non-free) periods for a department/year/weekday, cached.
  Future<List<PeriodModel>> scheduledPeriods({
    required String department,
    required int year,
    required String weekday,
  }) async {
    if (weekday == 'Sunday') return const [];

    final key = '$department|$year|$weekday';
    final cached = _scheduleCache[key];
    if (cached != null) return cached;

    List<PeriodModel> periods = const [];
    try {
      final all = await TimetableService.instance.getDaySchedule(
        department: department,
        academicYear: AppConfig.academicYear,
        year: year,
        day: weekday,
      );
      periods =
          all.where((p) => !p.isFree && p.subject.isNotEmpty).toList();
    } catch (e) {
      debugPrint('Schedule fetch failed ($key): $e');
    }

    _scheduleCache[key] = periods;
    return periods;
  }

  /// Classifies one day. Returns null when the day has no scheduled
  /// classes (holiday / Sunday / empty timetable).
  ({bool present, bool late, int lateByMinutes})? classifyDay({
    required DateTime date,
    required List<PeriodModel> periods,
    required Timestamp? checkIn,
  }) {
    if (periods.isEmpty) return null;

    final firstStart = AppConfig.timeOn(date, periods.first.startTime);
    final lastEnd = AppConfig.timeOn(date, periods.last.endTime);
    if (firstStart == null || lastEnd == null) return null;

    if (checkIn == null) {
      return (present: false, late: false, lateByMinutes: 0);
    }

    final inTime = checkIn.toDate();

    // Checked in after the college day ended -> absent.
    if (inTime.isAfter(lastEnd)) {
      return (present: false, late: false, lateByMinutes: 0);
    }

    final lateBy = inTime.difference(firstStart).inMinutes;

    return (
      present: true,
      late: lateBy > AppConfig.onTimeGraceMinutes,
      lateByMinutes: lateBy > 0 ? lateBy : 0,
    );
  }

  /// Real monthly attendance for the semester, replacing hardcoded stats.
  ///
  /// Returns {monthName: {present, absent, total, late}} for every month
  /// in [months] (missing data = zeros, so UI code can rely on the keys).
  Future<Map<String, Map<String, int>>> semesterStats({
    required String uid,
    required Map<String, dynamic> studentData,
    required List<String> months,
  }) async {
    final result = <String, Map<String, int>>{
      for (final m in months) m: {'present': 0, 'absent': 0, 'total': 0, 'late': 0},
    };

    try {
      final department = AppConfig.departmentOf(studentData);
      final year = AppConfig.yearOf(studentData);

      // One query for all of this student's events (uid is a single-field
      // filter — no composite index required).
      final snapshot = await _events.where('uid', isEqualTo: uid).get();

      final eventsByDate = <String, Map<String, dynamic>>{
        for (final doc in snapshot.docs)
          (doc.data()['date'] ?? '').toString(): doc.data(),
      };

      const monthNumbers = {
        'January': 1, 'February': 2, 'March': 3, 'April': 4,
        'May': 5, 'June': 6, 'July': 7, 'August': 8,
        'September': 9, 'October': 10, 'November': 11, 'December': 12,
      };

      // Jul-Dec belong to the first calendar year of the academic year,
      // Jan-Jun to the second (e.g. 2026-2027).
      final firstYear =
          int.tryParse(AppConfig.academicYear.split('-').first) ??
              DateTime.now().year;

      final today = DateTime.now();

      for (final monthName in months) {
        final monthNo = monthNumbers[monthName];
        if (monthNo == null) continue;

        final calendarYear = monthNo >= 7 ? firstYear : firstYear + 1;
        final daysInMonth = DateTime(calendarYear, monthNo + 1, 0).day;
        final stats = result[monthName]!;

        for (var d = 1; d <= daysInMonth; d++) {
          final date = DateTime(calendarYear, monthNo, d);

          // Only count days that have already happened.
          if (date.isAfter(today)) break;

          final weekday = AppConfig.dayName(date);
          final periods = await scheduledPeriods(
            department: department,
            year: year,
            weekday: weekday,
          );

          final event = eventsByDate[AppConfig.dateId(date)];
          final verdict = classifyDay(
            date: date,
            periods: periods,
            checkIn: event?['checkIn'] is Timestamp
                ? event!['checkIn'] as Timestamp
                : null,
          );

          if (verdict == null) continue; // not a college day

          stats['total'] = stats['total']! + 1;
          if (verdict.present) {
            stats['present'] = stats['present']! + 1;
            if (verdict.late) stats['late'] = stats['late']! + 1;
          } else {
            stats['absent'] = stats['absent']! + 1;
          }
        }
      }
    } catch (e) {
      debugPrint('semesterStats failed: $e');
    }

    return result;
  }

  /// All events for one date (admin insights). Filter by student uids
  /// client-side if needed.
  Future<List<Map<String, dynamic>>> eventsOn(String dateId) async {
    final snapshot = await _events.where('date', isEqualTo: dateId).get();
    return snapshot.docs.map((d) => d.data()).toList();
  }

  /// All events for one student, keyed by date id. Single-field query —
  /// no composite index needed.
  Future<Map<String, Map<String, dynamic>>> eventsFor(String uid) async {
    final snapshot = await _events.where('uid', isEqualTo: uid).get();
    return {
      for (final doc in snapshot.docs)
        (doc.data()['date'] ?? '').toString(): doc.data(),
    };
  }

  /// First day of the current semester (Jul 1 or Jan 1 of the academic year).
  DateTime semesterStart() {
    final firstYear =
        int.tryParse(AppConfig.academicYear.split('-').first) ??
            DateTime.now().year;
    final now = DateTime.now();
    return now.month >= 7
        ? DateTime(firstYear, 7, 1)
        : DateTime(firstYear + 1, 1, 1);
  }

  /// Whether the student's presence interval covered a specific period.
  /// Attended = checked in before the period ended (with grace) and did
  /// not check out before it started.
  bool periodAttended({
    required DateTime date,
    required PeriodModel period,
    required Timestamp? checkIn,
    required Timestamp? checkOut,
  }) {
    if (checkIn == null) return false;

    final start = AppConfig.timeOn(date, period.startTime);
    final end = AppConfig.timeOn(date, period.endTime);
    if (start == null || end == null) return false;

    final inTime = checkIn.toDate();
    if (inTime.isAfter(
        start.add(const Duration(minutes: AppConfig.presentGraceMinutes)))) {
      // Arrived too late for this period — maybe attended later ones.
      if (inTime.isAfter(end)) return false;
    }

    final today = AppConfig.dateId(DateTime.now()) == AppConfig.dateId(date);
    final outTime =
        checkOut?.toDate() ?? (today ? DateTime.now() : end);

    return outTime.isAfter(start);
  }
}
