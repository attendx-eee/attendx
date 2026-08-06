import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../notifications/services/notification_service.dart';
import '../models/attendance_permission_model.dart';

/// Manages a CR's month-scoped permission to mark attendance.
class AttendancePermissionService {
  AttendancePermissionService._();

  static final AttendancePermissionService instance =
      AttendancePermissionService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String collectionName = 'cr_attendance_permissions';

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(collectionName);

  /// Every request raised by one CR, newest month first. Single-field
  /// query with client-side sorting — no composite index required.
  Stream<List<AttendancePermission>> watchForCr(String crUid) {
    return _collection
        .where('crUid', isEqualTo: crUid)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => AttendancePermission.fromFirestore(doc))
          .toList();
      list.sort((a, b) => b.month.compareTo(a.month));
      return list;
    });
  }

  /// Requests waiting on an admin decision.
  Stream<List<AttendancePermission>> watchPending() {
    return _collection
        .where('status', isEqualTo: PermissionStatus.pending)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => AttendancePermission.fromFirestore(doc))
          .toList();
      list.sort((a, b) => a.month.compareTo(b.month));
      return list;
    });
  }

  /// Grants that are currently live, newest month first — the admin's
  /// audit list, and where access gets revoked from.
  Stream<List<AttendancePermission>> watchApproved() {
    return _collection
        .where('status', isEqualTo: PermissionStatus.approved)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => AttendancePermission.fromFirestore(doc))
          .toList();
      list.sort((a, b) => b.month.compareTo(a.month));
      return list;
    });
  }

  /// Live count for the badge on the admin's Approvals tile.
  Stream<int> pendingCount() => _collection
      .where('status', isEqualTo: PermissionStatus.pending)
      .snapshots()
      .map((snapshot) => snapshot.docs.length);

  /// The CR's grant for one month, or null if they never asked.
  Stream<AttendancePermission?> watchGrant({
    required String crUid,
    required String month,
  }) {
    return _collection
        .doc(AttendancePermission.buildId(crUid, month))
        .snapshots()
        .map((doc) =>
            doc.exists ? AttendancePermission.fromFirestore(doc) : null);
  }

  /// One-shot check used before opening a marking screen.
  Future<bool> isApprovedFor({
    required String crUid,
    required String month,
  }) async {
    final doc = await _collection
        .doc(AttendancePermission.buildId(crUid, month))
        .get();
    if (!doc.exists) return false;
    return AttendancePermission.fromFirestore(doc).isApproved;
  }

  /// Raises (or re-raises) a request for [month].
  ///
  /// Re-requesting overwrites a previous rejection so a CR can ask again
  /// with a better explanation, but an already-approved month is left
  /// alone — nothing to gain from resetting a live grant to pending.
  Future<void> request({
    required String crUid,
    required String crName,
    required String department,
    required int year,
    required String month,
    String note = '',
  }) async {
    final id = AttendancePermission.buildId(crUid, month);
    final existing = await _collection.doc(id).get();

    if (existing.exists &&
        AttendancePermission.fromFirestore(existing).isApproved) {
      return;
    }

    final permission = AttendancePermission(
      id: id,
      crUid: crUid,
      crName: crName,
      department: department,
      year: year,
      month: month,
      status: PermissionStatus.pending,
      requestNote: note,
    );

    await _collection.doc(id).set(permission.toMap());
  }

  /// Admin decision on a request. Also notifies the CR.
  Future<void> decide({
    required AttendancePermission permission,
    required bool approve,
    String note = '',
  }) async {
    await _collection.doc(permission.id).update({
      'status':
          approve ? PermissionStatus.approved : PermissionStatus.rejected,
      'decisionNote': note,
      'decidedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      'decidedAt': FieldValue.serverTimestamp(),
    });

    await NotificationService.instance.createNotification(
      studentUid: permission.crUid,
      title: approve
          ? 'Attendance Access Granted'
          : 'Attendance Access Declined',
      body: approve
          ? 'You can now mark attendance for Year ${permission.year} students '
              'for ${permission.monthName}. Open Students from your dashboard.'
          : 'Your request to mark attendance for ${permission.monthName} was '
              'not approved.${note.isEmpty ? '' : '\n$note'}',
      category: 'role',
      priority: 'high',
      action: 'attendance_permission',
      data: {'month': permission.month, 'approved': approve},
    );
  }

  /// Withdraws a live grant early — the escape hatch if a CR's access
  /// turns out to be a mistake before the month runs out.
  Future<void> revoke({
    required AttendancePermission permission,
    String note = '',
  }) async {
    await _collection.doc(permission.id).update({
      'status': PermissionStatus.revoked,
      'decisionNote': note,
      'decidedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      'decidedAt': FieldValue.serverTimestamp(),
    });

    await NotificationService.instance.createNotification(
      studentUid: permission.crUid,
      title: 'Attendance Access Revoked',
      body: 'Your permission to mark attendance for ${permission.monthName} '
          'has been withdrawn.${note.isEmpty ? '' : '\n$note'}',
      category: 'role',
      priority: 'high',
      action: 'attendance_permission',
      data: {'month': permission.month, 'approved': false},
    );
  }
}
