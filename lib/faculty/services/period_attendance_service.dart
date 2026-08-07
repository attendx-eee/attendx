import 'package:cloud_firestore/cloud_firestore.dart';

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
