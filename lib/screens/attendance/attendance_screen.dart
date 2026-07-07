import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_config.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_spacing.dart';
import '../../services/attendance_service.dart';
import '../../services/firestore_service.dart';

import 'widgets/attendance_summary_card.dart';
import 'widgets/today_status_card.dart';
import 'widgets/attendance_calendar_card.dart';
import 'widgets/subject_attendance_card.dart';
import 'widgets/monthly_statistics_card.dart';
import 'widgets/attendance_history_card.dart';

/// Attendance overview computed entirely from Raspberry Pi check-in
/// events (`attendance_events`) laid over the timetable — no hardcoded
/// data anywhere.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final AttendanceService _service = AttendanceService.instance;

  bool _loading = true;

  // Overall (semester to date)
  int _presentDays = 0;
  int _absentDays = 0;
  int _totalDays = 0;

  // Today
  bool _checkedIn = false;
  bool _checkedOut = false;
  String _checkInTime = "--";
  String _checkOutTime = "--";
  int _attendedToday = 0;
  int _totalToday = 0;

  // Current month
  int _monthPresent = 0;
  int _monthAbsent = 0;
  int _monthLate = 0;
  Map<int, String> _calendarStatuses = {};
  String _monthLabel = '';

  List<SubjectAttendance> _subjects = [];
  List<AttendanceHistory> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmtTime(DateTime d) {
    final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:${d.minute.toString().padLeft(2, '0')} $ap';
  }

  Future<void> _load() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('No user');

      final studentDoc = await FirestoreService().getStudent(uid);
      final student = studentDoc.data() ?? <String, dynamic>{};
      final department = AppConfig.departmentOf(student);
      final year = AppConfig.yearOf(student);

      final events = await _service.eventsFor(uid);

      final today = DateTime.now();
      final todayId = AppConfig.dateId(today);
      final start = _service.semesterStart();

      // Per-subject tallies: subject -> [attended, total]
      final subjectTotals = <String, List<int>>{};

      int presentDays = 0, absentDays = 0, totalDays = 0;
      int monthPresent = 0, monthAbsent = 0, monthLate = 0;
      final calendar = <int, String>{};

      for (var date = start;
          !date.isAfter(today);
          date = date.add(const Duration(days: 1))) {
        final weekday = AppConfig.dayName(date);
        if (weekday == 'Sunday') continue;

        final periods = await _service.scheduledPeriods(
          department: department,
          year: year,
          weekday: weekday,
        );
        if (periods.isEmpty) continue;

        final event = events[AppConfig.dateId(date)];
        final checkIn =
            event?['checkIn'] is Timestamp ? event!['checkIn'] as Timestamp : null;
        final checkOut =
            event?['checkOut'] is Timestamp ? event!['checkOut'] as Timestamp : null;

        final verdict = _service.classifyDay(
          date: date,
          periods: periods,
          checkIn: checkIn,
        );
        if (verdict == null) continue;

        final isToday = AppConfig.dateId(date) == todayId;
        final isCurrentMonth =
            date.month == today.month && date.year == today.year;

        // Overall day counts (today counts once it has an outcome).
        totalDays++;
        if (verdict.present) {
          presentDays++;
        } else if (!isToday) {
          absentDays++;
        } else {
          totalDays--; // today, not checked in yet — don't judge it
        }

        // Current month + calendar.
        if (isCurrentMonth) {
          if (isToday) {
            calendar[date.day] = 'today';
            if (verdict.present) {
              monthPresent++;
              if (verdict.late) monthLate++;
            }
          } else if (verdict.present) {
            monthPresent++;
            calendar[date.day] = verdict.late ? 'late' : 'present';
            if (verdict.late) monthLate++;
          } else {
            monthAbsent++;
            // Only mark the calendar red when a check-in event exists
            // but didn't qualify. Days with no check-in at all stay
            // blank on the calendar (stats still count them).
            if (event != null) calendar[date.day] = 'absent';
          }
        }

        // Per-subject attendance (period-level overlap with the
        // student's check-in/check-out interval).
        for (final period in periods) {
          final tally = subjectTotals.putIfAbsent(period.subject, () => [0, 0]);
          if (isToday) {
            final end = AppConfig.timeOn(date, period.endTime);
            if (end == null || end.isAfter(DateTime.now())) {
              continue; // period hasn't finished yet — don't count it
            }
          }
          tally[1]++;
          if (_service.periodAttended(
            date: date,
            period: period,
            checkIn: checkIn,
            checkOut: checkOut,
          )) {
            tally[0]++;
          }
        }
      }

      // Today's card.
      final todayEvent = events[todayId];
      final todayCheckIn = todayEvent?['checkIn'] is Timestamp
          ? todayEvent!['checkIn'] as Timestamp
          : null;
      final todayCheckOut = todayEvent?['checkOut'] is Timestamp
          ? todayEvent!['checkOut'] as Timestamp
          : null;

      final todayPeriods = await _service.scheduledPeriods(
        department: department,
        year: year,
        weekday: AppConfig.dayName(today),
      );

      var attendedToday = 0;
      for (final period in todayPeriods) {
        if (_service.periodAttended(
          date: today,
          period: period,
          checkIn: todayCheckIn,
          checkOut: todayCheckOut,
        )) {
          attendedToday++;
        }
      }

      // Subjects list, sorted worst-first so problems surface.
      final subjects = subjectTotals.entries
          .where((e) => e.value[1] > 0)
          .map((e) {
        final pct = (e.value[0] * 100 / e.value[1]).round();
        final color = pct >= 90
            ? Colors.green
            : pct >= 80
                ? Colors.blue
                : pct >= 75
                    ? Colors.orange
                    : Colors.red;
        return SubjectAttendance(e.key, '', pct, color);
      }).toList()
        ..sort((a, b) => a.percentage.compareTo(b.percentage));

      // History: last 7 college days, newest first.
      final history = <AttendanceHistory>[];
      var cursor = DateTime(today.year, today.month, today.day);
      while (history.length < 7 && !cursor.isBefore(start)) {
        final weekday = AppConfig.dayName(cursor);
        if (weekday != 'Sunday') {
          final periods = await _service.scheduledPeriods(
            department: department,
            year: year,
            weekday: weekday,
          );
          if (periods.isNotEmpty) {
            final event = events[AppConfig.dateId(cursor)];
            final ci = event?['checkIn'] is Timestamp
                ? event!['checkIn'] as Timestamp
                : null;
            final co = event?['checkOut'] is Timestamp
                ? event!['checkOut'] as Timestamp
                : null;

            final verdict = _service.classifyDay(
                date: cursor, periods: periods, checkIn: ci);

            final isToday = AppConfig.dateId(cursor) == todayId;
            String status;
            Color color;

            if (verdict?.present == true && isToday && co == null) {
              status = 'In Progress';
              color = Colors.orange;
            } else if (verdict?.present == true && verdict!.late) {
              status = 'Late';
              color = Colors.orange;
            } else if (verdict?.present == true) {
              status = 'Present';
              color = Colors.green;
            } else if (isToday) {
              status = 'Pending';
              color = Colors.grey;
            } else {
              status = 'Absent';
              color = Colors.red;
            }

            history.add(AttendanceHistory(
              DateFormat('dd MMM yyyy').format(cursor),
              ci == null ? '--' : _fmtTime(ci.toDate()),
              co == null ? '--' : _fmtTime(co.toDate()),
              status,
              color,
            ));
          }
        }
        cursor = cursor.subtract(const Duration(days: 1));
      }

      if (!mounted) return;
      setState(() {
        _presentDays = presentDays;
        _absentDays = absentDays;
        _totalDays = totalDays;

        _checkedIn = todayCheckIn != null;
        _checkedOut = todayCheckOut != null;
        _checkInTime =
            todayCheckIn == null ? '--' : _fmtTime(todayCheckIn.toDate());
        _checkOutTime =
            todayCheckOut == null ? '--' : _fmtTime(todayCheckOut.toDate());
        _attendedToday = attendedToday;
        _totalToday = todayPeriods.length;

        _monthPresent = monthPresent;
        _monthAbsent = monthAbsent;
        _monthLate = monthLate;
        _calendarStatuses = calendar;
        _monthLabel = DateFormat('MMMM yyyy').format(today);

        _subjects = subjects;
        _history = history;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Attendance screen load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final percentage =
        _totalDays == 0 ? 0.0 : (_presentDays * 100 / _totalDays);

    return Scaffold(
      backgroundColor: const Color(0xffF6F8FC),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    floating: false,
                    elevation: 0,
                    backgroundColor: Colors.white,
                    titleSpacing: Responsive.w(20),
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Attendance",
                          style: TextStyle(
                            fontSize: Responsive.sp(22),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: Responsive.h(2)),
                        Text(
                          "Track your academic presence",
                          style: TextStyle(
                            fontSize: Responsive.sp(12),
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      IconButton(
                        tooltip: 'Refresh',
                        icon: const Icon(Icons.refresh_rounded,
                            color: Colors.black54),
                        onPressed: () {
                          setState(() => _loading = true);
                          _load();
                        },
                      ),
                    ],
                  ),
                  SliverPadding(
                    padding: Responsive.all(AppSpacing.md),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate(
                        [
                          AttendanceSummaryCard(
                            attendancePercentage: percentage,
                            presentDays: _presentDays,
                            absentDays: _absentDays,
                            totalDays: _totalDays,
                          ),
                          SizedBox(height: Responsive.h(20)),
                          TodayStatusCard(
                            checkedIn: _checkedIn,
                            checkedOut: _checkedOut,
                            checkInTime: _checkInTime,
                            checkOutTime: _checkOutTime,
                            attendedClasses: _attendedToday,
                            totalClasses: _totalToday,
                          ),
                          SizedBox(height: Responsive.h(20)),
                          AttendanceCalendarCard(
                            year: today.year,
                            month: today.month,
                            monthLabel: _monthLabel,
                            dayStatuses: _calendarStatuses,
                          ),
                          SizedBox(height: Responsive.h(20)),
                          SubjectAttendanceCard(subjects: _subjects),
                          SizedBox(height: Responsive.h(20)),
                          MonthlyStatisticsCard(
                            present: _monthPresent,
                            absent: _monthAbsent,
                            late: _monthLate,
                            leave: 0,
                          ),
                          SizedBox(height: Responsive.h(20)),
                          AttendanceHistoryCard(entries: _history),
                          SizedBox(height: Responsive.h(30)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
