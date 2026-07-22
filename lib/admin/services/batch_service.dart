import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_config.dart';
import 'master_data_exceptions.dart';

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

  // Mirrors MasterDataService's weekday list — kept here too since batch
  // config lives in its own service, separate from timetables/master data.
  static const List<String> _weekdays = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
  ];

  /// True if [batchLetter] has at least one lab period assigned to it,
  /// anywhere in [year]'s timetable.
  Future<bool> isBatchLetterScheduled({
    required String department,
    required int year,
    required String batchLetter,
  }) async {
    for (final day in _weekdays) {
      final col = _firestore
          .collection('timetables')
          .doc(department)
          .collection(AppConfig.academicYear)
          .doc(year.toString())
          .collection(day);

      final snap = await col
          .where('batch', isEqualTo: batchLetter)
          .where('classType', isEqualTo: 'Lab')
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return true;
    }
    return false;
  }

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

  /// Reducing the count is the "delete" for the batch letters being
  /// dropped (e.g. count 3 -> 2 drops Batch C). If any dropped letter
  /// still has lab periods assigned in [year]'s timetable, this throws
  /// [MasterDataInUseException] instead of writing, so those lab
  /// assignments never silently end up pointing at a batch that no
  /// longer exists.
  Future<void> setBatchCount({
    required String department,
    required int year,
    required int count,
  }) async {
    final clamped = count.clamp(1, _letters.length);
    final current = await batchCount(department: department, year: year);

    if (clamped < current) {
      final droppedLetters = _letters.sublist(clamped, current);
      for (final letter in droppedLetters) {
        final inUse = await isBatchLetterScheduled(
          department: department,
          year: year,
          batchLetter: letter,
        );
        if (inUse) {
          throw MasterDataInUseException(
            'Batch $letter has lab periods scheduled in Year $year. Remove '
            'or reassign those lab periods first, then reduce the batch '
            'count.',
          );
        }
      }
    }

    await _doc(department, year).set({
      'department': department,
      'year': year,
      'batchCount': clamped,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Convenience for the default department.
  Future<int> batchCountForYear(int year) =>
      batchCount(department: AppConfig.department, year: year);
}
