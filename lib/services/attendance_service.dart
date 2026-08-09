import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../admin/models/period_model.dart';
import '../admin/services/holiday_service.dart';
import '../admin/services/timetable_service.dart';
import '../attendance/models/manual_attendance_model.dart';
import '../attendance/services/manual_attendance_service.dart';
import '../core/constants/app_config.dart';

/// Attendance derived from Raspberry Pi check-in/check-out events.
///
/// The Pi writes one document per student per day to
/// [AppConfig.attendanceEventsCollection] with `checkIn` (first face match
/// at the entrance) and `checkOut` (latest exit). This service turns those
/// raw timestamps into attendance against fixed wall-clock cutoffs
/// ([AppConfig.presentCutoffOn] / [AppConfig.lateCutoffOn]):
///
/// - Present: checked in at or before [AppConfig.presentCutoffLabel]
///   (9:15 AM).
/// - Late: present, but checked in after [AppConfig.presentCutoffLabel],
///   up to and including [AppConfig.lateCutoffLabel] (9:30 AM).
/// - Absent: no check-in for a scheduled college day, or checked in after
///   [AppConfig.lateCutoffLabel] (9:30 AM) — arriving that late doesn't
///   count as present even though a check-in event exists.
/// What a single calendar day resolved to.
enum DayStatus {
  present,
  late,
  absent,

  /// Sunday, holiday, or a day with nothing on the timetable.
  noClass,

  /// Later than today — not judged yet.
  upcoming,
}

/// One day's verdict plus the manual mark behind it, if any. The screen
/// uses [manual] to badge corrected days and to prefill the edit sheet.
class DayVerdict {
  final DateTime date;
  final DayStatus status;
  final ManualAttendance? manual;

  /// Why the college was shut, when it was: "Independence Day", "Second
  /// Saturday", "Summer vacation". Null on an ordinary working day.
  ///
  /// Carried on the verdict rather than looked up again by the calendar
  /// because a closed day and a day with an empty timetable both come
  /// back as [DayStatus.noClass], and only one of them has a reason
  /// worth showing.
  final String? closureReason;

  const DayVerdict({
    required this.date,
    required this.status,
    required this.manual,
    this.closureReason,
  });

  bool get isHoliday => closureReason != null;

  bool get isManual => manual != null;

  /// Whether a status can be applied to this day at all.
  ///
  /// A closed day is excluded outright — not merely discouraged in the
  /// UI — so bulk selection can't sweep a holiday up with the working
  /// days around it. The exception is a day someone has *already* marked
  /// by hand, which stays editable so the mark can be removed.
  bool get isMarkable {
    if (isHoliday && manual == null) return false;
    return status != DayStatus.upcoming || manual != null;
  }
}

class AttendanceService {
  AttendanceService._();

  static final AttendanceService instance = AttendanceService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// (department|year|weekday) -> periods. Avoids re-reading the timetable.
  final Map<String, List<PeriodModel>> _scheduleCache = {};

  CollectionReference<Map<String, dynamic>> get _events =>
      _firestore.collection(AppConfig.attendanceEventsCollection);

  /// Drops the cached timetables. Called after the holiday calendar or
  /// the timetable itself changes, so the next read reflects it instead
  /// of serving whatever was true when the screen opened.
  void clearScheduleCache() => _scheduleCache.clear();

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
    /// When given, the day is also checked against the holiday
    /// calendar. Without it only the weekday is considered, which is
    /// what callers that genuinely want "the Monday timetable" expect.
    DateTime? on,
  }) async {
    if (weekday == 'Sunday') return const [];

    // A closed day has no scheduled periods, which is what makes the
    // rest of the pipeline treat it as "not a college day" rather than
    // marking everyone absent for a holiday.
    if (on != null && !HolidayService.instance.isWorkingDay(on, year: year)) {
      return const [];
    }

    final key = '$department|$year|$weekday';
    final cached = _scheduleCache[key];
    if (cached != null) return cached;

    try {
      final all = await TimetableService.instance.getDaySchedule(
        department: department,
        academicYear: AppConfig.academicYear,
        year: year,
        day: weekday,
      );

      final periods =
          all.where((p) => !p.isFree && p.subject.isNotEmpty).toList();

      _scheduleCache[key] = periods;
      return periods;
    } catch (e) {
      // Deliberately not cached. A failed read used to be stored as an
      // empty timetable, so one dropped request made the whole day look
      // like it had no classes for the rest of the session — and every
      // screen downstream reported "no classes scheduled" with complete
      // confidence. Better to retry on the next call.
      debugPrint('Schedule fetch failed ($key): $e');
      return const [];
    }
  }

  /// Classifies one day against the fixed 9:15 / 9:30 AM cutoffs. Returns
  /// null when the day has no scheduled classes (holiday / Sunday / empty
  /// timetable).
  ///
  /// A [manual] mark — recorded by an admin, or a CR the admin approved
  /// for that month — always wins. Manual marks exist precisely for the
  /// days the Pi got wrong (missed scan, camera down, on-duty, medical
  /// leave), so deferring to the derived verdict would defeat the point.
  /// A manual mark also forces the day to count even when the timetable
  /// shows nothing scheduled, since someone deliberately recorded it.
  ({bool present, bool late, int lateByMinutes})? classifyDay({
    required DateTime date,
    required List<PeriodModel> periods,
    required Timestamp? checkIn,
    ManualAttendance? manual,
  }) {
    if (manual != null) {
      return (
        present: manual.isPresent,
        late: manual.isLate,
        lateByMinutes: 0,
      );
    }

    if (periods.isEmpty) return null;

    final lastEnd = AppConfig.timeOn(date, periods.last.endTime);
    if (lastEnd == null) return null;

    if (checkIn == null) {
      return (present: false, late: false, lateByMinutes: 0);
    }

    final inTime = checkIn.toDate();

    // Checked in after the college day ended -> absent.
    if (inTime.isAfter(lastEnd)) {
      return (present: false, late: false, lateByMinutes: 0);
    }

    final presentCutoff = AppConfig.presentCutoffOn(date);
    final lateCutoff = AppConfig.lateCutoffOn(date);

    // Checked in after 9:30 AM -> absent, regardless of a valid check-in.
    if (inTime.isAfter(lateCutoff)) {
      return (present: false, late: false, lateByMinutes: 0);
    }

    final lateByMinutes =
        inTime.isAfter(presentCutoff) ? inTime.difference(presentCutoff).inMinutes : 0;

    return (
      present: true,
      late: lateByMinutes > 0,
      lateByMinutes: lateByMinutes,
    );
  }

  /// Rolls a [semesterStats] map up into one headline figure.
  ///
  /// Exists so the dashboard's alert and the attendance page's summary
  /// can't disagree. They used to compute the total independently — the
  /// dashboard summed these months, the attendance page ran its own day
  /// loop with slightly different rules about today and about days with
  /// no timetable — and reported 71.9% and 67.6% for the same student on
  /// the same afternoon. Whichever number is right, showing both is
  /// worse than either.
  ///
  /// A late day counts as present. Punctuality is reported separately,
  /// not deducted twice.
  static ({int present, int absent, int late, int total, double percent})
      rollUp(Map<String, Map<String, int>> stats) {
    var present = 0, absent = 0, late = 0;

    for (final month in stats.values) {
      present += month['present'] ?? 0;
      absent += month['absent'] ?? 0;
      late += month['late'] ?? 0;
    }

    final total = present + absent;

    return (
      present: present,
      absent: absent,
      late: late,
      total: total,
      percent: total == 0 ? 0 : (present / total) * 100,
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

      // Warm the holiday cache before any day is judged. It's checked
      // synchronously per-day inside the loop below, and an unloaded
      // cache silently reports every holiday as a working day — which
      // would mark a whole class absent for Sankranti.
      await HolidayService.instance.all();

      // One query for all of this student's events (uid is a single-field
      // filter — no composite index required).
      final snapshot = await _events.where('uid', isEqualTo: uid).get();

      final eventsByDate = <String, Map<String, dynamic>>{
        for (final doc in snapshot.docs)
          (doc.data()['date'] ?? '').toString(): doc.data(),
      };

      // Manual corrections layered on top of the Pi's record.
      final manualByDate =
          await ManualAttendanceService.instance.forStudent(uid);

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
            on: date,
          );

          final dateId = AppConfig.dateId(date);
          final event = eventsByDate[dateId];
          final verdict = classifyDay(
            date: date,
            periods: periods,
            checkIn: event?['checkIn'] is Timestamp
                ? event!['checkIn'] as Timestamp
                : null,
            manual: manualByDate[dateId],
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

  /// Per-day verdict for one calendar month, for the marking calendar.
  ///
  /// [manualByDate] is passed in rather than fetched so the calling screen
  /// can drive it from a live stream and repaint the moment a mark is
  /// written, without this service re-querying on every rebuild.
  Future<Map<int, DayVerdict>> monthVerdicts({
    required Map<String, dynamic> studentData,
    required Map<String, Map<String, dynamic>> eventsByDate,
    required Map<String, ManualAttendance> manualByDate,
    required int calendarYear,
    required int month,
  }) async {
    final department = AppConfig.departmentOf(studentData);
    final year = AppConfig.yearOf(studentData);

    // Same reason as semesterStats: the per-day holiday check is
    // synchronous, so the cache has to be filled before the loop starts.
    await HolidayService.instance.all();

    final daysInMonth = DateTime(calendarYear, month + 1, 0).day;
    final today = DateTime.now();
    final result = <int, DayVerdict>{};

    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(calendarYear, month, d);
      final dateId = AppConfig.dateId(date);
      final manual = manualByDate[dateId];

      final closure =
          HolidayService.instance.closureReason(date, year: year);

      final periods = await scheduledPeriods(
        department: department,
        year: year,
        weekday: AppConfig.dayName(date),
        on: date,
      );

      final future = date.isAfter(DateTime(today.year, today.month, today.day));

      // Future days are shown but not judged — nothing has happened yet.
      // A manual mark is still honoured (an admin may pre-record planned
      // on-duty or approved leave).
      if (future && manual == null) {
        result[d] = DayVerdict(
          date: date,
          status: periods.isEmpty ? DayStatus.noClass : DayStatus.upcoming,
          manual: null,
          closureReason: closure,
        );
        continue;
      }

      final event = eventsByDate[dateId];
      final verdict = classifyDay(
        date: date,
        periods: periods,
        checkIn: event?['checkIn'] is Timestamp
            ? event!['checkIn'] as Timestamp
            : null,
        manual: manual,
      );

      final DayStatus status;
      if (verdict == null) {
        status = DayStatus.noClass;
      } else if (!verdict.present) {
        status = DayStatus.absent;
      } else if (verdict.late) {
        status = DayStatus.late;
      } else {
        status = DayStatus.present;
      }

      result[d] = DayVerdict(
        date: date,
        status: status,
        manual: manual,
        closureReason: closure,
      );
    }

    return result;
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
