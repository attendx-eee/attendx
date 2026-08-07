import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/app_config.dart';
import '../models/holiday_model.dart';

/// The department's non-working days.
///
/// Cached in memory after the first read. Attendance calculation asks
/// "is this a college day" once per student per day — over a month, for
/// a class of sixty, that's thousands of questions about the same
/// handful of dates.
class HolidayService {
  HolidayService._();

  static final HolidayService instance = HolidayService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String collectionName = 'holidays';

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(collectionName);

  Map<String, Holiday>? _cache;

  /// Every stored holiday, by date id. Loaded once, then reused.
  Future<Map<String, Holiday>> all({bool refresh = false}) async {
    if (_cache != null && !refresh) return _cache!;

    try {
      final snap = await _collection.get();
      _cache = {
        for (final doc in snap.docs) doc.id: Holiday.fromMap(doc.id, doc.data()),
      };
    } catch (e) {
      debugPrint('Holiday load failed: $e');
      // An empty map, not a thrown error: a failure to read the holiday
      // list should degrade to "no holidays", not take attendance down
      // with it.
      _cache = {};
    }

    return _cache!;
  }

  Stream<List<Holiday>> watch() {
    return _collection.snapshots().map((snap) {
      final list =
          snap.docs.map((d) => Holiday.fromMap(d.id, d.data())).toList();
      list.sort((a, b) => a.date.compareTo(b.date));
      // Keep the cache warm from the same stream the admin screen uses,
      // so an edit is reflected in attendance without a restart.
      _cache = {for (final h in list) h.date: h};
      return list;
    });
  }

  /// Why [date] is closed, or null if it's a working day.
  ///
  /// Answers for weekly closures without touching Firestore — Sunday and
  /// second Saturday are rules, and most queries are about ordinary days.
  String? closureReason(DateTime date, {int? year}) {
    final weekly = HolidayCalendar.weeklyClosureReason(date);
    if (weekly != null) return weekly;

    final holiday = _cache?[AppConfig.dateId(date)];
    if (holiday == null) return null;
    if (year != null && !holiday.appliesTo(year)) return null;

    return holiday.reason.isEmpty ? holiday.name : holiday.name;
  }

  bool isWorkingDay(DateTime date, {int? year}) =>
      closureReason(date, year: year) == null;

  Future<void> save(Holiday holiday) async {
    await _collection.doc(holiday.date).set(holiday.toMap());
    _cache?[holiday.date] = holiday;
  }

  Future<void> delete(String date) async {
    await _collection.doc(date).delete();
    _cache?.remove(date);
  }

  /// Writes the seed list, skipping dates that already exist so an
  /// admin's corrections are never overwritten by a re-seed.
  ///
  /// Returns how many were added.
  Future<int> seedDefaults() async {
    final existing = await all(refresh: true);
    final toAdd =
        SeedHolidays.all.where((h) => !existing.containsKey(h.date)).toList();

    if (toAdd.isEmpty) return 0;

    final batch = _firestore.batch();
    for (final h in toAdd) {
      batch.set(_collection.doc(h.date), h.toMap());
    }
    await batch.commit();

    await all(refresh: true);
    return toAdd.length;
  }

  /// Drops the cache — call after bulk edits made elsewhere.
  void invalidate() => _cache = null;
}
