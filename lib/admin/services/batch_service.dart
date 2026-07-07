import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_config.dart';

/// Lab batch configuration per year.
///
/// Firestore: `batch_config/{department}_{year}` -> { batchCount: 2 }
/// A count of 2 means batches A and B; labs in the timetable can then be
/// assigned to a specific batch (or to the whole class).
class BatchService {
  BatchService._();

  static final BatchService instance = BatchService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String collectionName = 'batch_config';

  static const List<String> _letters = ['A', 'B', 'C', 'D', 'E', 'F'];

  DocumentReference<Map<String, dynamic>> _doc(String department, int year) =>
      _firestore
          .collection(collectionName)
          .doc('${department}_$year');

  /// Batch labels for a count: 2 -> [A, B].
  static List<String> labels(int count) =>
      _letters.take(count.clamp(1, _letters.length)).toList();

  Future<int> batchCount({
    required String department,
    required int year,
  }) async {
    try {
      final snapshot = await _doc(department, year).get();
      return ((snapshot.data()?['batchCount'] ?? 1) as num).toInt();
    } catch (_) {
      return 1;
    }
  }

  Stream<int> watchBatchCount({
    required String department,
    required int year,
  }) {
    return _doc(department, year).snapshots().map(
        (snapshot) => ((snapshot.data()?['batchCount'] ?? 1) as num).toInt());
  }

  Future<void> setBatchCount({
    required String department,
    required int year,
    required int count,
  }) async {
    await _doc(department, year).set({
      'department': department,
      'year': year,
      'batchCount': count.clamp(1, _letters.length),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Convenience for the default department.
  Future<int> batchCountForYear(int year) =>
      batchCount(department: AppConfig.department, year: year);
}
