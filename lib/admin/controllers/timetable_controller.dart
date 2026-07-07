import 'package:flutter/foundation.dart';

import '../models/period_model.dart';
import '../services/timetable_service.dart';

class TimetableController extends ChangeNotifier {
  final TimetableService _service = TimetableService.instance;

  // -----------------------------
  // State
  // -----------------------------

  bool loading = false;

  bool saving = false;

  String selectedDay = "Monday";

  String timetableStatus = "draft";

  List<PeriodModel> periods = [];

  String? error;

  // -----------------------------
  // Current Timetable Identity
  // -----------------------------

  late String department;

  late String academicYear;

  late int year;

  late String semester;

  late String section;

  // -----------------------------
  // Initialize Controller
  // -----------------------------

  Future<void> initialize({
    required String department,
    required String academicYear,
    required int year,
    required String semester,
    required String section,
  }) async {
    this.department = department;
    this.academicYear = academicYear;
    this.year = year;
    this.semester = semester;

    await loadDay(selectedDay);
  }

  // -----------------------------
  // Load Selected Day
  // -----------------------------

  Future<void> loadDay(String day) async {
    loading = true;
    error = null;
    notifyListeners();

    selectedDay = day;

    try {
      periods = await _service.getDaySchedule(
        department: department,
        academicYear: academicYear,
        year: year,
        day: day,
      );

      timetableStatus = await _service.getTimetableStatus(
        department: department,
        academicYear: academicYear,
        year: year,
      );
      
    } catch (e) {
      error = e.toString();
    }

    loading = false;
    notifyListeners();
  }

  // -----------------------------
  // Refresh Current Day
  // -----------------------------

  Future<void> refresh() async {
    await loadDay(selectedDay);
  }

  // -----------------------------
  // Change Day
  // -----------------------------

  Future<void> changeDay(String day) async {
    if (day == selectedDay) return;

    await loadDay(day);
  }

  // -----------------------------
  // Save One Period
  // -----------------------------

  Future<void> savePeriod(PeriodModel period) async {
    saving = true;
    notifyListeners();

    try {
      await _service.updatePeriod(
        department: department,
        academicYear: academicYear,
        year: year,
        day: selectedDay,
        period: period,
      );

      final index =
          periods.indexWhere((e) => e.periodNo == period.periodNo);

      if (index != -1) {
        periods[index] = period;
      } else {
        periods.add(period);
      }

      periods.sort((a, b) => a.periodNo.compareTo(b.periodNo));
    } catch (e) {
      error = e.toString();
    }

    saving = false;
    notifyListeners();
  }

  // -----------------------------
  // Delete Period
  // -----------------------------

  Future<void> deletePeriod(int periodNo) async {
    saving = true;
    notifyListeners();

    try {
      await _service.deletePeriod(
        department: department,
        academicYear: academicYear,
        year: year,
        day: selectedDay,
        periodNo: periodNo,
      );

      periods.removeWhere((e) => e.periodNo == periodNo);
    } catch (e) {
      error = e.toString();
    }

    saving = false;
    notifyListeners();
  }

  // -----------------------------
  // Submit
  // -----------------------------

  Future<void> submitForApproval() async {
    await _service.submitForApproval(
      department: department,
      academicYear: academicYear,
      year: year,
    );

    timetableStatus = "pending";

    notifyListeners();
  }

  // -----------------------------
  // Approve
  // -----------------------------

  Future<void> approve() async {
    await _service.approve(
      department: department,
      academicYear: academicYear,
      year: year,
    );

    timetableStatus = "approved";

    notifyListeners();
  }

  // -----------------------------
  // Reject
  // -----------------------------

  Future<void> reject(String reason) async {
    await _service.reject(
      department: department,
      academicYear: academicYear,
      year: year,
      reason: reason,
    );

    timetableStatus = "rejected";

    notifyListeners();
  }
  

  // -----------------------------
  // Create Blank Timetable
  // -----------------------------

  Future<void> createBlankWeek() async {
    await _service.createBlankWeek(
      department: department,
      academicYear: academicYear,
      year: year,
    );

    await refresh();
  }

  // -----------------------------
  // Check Empty
  // -----------------------------

  bool get isEmpty => periods.isEmpty;

  bool get hasError => error != null;

  dynamic get timetable => null;

  void load({required String year, required String semester, required String section}) {}
}