import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_config.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_spacing.dart';
import '../../attendance/services/manual_attendance_service.dart';
import '../../services/attendance_service.dart';
import '../../services/firestore_service.dart';

import '../dashboard/widgets/attendance_overview_card.dart';
import 'widgets/attendance_summary_card.dart';
import 'widgets/attendance_calendar_card.dart';
import 'widgets/subject_attendance_card.dart';
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

  // Current month
  Map<int, String> _calendarStatuses = {};
  String _monthLabel = '';

  List<SubjectAttendance> _subjects = [];
  List<AttendanceHistory> _history = [];

  // Semester monthly overview (moved here from the dashboard).
  final PageController _pageController = PageController(initialPage: 0);
  int _selectedMonthIndex = 0;
  final List<String> _semesterMonths = [
    "July",
    "August",
    "September",
    "October",
    "November",
    "December"
  ];
  Map<String, Map<String, int>> _semesterAttendance = {
    for (final m in [
      "July", "August", "September", "October", "November", "December"
    ])
      m: {"present": 0, "absent": 0, "total": 0, "late": 0},
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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

      // Corrections an admin (or an approved CR) made by hand. Without
      // these the student would still see "absent" on a day staff had
      // already fixed for them, and would rightly not trust the screen.
      final manual = await ManualAttendanceService.instance.forStudent(uid);

      // Semester-wide monthly breakdown (independent query — a failure
      // here shouldn't block the rest of the screen).
      var semesterAttendance = _semesterAttendance;
      try {
        semesterAttendance = await _service.semesterStats(
          uid: uid,
          studentData: student,
          months: _semesterMonths,
        );
      } catch (e) {
        debugPrint('Semester attendance load failed: $e');
      }

      final today = DateTime.now();
      final todayId = AppConfig.dateId(today);
      final start = _service.semesterStart();

      // Per-subject tallies: subject -> [attended, total]
      final subjectTotals = <String, List<int>>{};

      int presentDays = 0, absentDays = 0, totalDays = 0;
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

        final dateId = AppConfig.dateId(date);
        final manualMark = manual[dateId];

        // Normally an empty timetable means "not a college day", but a
        // manual mark says someone deliberately recorded this day, so it
        // still counts.
        if (periods.isEmpty && manualMark == null) continue;

        final event = events[dateId];
        final checkIn =
            event?['checkIn'] is Timestamp ? event!['checkIn'] as Timestamp : null;
        final checkOut =
            event?['checkOut'] is Timestamp ? event!['checkOut'] as Timestamp : null;

        final verdict = _service.classifyDay(
          date: date,
          periods: periods,
          checkIn: checkIn,
          manual: manualMark,
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

        // Current month calendar colouring.
        if (isCurrentMonth) {
          if (isToday) {
            calendar[date.day] = 'today';
          } else if (verdict.present) {
            calendar[date.day] = verdict.late ? 'late' : 'present';
          } else if (event != null) {
            // Only mark the calendar red when a check-in event exists
            // but didn't qualify. Days with no check-in at all stay
            // blank on the calendar (stats still count them).
            calendar[date.day] = 'absent';
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
                date: cursor,
                periods: periods,
                checkIn: ci,
                manual: manual[AppConfig.dateId(cursor)]);

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

        _calendarStatuses = calendar;
        _monthLabel = DateFormat('MMMM yyyy').format(today);

        _subjects = subjects;
        _history = history;
        _semesterAttendance = semesterAttendance;
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
                          AttendanceOverviewCard(
                            months: _semesterMonths,
                            selectedIndex: _selectedMonthIndex,
                            pageController: _pageController,
                            attendance: _semesterAttendance,
                            onMonthChanged: (index) {
                              setState(() {
                                _selectedMonthIndex = index;
                              });
                            },
                          ),
                          // Today's check-in / check-out status lives on
                          // the dashboard, which is the screen a student
                          // opens to answer "am I marked in yet". Having
                          // it here too meant the same two timestamps in
                          // two places; this page is about the semester.
                          SizedBox(height: Responsive.h(20)),
                          AttendanceCalendarCard(
                            year: today.year,
                            month: today.month,
                            monthLabel: _monthLabel,
                            dayStatuses: _calendarStatuses,
                          ),
                          SizedBox(height: Responsive.h(20)),
                          SubjectAttendanceCard(subjects: _subjects),
                          // The monthly present / absent / late tiles
                          // that used to sit here duplicated the month
                          // pager near the top of this same page, which
                          // already shows those figures for whichever
                          // month is selected — and does it for every
                          // month, not just the current one.
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
