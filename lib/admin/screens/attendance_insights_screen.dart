import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../attendance/services/manual_attendance_service.dart';
import '../../core/constants/app_config.dart';
import '../../core/auth/account_lookup.dart';
import '../../services/attendance_service.dart';

/// Admin-only attendance insights fed by Raspberry Pi check-in events:
/// today's check-in/late/absent summary, a 7-day late-check-in count
/// graph, and the list of late/marked-absent students across the week
/// (exportable as a PDF).
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

/// One row in the weekly late-arrivals report: either "late" (checked in
/// between the present and late cutoffs, still counts as present) or
/// "marked absent" (checked in after the late cutoff — arrived, but too
/// late to count).
class _WeeklyLateEntry {
  final DateTime date;
  final String name;
  final String regNo;
  final int year;
  final DateTime checkIn;
  final bool markedAbsent;

  const _WeeklyLateEntry({
    required this.date,
    required this.name,
    required this.regNo,
    required this.year,
    required this.checkIn,
    required this.markedAbsent,
  });
}

class _AttendanceInsightsScreenState extends State<AttendanceInsightsScreen> {
  bool _loading = true;
  bool _exportingPdf = false;
  int _totalStudents = 0;
  List<_DayInsight> _week = [];
  List<_LateStudent> _lateToday = [];
  List<_WeeklyLateEntry> _weeklyLate = [];

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
          if (AccountLookup.isStudentDoc(doc.data()) &&
              AppConfig.departmentOf(doc.data()) == AppConfig.department)
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
      final weeklyLate = <_WeeklyLateEntry>[];

      for (final date in days) {
        final insight = _DayInsight(date);
        final weekday = AppConfig.dayName(date);

        final dateId = AppConfig.dateId(date);
        final events = await AttendanceService.instance.eventsOn(dateId);

        // This report is deliberately built from check-in events — it's
        // about who walked through the door and when. Manual marks are
        // still applied on top, so a student staff already excused isn't
        // listed as a late arrival for the rest of the week.
        final manual = await ManualAttendanceService.instance.onDate(dateId);

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
            manual: manual[uid],
          );

          if (verdict == null) continue; // not a college day

          final name = (student['name'] ?? 'Unknown').toString();
          final regNo = (student['regNo'] ?? '--').toString();
          final inTime = checkIn.toDate();

          if (verdict.present) {
            insight.checkIns++;
            if (verdict.late) {
              insight.late++;

              // Present, but after the 9:15 AM cutoff.
              weeklyLate.add(_WeeklyLateEntry(
                date: date,
                name: name,
                regNo: regNo,
                year: year,
                checkIn: inTime,
                markedAbsent: false,
              ));

              final isToday =
                  AppConfig.dateId(date) == AppConfig.dateId(today);
              if (isToday) {
                lateToday.add(_LateStudent(
                  name: name,
                  regNo: regNo,
                  year: year,
                  checkIn: inTime,
                  lateByMinutes: verdict.lateByMinutes,
                ));
              }
            }
          } else {
            // Checked in, but after the 9:30 AM cutoff — still surfaced so
            // admins can see who actually showed up, just too late to
            // count as present.
            weeklyLate.add(_WeeklyLateEntry(
              date: date,
              name: name,
              regNo: regNo,
              year: year,
              checkIn: inTime,
              markedAbsent: true,
            ));
          }
        }

        week.add(insight);
      }

      lateToday.sort((a, b) => b.lateByMinutes.compareTo(a.lateByMinutes));
      weeklyLate.sort((a, b) {
        final byDate = b.date.compareTo(a.date); // most recent day first
        return byDate != 0 ? byDate : a.checkIn.compareTo(b.checkIn);
      });

      if (mounted) {
        setState(() {
          _week = week;
          _lateToday = lateToday;
          _weeklyLate = weeklyLate;
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

  /// Builds a PDF of this week's late/marked-absent arrivals and opens
  /// the native share sheet so the admin can save or send it.
  Future<void> _exportWeeklyPdf() async {
    if (_weeklyLate.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No late arrivals to export this week")),
      );
      return;
    }

    setState(() => _exportingPdf = true);
    try {
      final rows = _weeklyLate
          .map((s) => [
                DateFormat('dd MMM (EEE)').format(s.date),
                s.name,
                s.regNo,
                'Y${s.year}',
                _fmtTime(s.checkIn),
                s.markedAbsent
                    ? 'Absent (after ${AppConfig.lateCutoffLabel})'
                    : 'Late',
              ])
          .toList();

      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'AttendX — Weekly Late Arrivals Report',
                style:
                    pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Department: ${AppConfig.department}   |   Generated: '
                '${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Present up to ${AppConfig.presentCutoffLabel}  |  Late '
                '${AppConfig.presentCutoffLabel}-${AppConfig.lateCutoffLabel}  |  '
                'Absent after ${AppConfig.lateCutoffLabel}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 14),
            ],
          ),
          build: (context) => [
            pw.TableHelper.fromTextArray(
              headers: const ['Date', 'Name', 'Reg No', 'Year', 'Check-in', 'Status'],
              data: rows,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.deepOrange),
              cellStyle: const pw.TextStyle(fontSize: 9.5),
              cellAlignment: pw.Alignment.centerLeft,
              rowDecoration: const pw.BoxDecoration(
                border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey300, width: .5)),
              ),
              cellPadding:
                  const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            ),
          ],
        ),
      );

      final bytes = await doc.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'weekly_late_report_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );
    } catch (e) {
      debugPrint('PDF export failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't generate the PDF report")),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
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
                      sub: "after ${AppConfig.presentCutoffLabel}",
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
                          "Students arriving after ${AppConfig.presentCutoffLabel}",
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
                const SizedBox(height: 24),

                // ---------------------------- weekly late/absent report
                Row(
                  children: [
                    Expanded(
                      child: Text("Late arrivals this week",
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    FilledButton.icon(
                      onPressed: _exportingPdf ? null : _exportWeeklyPdf,
                      icon: _exportingPdf
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: Text(_exportingPdf ? "Preparing…" : "Download PDF"),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "Present up to ${AppConfig.presentCutoffLabel}  •  Late up to "
                  "${AppConfig.lateCutoffLabel}  •  Absent after ${AppConfig.lateCutoffLabel}",
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 10),
                if (_weeklyLate.isEmpty)
                  const Card(
                    elevation: 0,
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                          child: Text("No late arrivals in the last 7 college days")),
                    ),
                  )
                else
                  ..._weeklyLate.map(
                    (s) => Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: s.markedAbsent
                              ? Colors.red.shade50
                              : Colors.orange.shade100,
                          child: Text("Y${s.year}",
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: s.markedAbsent
                                      ? Colors.red
                                      : Colors.orange)),
                        ),
                        title: Text(s.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            "Reg ${s.regNo}  •  ${DateFormat('dd MMM (EEE)').format(s.date)}"),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_fmtTime(s.checkIn),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: s.markedAbsent
                                    ? Colors.red.shade50
                                    : Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                s.markedAbsent ? "Absent" : "Late",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: s.markedAbsent
                                      ? Colors.red
                                      : Colors.orange,
                                ),
                              ),
                            ),
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
