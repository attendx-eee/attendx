import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/constants/app_config.dart';
import '../../notifications/services/notification_service.dart';
import '../models/manual_attendance_model.dart';

/// Reads and writes manual attendance corrections.
///
/// Deliberately a thin layer over one collection: the merge with the Pi's
/// derived verdict happens in [AttendanceService], so every existing
/// caller (dashboard, calendar, insights, PDF export) picks up manual
/// marks without knowing this collection exists.
class ManualAttendanceService {
  ManualAttendanceService._();

  static final ManualAttendanceService instance = ManualAttendanceService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String collectionName = 'attendance_manual';

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(collectionName);

  /// Every manual mark for one student, keyed by date id (yyyy-MM-dd).
  /// Single-field query — no composite index needed.
  Future<Map<String, ManualAttendance>> forStudent(String uid) async {
    final snapshot = await _collection.where('uid', isEqualTo: uid).get();
    return {
      for (final doc in snapshot.docs)
        (doc.data()['date'] ?? '').toString():
            ManualAttendance.fromFirestore(doc),
    };
  }

  /// Live version of [forStudent] — powers the marking calendar so a new
  /// mark shows up the instant it's written.
  Stream<Map<String, ManualAttendance>> watchStudent(String uid) {
    return _collection.where('uid', isEqualTo: uid).snapshots().map(
          (snapshot) => {
            for (final doc in snapshot.docs)
              (doc.data()['date'] ?? '').toString():
                  ManualAttendance.fromFirestore(doc),
          },
        );
  }

  /// All manual marks on one date, keyed by student uid (admin insights).
  Future<Map<String, ManualAttendance>> onDate(String dateId) async {
    final snapshot = await _collection.where('date', isEqualTo: dateId).get();
    return {
      for (final doc in snapshot.docs)
        (doc.data()['uid'] ?? '').toString():
            ManualAttendance.fromFirestore(doc),
    };
  }

  /// Records (or replaces) a manual mark and tells the student, so an
  /// attendance change never happens silently behind their back.
  Future<void> mark({
    required String uid,
    required String studentName,
    required Map<String, dynamic> studentData,
    required DateTime date,
    required String status,
    required String markerName,
    required String markerRole,
    String reason = '',
  }) async {
    final dateId = AppConfig.dateId(date);
    final markerUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    final record = ManualAttendance(
      id: ManualAttendance.buildId(uid, dateId),
      uid: uid,
      date: dateId,
      month: ManualAttendance.monthOf(dateId),
      department: AppConfig.departmentOf(studentData),
      year: AppConfig.yearOf(studentData),
      status: status,
      reason: reason,
      markedBy: markerUid,
      markedByName: markerName,
      markedByRole: markerRole,
    );

    await _collection.doc(record.id).set(record.toMap());

    await NotificationService.instance.createNotification(
      studentUid: uid,
      title: 'Attendance Updated: ${ManualAttendanceStatus.label(status)}',
      body: 'Your attendance for $dateId was marked as '
          '${ManualAttendanceStatus.label(status).toLowerCase()} by '
          '$markerName${reason.isEmpty ? '' : '.\nReason: $reason'}',
      category: 'attendance',
      priority: 'high',
      action: 'manual_attendance',
      data: {'date': dateId, 'status': status},
    );
  }

  /// Marks several days at once.
  ///
  /// Correcting attendance is rarely a one-day job — a student is off
  /// sick for a week, or the scanner is down for three days and the
  /// whole class needs fixing. Doing that a day at a time is one
  /// Firestore round trip and one notification per day; this is a single
  /// batch and a single notification summarising the lot.
  ///
  /// Returns the number of days written.
  Future<int> markMany({
    required String uid,
    required Map<String, dynamic> studentData,
    required List<DateTime> dates,
    required String status,
    required String markerName,
    required String markerRole,
    String reason = '',
  }) async {
    if (dates.isEmpty) return 0;

    final markerUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final department = AppConfig.departmentOf(studentData);
    final year = AppConfig.yearOf(studentData);

    // Firestore caps a batch at 500 writes.
    const chunkSize = 400;
    final sorted = [...dates]..sort();

    for (var i = 0; i < sorted.length; i += chunkSize) {
      final batch = _firestore.batch();

      for (final date in sorted.skip(i).take(chunkSize)) {
        final dateId = AppConfig.dateId(date);
        final record = ManualAttendance(
          id: ManualAttendance.buildId(uid, dateId),
          uid: uid,
          date: dateId,
          month: ManualAttendance.monthOf(dateId),
          department: department,
          year: year,
          status: status,
          reason: reason,
          markedBy: markerUid,
          markedByName: markerName,
          markedByRole: markerRole,
        );

        batch.set(_collection.doc(record.id), record.toMap());
      }

      await batch.commit();
    }

    final first = AppConfig.dateId(sorted.first);
    final last = AppConfig.dateId(sorted.last);
    final label = ManualAttendanceStatus.label(status).toLowerCase();

    await NotificationService.instance.createNotification(
      studentUid: uid,
      title: 'Attendance updated for ${sorted.length} days',
      body: sorted.length == 1
          ? 'You were marked $label for $first by $markerName.'
          : 'You were marked $label for ${sorted.length} days between '
              '$first and $last by $markerName.'
              '${reason.isEmpty ? '' : '\nReason: $reason'}',
      category: 'attendance',
      priority: 'high',
      action: 'manual_attendance',
      data: {'from': first, 'to': last, 'status': status},
    );

    return sorted.length;
  }

  /// Removes a manual mark, handing the day back to the Pi's own verdict.
  Future<void> clear({
    required String uid,
    required DateTime date,
    required String markerName,
  }) async {
    final dateId = AppConfig.dateId(date);

    await _collection.doc(ManualAttendance.buildId(uid, dateId)).delete();

    await NotificationService.instance.createNotification(
      studentUid: uid,
      title: 'Attendance Correction Removed',
      body: 'The manual attendance mark for $dateId was removed by '
          '$markerName. Your check-in record for that day applies again.',
      category: 'attendance',
      priority: 'normal',
      action: 'manual_attendance_cleared',
      data: {'date': dateId},
    );
  }
}
