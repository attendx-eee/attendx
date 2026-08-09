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

  /// True when the cache is the built-in list rather than Firestore's,
  /// i.e. nobody has ever seeded the collection.
  bool _usingDefaults = false;

  bool get usingDefaults => _usingDefaults;

  /// Every stored holiday, by date id. Loaded once, then reused.
  ///
  /// An empty collection falls back to the built-in calendar rather than
  /// to "no holidays". Requiring an admin to press a seed button before
  /// the calendar knows about Independence Day meant every unseeded
  /// install marked the whole department absent for it — a silent wrong
  /// answer, which is worse than a missing one. The fallback lives only
  /// in memory; the moment an admin saves or seeds anything, Firestore
  /// takes over.
  Future<Map<String, Holiday>> all({bool refresh = false}) async {
    if (_cache != null && !refresh) return _cache!;

    try {
      final snap = await _collection.get();

      if (snap.docs.isEmpty) {
        _usingDefaults = true;
        _cache = {for (final h in SeedHolidays.all) h.date: h};
      } else {
        _usingDefaults = false;
        _cache = {
          for (final doc in snap.docs)
            doc.id: Holiday.fromMap(doc.id, doc.data()),
        };
      }
    } catch (e) {
      debugPrint('Holiday load failed: $e');
      // A read failure degrades to the built-in list too. Attendance
      // shouldn't collapse because the network blinked, and the built-in
      // dates are right far more often than an empty list is.
      _usingDefaults = true;
      _cache = {for (final h in SeedHolidays.all) h.date: h};
    }

    return _cache!;
  }

  Stream<List<Holiday>> watch() {
    return _collection.snapshots().map((snap) {
      final list = snap.docs.isEmpty
          ? [...SeedHolidays.all]
          : snap.docs.map((d) => Holiday.fromMap(d.id, d.data())).toList();
      _usingDefaults = snap.docs.isEmpty;
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
    // Saving into an unseeded collection would leave Firestore holding
    // exactly one holiday while the cache still shows the built-in list —
    // and the next cold start would lose every other date. Write the
    // defaults down first so what's stored matches what's shown.
    if (_usingDefaults) await seedDefaults();

    await _collection.doc(holiday.date).set(holiday.toMap());
    _cache?[holiday.date] = holiday;
    _usingDefaults = false;
  }

  Future<void> delete(String date) async {
    if (_usingDefaults) await seedDefaults();

    await _collection.doc(date).delete();
    _cache?.remove(date);
    _usingDefaults = false;
  }

  /// The stored holiday on [date], if there is one. Weekly closures
  /// (Sunday, second Saturday) are rules rather than records and so
  /// aren't returned here — there's nothing to delete.
  Holiday? on(DateTime date) => _cache?[AppConfig.dateId(date)];

  /// Writes the seed list, skipping dates that already exist so an
  /// admin's corrections are never overwritten by a re-seed.
  ///
  /// Returns how many were added.
  Future<int> seedDefaults() async {
    // Reads Firestore directly rather than through `all()`, which would
    // hand back the built-in list and make every date look like it
    // already exists.
    final snap = await _collection.get();
    final existing = {for (final d in snap.docs) d.id};

    final toAdd =
        SeedHolidays.all.where((h) => !existing.contains(h.date)).toList();

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
