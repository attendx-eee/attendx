import 'package:cloud_firestore/cloud_firestore.dart';

import '../../admin/models/period_model.dart';
import '../../admin/services/holiday_service.dart';
import '../../attendance/models/day_summary.dart';
import '../../services/attendance_service.dart';
import '../../core/constants/app_config.dart';
import '../../notifications/services/notification_service.dart';
import '../models/period_attendance.dart';

/// Reads and writes per-period class attendance.
class PeriodAttendanceService {
  PeriodAttendanceService._();

  static final PeriodAttendanceService instance =
      PeriodAttendanceService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String collectionName = 'period_attendance';

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(collectionName);

  /// Saves a period, replacing any earlier record for the same slot.
  ///
  /// Re-marking a period is a normal thing to want — a faculty member
  /// notices a mistake, or a student turns up late — so the id is
  /// deterministic and the write overwrites rather than appending. The
  /// audit fields say who last touched it.
  Future<void> save(PeriodAttendance record) async {
    final id = PeriodAttendance.buildId(
      department: record.department,
      year: record.year,
      date: record.date,
      periodNo: record.periodNo,
    );

    await _collection.doc(id).set(record.toMap());
  }

  /// Tells the students who were marked absent, so a wrong mark can be
  /// challenged the same day rather than discovered at the end of term.
  ///
  /// Only absences are announced. A "you were present" notification for
  /// every student after every period would be six messages a day of
  /// pure noise, and nobody would read the seventh.
  Future<void> notifyAbsentees({
    required PeriodAttendance record,
    required List<String> allStudentUids,
  }) async {
    final absent =
        allStudentUids.where((uid) => !record.wasPresent(uid)).toList();

    if (absent.isEmpty) return;

    const chunkSize = 400;
    for (var i = 0; i < absent.length; i += chunkSize) {
      final batch = _firestore.batch();

      for (final uid in absent.skip(i).take(chunkSize)) {
        batch.set(_firestore.collection('notifications').doc(), {
          'studentUid': uid,
          'title': 'Marked absent: ${record.subject}',
          'body': 'You were marked absent for ${record.subject} '
              '(${record.startTime} - ${record.endTime}) on ${record.date} '
              'by ${record.facultyName}. If this is wrong, speak to them '
              'today.',
          'category': 'attendance',
          'priority': 'high',
          'read': false,
          // See NotificationService.createNotification — the push
          // worker sweeps on this flag.
          'pushed': false,
          'createdAt': FieldValue.serverTimestamp(),
          'action': 'period_attendance',
          'data': {
            'date': record.date,
            'periodNo': record.periodNo,
            'subject': record.subject,
          },
        });
      }

      await batch.commit();
    }
  }

  /// One period's record, or null if it hasn't been marked.
  Future<PeriodAttendance?> forPeriod({
    required String department,
    required int year,
    required String date,
    required int periodNo,
  }) async {
    final doc = await _collection
        .doc(PeriodAttendance.buildId(
          department: department,
          year: year,
          date: date,
          periodNo: periodNo,
        ))
        .get();

    return doc.exists ? PeriodAttendance.fromFirestore(doc) : null;
  }

  /// Every period marked on one date for a year — what the faculty home
  /// uses to show which of today's classes are already done.
  Stream<List<PeriodAttendance>> watchDay({
    required String department,
    required int year,
    required String date,
  }) {
    return _collection
        .where('department', isEqualTo: department)
        .where('year', isEqualTo: year)
        .where('date', isEqualTo: date)
        .snapshots()
        .map((snap) {
      final list =
          snap.docs.map((d) => PeriodAttendance.fromFirestore(d)).toList();
      list.sort((a, b) => a.periodNo.compareTo(b.periodNo));
      return list;
    });
  }

  /// One date's records for a year, keyed by period number.
  ///
  /// The one-shot sibling of [watchDay] — used where a screen needs the
  /// day once and then edits it, and a live stream would fight the
  /// local edits for control of the checkboxes.
  Future<Map<int, PeriodAttendance>> dayForYear({
    required String department,
    required int year,
    required String date,
  }) async {
    final snap = await _collection
        .where('department', isEqualTo: department)
        .where('year', isEqualTo: year)
        .where('date', isEqualTo: date)
        .get();

    final records = snap.docs.map(PeriodAttendance.fromFirestore);
    return {for (final r in records) r.periodNo: r};
  }

  /// Every period a year had in one month.
  ///
  /// Queried by year and month rather than by student: Firestore can't
  /// index "documents whose presentUids array does NOT contain X", so
  /// absence has to be worked out client-side from the roster. Fetching
  /// the year's month is one query; the alternative is one per day.
  Future<List<PeriodAttendance>> monthForYear({
    required String department,
    required int year,
    required String month,
  }) async {
    final snap = await _collection
        .where('department', isEqualTo: department)
        .where('year', isEqualTo: year)
        .where('month', isEqualTo: month)
        .get();

    final list =
        snap.docs.map((d) => PeriodAttendance.fromFirestore(d)).toList();
    list.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.periodNo.compareTo(b.periodNo);
    });
    return list;
  }

  /// Marks one student class by class on one day.
  ///
  /// This is the admin's partial-attendance path: the day's timetable is
  /// laid out, the admin ticks the classes the student actually attended,
  /// and every other class that day is recorded as an absence for them.
  /// Whole-day present and whole-day absent stay on the day-level manual
  /// override — this exists for the case those two can't express.
  ///
  /// Only this student's entry is touched. Where a faculty member has
  /// already scanned the period, their record is amended in place; where
  /// nobody has marked it, a new record is created **scoped to this
  /// student**, so it doesn't quietly declare the rest of the year absent
  /// for a class that was never registered.
  ///
  /// Returns the number of periods written.
  Future<int> markStudentDay({
    required String uid,
    required Map<String, dynamic> studentData,
    required DateTime date,
    required List<PeriodModel> periods,
    required Set<int> presentPeriodNos,
    required String markerUid,
    required String markerName,
    required String markerRole,
  }) async {
    final department = AppConfig.departmentOf(studentData);
    final year = AppConfig.yearOf(studentData);
    final dateId = AppConfig.dateId(date);

    // Deliberately not re-filtered by batch. The caller passes exactly
    // the classes it put in front of the admin, and filtering again here
    // would silently drop rows they ticked — the worst kind of bug,
    // because the screen would report a save that never happened.
    final relevant =
        periods.where((p) => !p.isFree && p.subject.isNotEmpty).toList();

    if (relevant.isEmpty) return 0;

    final refs = {
      for (final p in relevant)
        p.periodNo: _collection.doc(PeriodAttendance.buildId(
          department: department,
          year: year,
          date: dateId,
          periodNo: p.periodNo,
        )),
    };

    // Read before writing: arrayUnion alone would leave presentCount
    // stale, and knowing whether the document already exists is what
    // decides between amending a class register and creating a
    // single-student one.
    final existing = await Future.wait(
      relevant.map((p) => refs[p.periodNo]!.get()),
    );

    final batch = _firestore.batch();

    for (var i = 0; i < relevant.length; i++) {
      final period = relevant[i];
      final doc = existing[i];
      final present = presentPeriodNos.contains(period.periodNo);

      if (doc.exists) {
        final current = PeriodAttendance.fromFirestore(doc);

        final presentUids = current.presentUids.toSet();
        if (present) {
          presentUids.add(uid);
        } else {
          presentUids.remove(uid);
        }

        // A whole-class record stays whole-class. A record that was
        // already scoped to named students grows to include this one,
        // since it now speaks for them too.
        final scope = current.scopeUids.isEmpty
            ? const <String>[]
            : ({...current.scopeUids, uid}.toList());

        batch.set(
          refs[period.periodNo]!,
          {
            'presentUids': presentUids.toList(),
            'presentCount': presentUids.length,
            'scopeUids': scope,
            'lastEditedBy': markerUid,
            'lastEditedByName': '$markerName (${markerRole.toUpperCase()})',
            'lastEditedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } else {
        batch.set(
          refs[period.periodNo]!,
          PeriodAttendance(
            id: '',
            department: department,
            year: year,
            academicYear: AppConfig.academicYear,
            date: dateId,
            periodNo: period.periodNo,
            startTime: period.startTime,
            endTime: period.endTime,
            subject: period.subject,
            batch: period.batch,
            facultyId: period.facultyId,
            facultyName: period.facultyName,
            presentUids: present ? [uid] : const [],
            recognisedUids: const [],
            scopeUids: [uid],
            method: PeriodAttendanceMethod.manual,
            markedBy: markerUid,
            markedByName: '$markerName (${markerRole.toUpperCase()})',
          ).toMap(),
        );
      }
    }

    await batch.commit();

    final attended = presentPeriodNos
        .where((n) => relevant.any((p) => p.periodNo == n))
        .length;

    await NotificationService.instance.createNotification(
      studentUid: uid,
      title: 'Attendance updated for $dateId',
      body: attended == relevant.length
          ? 'You have been marked present for all ${relevant.length} '
              'classes on $dateId by $markerName.'
          : attended == 0
              ? 'You have been marked absent for all ${relevant.length} '
                  'classes on $dateId by $markerName.'
              : 'You have been marked present for $attended of '
                  '${relevant.length} classes on $dateId by $markerName. '
                  'If this is wrong, raise it with the department.',
      category: 'attendance',
      priority: 'high',
      action: 'period_attendance',
      data: {'date': dateId},
    );

    return relevant.length;
  }

  /// A student's month, day by day, counted from period records.
  ///
  /// This is what makes a day worth "1 of 2" rather than a flat present
  /// or absent. The timetable says what was scheduled; the period
  /// records say what was attended; the difference is the fraction.
  ///
  /// Returns {day-of-month: summary} plus the rolled-up totals, since
  /// every caller that wants one wants the other.
  Future<({Map<int, DaySummary> days, AttendanceTotals totals})> monthSummary({
    required String uid,
    required Map<String, dynamic> studentData,
    required int calendarYear,
    required int month,
  }) async {
    final department = AppConfig.departmentOf(studentData);
    final year = AppConfig.yearOf(studentData);
    final batch = (studentData['batch'] ?? '').toString();

    final monthId =
        '$calendarYear-${month.toString().padLeft(2, '0')}';

    // One query for the whole month, then grouped by date — far cheaper
    // than a read per day.
    final records = await monthForYear(
      department: department,
      year: year,
      month: monthId,
    );

    final byDate = <String, Map<int, PeriodAttendance>>{};
    for (final r in records) {
      byDate.putIfAbsent(r.date, () => {})[r.periodNo] = r;
    }

    await HolidayService.instance.all();

    final daysInMonth = DateTime(calendarYear, month + 1, 0).day;
    final today = DateTime.now();
    final days = <int, DaySummary>{};
    final totals = AttendanceTotals();

    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(calendarYear, month, d);
      if (date.isAfter(DateTime(today.year, today.month, today.day))) break;

      final periods = await AttendanceService.instance.scheduledPeriods(
        department: department,
        year: year,
        weekday: AppConfig.dayName(date),
        on: date,
      );

      final summary = DaySummaryBuilder.build(
        date: date,
        uid: uid,
        periods: periods,
        records: byDate[AppConfig.dateId(date)] ?? const {},
        studentBatch: batch,
      );

      days[d] = summary;
      totals.add(summary);
    }

    return (days: days, totals: totals);
  }

  /// Subject-wise totals for one student over a month.
  ///
  /// Returns {subject: (attended, total)} — the shape a "you are at 68%
  /// in Power Systems" line needs.
  Future<Map<String, ({int attended, int total})>> subjectTotals({
    required String uid,
    required Map<String, dynamic> studentData,
    required String month,
  }) async {
    final periods = await monthForYear(
      department: AppConfig.departmentOf(studentData),
      year: AppConfig.yearOf(studentData),
      month: month,
    );

    final tally = <String, ({int attended, int total})>{};

    for (final p in periods) {
      if (!p.covers(uid)) continue;

      // A lab period marked for batch B says nothing about a student in
      // batch A — they weren't expected to be there.
      if (p.batch.isNotEmpty) {
        final studentBatch = (studentData['batch'] ?? '').toString();
        if (studentBatch.isNotEmpty && studentBatch != p.batch) continue;
      }

      final current = tally[p.subject] ?? (attended: 0, total: 0);
      tally[p.subject] = (
        attended: current.attended + (p.wasPresent(uid) ? 1 : 0),
        total: current.total + 1,
      );
    }

    return tally;
  }

  /// Sends one student a summary after their period is saved. Used by
  /// the roster screen for late corrections.
  Future<void> notifyCorrection({
    required String uid,
    required PeriodAttendance record,
    required bool present,
  }) {
    return NotificationService.instance.createNotification(
      studentUid: uid,
      title: present
          ? 'Attendance corrected: ${record.subject}'
          : 'Marked absent: ${record.subject}',
      body: present
          ? 'You have been marked present for ${record.subject} '
              '(${record.startTime}) on ${record.date}.'
          : 'You have been marked absent for ${record.subject} '
              '(${record.startTime}) on ${record.date}.',
      category: 'attendance',
      priority: 'normal',
      action: 'period_attendance',
      data: {'date': record.date, 'periodNo': record.periodNo},
    );
  }
}
