import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/constants/app_config.dart';
import '../../core/auth/account_lookup.dart';
import '../models/notification_model.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection("notifications");

  /// Live notification stream.
  ///
  /// Deliberately queries by studentUid ONLY (no orderBy) so no composite
  /// index is required — sorting happens client-side. This is what caused
  /// the "Unable to load notifications" error before.
  Stream<List<AppNotification>> notifications() {
    if (_uid.isEmpty) {
      return Stream.value(const <AppNotification>[]);
    }

    return _collection
        .where("studentUid", isEqualTo: _uid)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => AppNotification.fromFirestore(doc))
          .toList();

      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Unread count
  Stream<int> unreadCount() {
    if (_uid.isEmpty) {
      return Stream.value(0);
    }

    return _collection
        .where("studentUid", isEqualTo: _uid)
        .where("read", isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Mark notification as read
  Future<void> markAsRead(String id) async {
    if (_uid.isEmpty) return;

    await _collection.doc(id).update({
      "read": true,
    });
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    if (_uid.isEmpty) return;

    final snapshot = await _collection
        .where("studentUid", isEqualTo: _uid)
        .where("read", isEqualTo: false)
        .get();

    final batch = _firestore.batch();

    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {
        "read": true,
      });
    }

    await batch.commit();
  }

  /// Delete one notification
  Future<void> deleteNotification(String id) async {
    if (_uid.isEmpty) return;

    await _collection.doc(id).delete();
  }

  /// Delete all notifications
  Future<void> deleteAll() async {
    if (_uid.isEmpty) return;

    final snapshot = await _collection
        .where("studentUid", isEqualTo: _uid)
        .get();

    final batch = _firestore.batch();

    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }

  /// Create notification
  /// (Later used by Admin Panel and Raspberry Pi integrations)
  Future<void> createNotification({
    required String studentUid,
    required String title,
    required String body,
    required String category,
    required String priority,
    String? action,
    Map<String, dynamic>? data,
  }) async {
    await _collection.add({
      "studentUid": studentUid,
      "title": title,
      "body": body,
      "category": category,
      "priority": priority,
      "read": false,
      // Claimed by the push worker, which sweeps for `pushed == false`
      // once a minute and sends the device notification. Written by
      // every producer so nothing is silently undeliverable; Firestore
      // cannot query for a *missing* field, so the flag has to be
      // present from the start.
      "pushed": false,
      "createdAt": FieldValue.serverTimestamp(),
      "action": action,
      "data": data,
    });
  }

  /// Fan-out a notification to every student of a department + year.
  ///
  /// Used by CR timetable changes so the update instantly reaches all
  /// students of that year (their apps listen to this collection live).
  Future<int> broadcastToYear({
    required String department,
    required int year,
    required String title,
    required String body,
    required String category,
    String priority = "high",
    String? action,
    Map<String, dynamic>? data,
  }) async {
    // Fetch all students and match department AFTER normalization, so
    // legacy docs ("Electrical Engineering") and new docs ("EEE") both
    // receive the broadcast.
    final students = await _firestore.collection("students").get();

    final targetDept = AppConfig.normalizeDepartment(department);

    final targets = students.docs.where((doc) {
      final data = doc.data();
      if (!AccountLookup.isStudentDoc(data)) return false;
      return AppConfig.departmentOf(data) == targetDept &&
          AppConfig.yearOf(data) == year;
    }).toList();

    if (targets.isEmpty) return 0;

    // Firestore batches max out at 500 writes.
    const chunkSize = 400;

    for (var i = 0; i < targets.length; i += chunkSize) {
      final batch = _firestore.batch();

      for (final doc in targets.skip(i).take(chunkSize)) {
        batch.set(_collection.doc(), {
          "studentUid": doc.id,
          "title": title,
          "body": body,
          "category": category,
          "priority": priority,
          "read": false,
          "pushed": false,
          "createdAt": FieldValue.serverTimestamp(),
          "action": action,
          "data": data,
        });
      }

      await batch.commit();
    }

    return targets.length;
  }
}
