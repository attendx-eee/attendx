import 'package:cloud_firestore/cloud_firestore.dart';

import '../../notifications/services/notification_service.dart';
import '../models/timetable_override_model.dart';

/// Manages temporary, date-specific timetable changes made by CRs and
/// broadcasts each change as a realtime notification to every student
/// of the affected year.
class TimetableOverrideService {
  TimetableOverrideService._();

  static final TimetableOverrideService instance = TimetableOverrideService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection("timetable_overrides");

  /// Live overrides for one class-day (department + year + date).
  Stream<List<TimetableOverride>> watchForDate({
    required String department,
    required String academicYear,
    required int year,
    required String date,
  }) {
    return _collection
        .where("department", isEqualTo: department)
        .where("academicYear", isEqualTo: academicYear)
        .where("year", isEqualTo: year)
        .where("date", isEqualTo: date)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => TimetableOverride.fromFirestore(doc))
              .toList(),
        );
  }

  /// Applies (creates or replaces) an override and notifies the year.
  Future<void> applyOverride(TimetableOverride override) async {
    final id = TimetableOverride.buildId(
      department: override.department,
      academicYear: override.academicYear,
      year: override.year,
      date: override.date,
      periodNo: override.periodNo,
    );

    await _collection.doc(id).set(override.toMap());

    await NotificationService.instance.broadcastToYear(
      department: override.department,
      year: override.year,
      title: override.notificationTitle(),
      body: override.notificationBody(),
      category: "timetable",
      priority: "high",
      action: "timetable_override",
      data: {
        "overrideId": id,
        "type": override.type,
        "date": override.date,
        "periodNo": override.periodNo,
      },
    );
  }

  /// Reverts an override back to the regular timetable and notifies the year.
  Future<void> revertOverride(TimetableOverride override) async {
    await _collection.doc(override.id).delete();

    await NotificationService.instance.broadcastToYear(
      department: override.department,
      year: override.year,
      title: "Update Reverted: ${override.originalSubject}",
      body:
          "${override.originalSubject} (${override.startTime} - ${override.endTime} on ${override.date}) "
          "will run as per the regular timetable.",
      category: "timetable",
      priority: "normal",
      action: "timetable_override_reverted",
      data: {
        "date": override.date,
        "periodNo": override.periodNo,
      },
    );
  }
}
