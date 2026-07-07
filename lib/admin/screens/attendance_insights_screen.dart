import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_config.dart';
import '../../services/attendance_service.dart';

/// Admin-only attendance insights fed by Raspberry Pi check-in events:
/// today's check-in/late/absent summary, a 7-day late-check-in count
/// graph, and the list of today's late students.
class AttendanceInsightsScreen extends StatefulWidget {
  const AttendanceInsightsScreen({super.key});

  @override
  State<AttendanceInsightsScreen> createState() =>
      _AttendanceInsightsScreenState();
}

class _LateStudent {
  final String name;
  final String regNo;
  final int year;
  final DateTime checkIn;
  final int lateByMinutes;

  const _LateStudent({
    required this.name,
    required this.regNo,
    required this.year,
    required this.checkIn,
    required this.lateByMinutes,
  });
}

class _DayInsight {
  final DateTime date;
  int checkIns = 0;
  int late = 0;

  _DayInsight(this.date);
}

class _AttendanceInsightsScreenState extends State<AttendanceInsightsScreen> {
  bool _loading = true;
  int _totalStudents = 0;
  List<_DayInsight> _week = [];
  List<_LateStudent> _lateToday = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // All students of the department, mapped by uid. Department is
      // matched after normalization so legacy long-name docs count too.
      final studentsSnap =
          await FirebaseFirestore.instance.collection('students').get();

      final students = {
        for (final doc in studentsSnap.docs)
          if (AppConfig.departmentOf(doc.data()) == AppConfig.department)
            doc.id: doc.data(),
      };
      _totalStudents = students.length;

      final today = DateTime.now();

      // Last 7 COLLEGE days — Sundays are skipped entirely.
      final days = <DateTime>[];
      var cursor = DateTime(today.year, today.month, today.day);
      while (days.length < 7) {
        if (cursor.weekday != DateTime.sunday) days.insert(0, cursor);
        cursor = cursor.subtract(const Duration(days: 1));
      }

      final week = <_DayInsight>[];
      final lateToday = <_LateStudent>[];

      for (final date in days) {
        final insight = _DayInsight(date);
        final weekday = AppConfig.dayName(date);

        final events =
            await AttendanceService.instance.eventsOn(AppConfig.dateId(date));

        for (final event in events) {
          final uid = (event['uid'] ?? '').toString();
          final student = students[uid];
          if (student == null) continue; // other department / unknown

          final checkIn = event['checkIn'];
          if (checkIn is! Timestamp) continue;

          final year = AppConfig.yearOf(student);
          final periods = await AttendanceService.instance.scheduledPeriods(
            department: AppConfig.department,
            year: year,
            weekday: weekday,
          );

          final verdict = AttendanceService.instance.classifyDay(
            date: date,
            periods: periods,
            checkIn: checkIn,
          );

          if (verdict == null || !verdict.present) continue;

          insight.checkIns++;
          if (verdict.late) {
            insight.late++;

            final isToday = AppConfig.dateId(date) == AppConfig.dateId(today);
            if (isToday) {
              lateToday.add(_LateStudent(
                name: (student['name'] ?? 'Unknown').toString(),
                regNo: (student['regNo'] ?? '--').toString(),
                year: year,
                checkIn: checkIn.toDate(),
                lateByMinutes: verdict.lateByMinutes,
              ));
            }
          }
        }

        week.add(insight);
      }

      lateToday.sort((a, b) => b.lateByMinutes.compareTo(a.lateByMinutes));

      if (mounted) {
        setState(() {
          _week = week;
          _lateToday = lateToday;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Insights load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtTime(DateTime d) {
    final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:${d.minute.toString().padLeft(2, '0')} $ap';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Only treat the last bar as "today" when today is a college day.
    final todayInsight = _week.isNotEmpty &&
            AppConfig.dateId(_week.last.date) ==
                AppConfig.dateId(DateTime.now())
        ? _week.last
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Attendance Insights"),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading
                ? null
                : () {
                    setState(() => _loading = true);
                    _load();
                  },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ------------------------------------- today summary
                Row(
                  children: [
                    _summaryCard(
                      theme,
                      label: "Checked In",
                      value: "${todayInsight?.checkIns ?? 0}",
                      sub: "of $_totalStudents students",
                      color: Colors.green,
                      icon: Icons.login_rounded,
                    ),
                    const SizedBox(width: 12),
                    _summaryCard(
                      theme,
                      label: "Late Today",
                      value: "${todayInsight?.late ?? 0}",
                      sub: "> ${AppConfig.onTimeGraceMinutes} min after start",
                      color: Colors.orange,
                      icon: Icons.schedule_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ------------------------------- 7-day late count graph
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Late check-ins — last 7 college days",
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          "Students arriving ${AppConfig.onTimeGraceMinutes}-${AppConfig.presentGraceMinutes}+ min after their first period",
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(height: 160, child: _buildBarChart(theme)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ---------------------------------- today's late list
                Text("Late students today",
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (_lateToday.isEmpty)
                  const Card(
                    elevation: 0,
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: Text("No late check-ins today")),
                    ),
                  )
                else
                  ..._lateToday.map(
                    (s) => Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.orange.shade100,
                          child: Text("Y${s.year}",
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange)),
                        ),
                        title: Text(s.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text("Reg ${s.regNo}"),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_fmtTime(s.checkIn),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            Text("+${s.lateByMinutes} min",
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.orange)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _summaryCard(
    ThemeData theme, {
    required String label,
    required String value,
    required String sub,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Card(
        elevation: 0,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 10),
              Text(value,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800, color: color)),
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(sub,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBarChart(ThemeData theme) {
    final maxLate = _week.fold<int>(1, (m, d) => d.late > m ? d.late : m);
    const weekdayShort = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: _week.map((day) {
        final ratio = day.late / maxLate;
        final isToday =
            AppConfig.dateId(day.date) == AppConfig.dateId(DateTime.now());

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text("${day.late}",
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: day.late > 0 ? Colors.orange : Colors.grey)),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  height: 100 * ratio + 4,
                  decoration: BoxDecoration(
                    color: isToday
                        ? Colors.orange
                        : Colors.orange.withValues(alpha: .35),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6)),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  weekdayShort[day.date.weekday - 1],
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight:
                        isToday ? FontWeight.w800 : FontWeight.w500,
                    color: isToday ? Colors.orange : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
