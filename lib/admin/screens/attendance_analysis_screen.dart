import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../attendance/models/attendance_marker.dart';
import '../../attendance/screens/student_attendance_screen.dart';
import '../../attendance/models/day_summary.dart';
import '../../attendance/services/semester_totals_service.dart';
import '../../core/constants/app_config.dart';
import '../../core/auth/account_lookup.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';
import '../../services/attendance_service.dart';

/// Which column the table is ordered by.
enum AnalysisSort {
  /// Register number, ascending. The default: it's the order marks
  /// sheets, seating and every other college list already uses, so an
  /// admin can read down the column and find a student without hunting.
  regNoAsc,
  regNoDesc,

  /// Worst attendance first — the order that matters when the point of
  /// opening this screen is to find who's falling behind.
  overallAsc,
  overallDesc,

  theoryAsc,
  theoryDesc,

  labAsc,
  labDesc;

  String get label => switch (this) {
        AnalysisSort.regNoAsc => 'Reg no ↑',
        AnalysisSort.regNoDesc => 'Reg no ↓',
        AnalysisSort.overallAsc => 'Overall ↑',
        AnalysisSort.overallDesc => 'Overall ↓',
        AnalysisSort.theoryAsc => 'Theory ↑',
        AnalysisSort.theoryDesc => 'Theory ↓',
        AnalysisSort.labAsc => 'Lab ↑',
        AnalysisSort.labDesc => 'Lab ↓',
      };

  /// ASCII-only version for the PDF.
  ///
  /// The built-in PDF fonts are Latin-1, so an arrow has no glyph and
  /// renders as a hollow box. Same reason the header avoids em dashes
  /// and bullets.
  String get pdfLabel => switch (this) {
        AnalysisSort.regNoAsc => 'Reg no (ascending)',
        AnalysisSort.regNoDesc => 'Reg no (descending)',
        AnalysisSort.overallAsc => 'Overall, lowest first',
        AnalysisSort.overallDesc => 'Overall, highest first',
        AnalysisSort.theoryAsc => 'Theory, lowest first',
        AnalysisSort.theoryDesc => 'Theory, highest first',
        AnalysisSort.labAsc => 'Lab, lowest first',
        AnalysisSort.labDesc => 'Lab, highest first',
      };
}

/// One student's row, backed entirely by [AttendanceTotals].
///
/// The row holds no arithmetic of its own. It used to count present and
/// absent *days* from gate events while the student's own app counted
/// *periods* from registers, and the two disagreed by ten points for the
/// same person. Every figure here now comes from the one service both
/// sides read.
class _Row {
  final String uid;
  final String name;
  final String regNo;
  final Map<String, dynamic> data;
  final AttendanceTotals totals;

  const _Row({
    required this.uid,
    required this.name,
    required this.regNo,
    required this.data,
    required this.totals,
  });

  /// Classes held, not scheduled. Zero means nothing has been
  /// registered for this student yet, so there is no percentage to show.
  int get held => totals.held;

  double get percent => totals.overallPercent;
  double get theoryPercent => totals.theoryPercent;
  double get labPercent => totals.labPercent;

  /// The conventional attendance bar in Indian engineering colleges.
  bool get isShort => totals.isShortOverall;
}

/// Admin-only: attendance for a chosen month and B.Tech year.
///
/// Deliberately a table rather than a chart. The question an admin brings
/// here is "who is short this month, and by how much" — and that's a list
/// you read, sort and export, not a shape you eyeball.
class AttendanceAnalysisScreen extends StatefulWidget {
  const AttendanceAnalysisScreen({super.key});

  @override
  State<AttendanceAnalysisScreen> createState() =>
      _AttendanceAnalysisScreenState();
}

class _AttendanceAnalysisScreenState extends State<AttendanceAnalysisScreen> {
  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  late DateTime _month = () {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }();

  int _year = 1;
  AnalysisSort _sort = AnalysisSort.regNoAsc;

  /// False = the selected month, true = everything since the semester
  /// began. Attendance rules are applied to the semester, so that is the
  /// figure that decides eligibility; the month view is for spotting a
  /// bad patch early.
  bool _wholeSemester = true;

  bool _loading = true;
  bool _exporting = false;
  String? _error;
  List<_Row> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Months from the start of the semester up to the current one — there
  /// is no attendance to analyse outside that window.
  List<DateTime> get _selectableMonths {
    final start = AttendanceService.instance.semesterStart();
    final now = DateTime.now();

    final months = <DateTime>[];
    var cursor = DateTime(start.year, start.month);
    final end = DateTime(now.year, now.month);

    while (!cursor.isAfter(end)) {
      months.add(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1);
    }

    // A freshly-started semester still needs one entry to show.
    return months.isEmpty ? [end] : months;
  }

  String _labelFor(DateTime month) =>
      '${_monthNames[month.month - 1]} ${month.year}';

  String get _monthLabel => _labelFor(_month);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('students').get();

      final students = snapshot.docs.where((doc) {
        final data = doc.data();
        // Staff records that predate the collection split still sit in
        // `students`. Counting them would drag every percentage down
        // with people who were never in the class.
        if (!AccountLookup.isStudentDoc(data)) return false;
        return AppConfig.departmentOf(data) == AppConfig.department &&
            AppConfig.yearOf(data) == _year;
      }).toList();

      // Cleared so a reload after marking attendance sees the new
      // records rather than the ones cached when the screen opened.
      SemesterTotalsService.instance.clearCache();

      final byUid = {
        for (final doc in students) doc.id: doc.data(),
      };

      // The window: this month only, or the whole semester to date.
      final months = _wholeSemester
          ? SemesterTotalsService.instance.semesterMonths()
          : [_month];

      final totals = await SemesterTotalsService.instance.forGroup(
        students: byUid,
        months: months,
      );

      final rows = <_Row>[];

      for (final doc in students) {
        final data = doc.data();

        rows.add(_Row(
          uid: doc.id,
          name: (data['name'] ?? 'Unknown').toString(),
          regNo: (data['regNo'] ?? '').toString(),
          data: data,
          totals: totals[doc.id] ?? AttendanceTotals(),
        ));
      }

      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Register numbers are strings but read as numbers, so "10" must sort
  /// after "9", not before it. Comparing the trailing digits handles the
  /// usual "21EE001" style; anything unparseable falls back to plain
  /// text order.
  int _compareRegNo(_Row a, _Row b) {
    int? tail(String s) {
      final m = RegExp(r'(\d+)\s*$').firstMatch(s);
      return m == null ? null : int.tryParse(m.group(1)!);
    }

    final ta = tail(a.regNo);
    final tb = tail(b.regNo);

    if (ta != null && tb != null) {
      // Same numeric tail but different prefixes ("21EE010" vs "22EE010")
      // still needs a tiebreak.
      final byPrefix = a.regNo
          .substring(0, a.regNo.length - ta.toString().length)
          .compareTo(b.regNo.substring(0, b.regNo.length - tb.toString().length));
      if (byPrefix != 0) return byPrefix;
      return ta.compareTo(tb);
    }

    return a.regNo.toLowerCase().compareTo(b.regNo.toLowerCase());
  }

  List<_Row> get _sortedRows {
    final rows = [..._rows];

    // Every percentage sort breaks ties on register number, so the
    // order is stable and predictable rather than whatever Firestore
    // happened to return.
    void byMetric(double Function(_Row) metric, {required bool ascending}) {
      rows.sort((a, b) {
        final c = ascending
            ? metric(a).compareTo(metric(b))
            : metric(b).compareTo(metric(a));
        return c != 0 ? c : _compareRegNo(a, b);
      });
    }

    switch (_sort) {
      case AnalysisSort.regNoAsc:
        rows.sort(_compareRegNo);
      case AnalysisSort.regNoDesc:
        rows.sort((a, b) => _compareRegNo(b, a));
      case AnalysisSort.overallAsc:
        byMetric((r) => r.percent, ascending: true);
      case AnalysisSort.overallDesc:
        byMetric((r) => r.percent, ascending: false);
      case AnalysisSort.theoryAsc:
        byMetric((r) => r.theoryPercent, ascending: true);
      case AnalysisSort.theoryDesc:
        byMetric((r) => r.theoryPercent, ascending: false);
      case AnalysisSort.labAsc:
        byMetric((r) => r.labPercent, ascending: true);
      case AnalysisSort.labDesc:
        byMetric((r) => r.labPercent, ascending: false);
    }

    return rows;
  }

  double get _classAverage {
    final counted = _rows.where((r) => r.held > 0).toList();
    if (counted.isEmpty) return 0;
    return counted.map((r) => r.percent).reduce((a, b) => a + b) /
        counted.length;
  }

  int get _shortCount => _rows.where((r) => r.isShort).length;

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);

    try {
      final rows = _sortedRows;
      final doc = pw.Document();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ASCII only in the PDF.
              //
              // The built-in PDF fonts are Latin-1: an em dash, a
              // bullet, or a curly quote has no glyph and renders as a
              // hollow box. Embedding a Unicode font would fix it too,
              // at the cost of a few hundred KB in the APK for
              // punctuation nobody needs on a report.
              pw.Text(
                'Attendance Analysis - Year $_year, '
                '${_wholeSemester ? 'semester to date' : _monthLabel}',
                style:
                    pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '${AppConfig.department} | ${AppConfig.academicYear} | '
                'sorted by ${_sort.pdfLabel}',
                style:
                    const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Class average ${_classAverage.toStringAsFixed(1)}% | '
                '$_shortCount of ${rows.length} below 75% | '
                'lab counts ${ClassWeight.lab}, theory '
                '${ClassWeight.theory}',
                style:
                    const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 14),
            ],
          ),
          build: (context) => [
            pw.TableHelper.fromTextArray(
              // The same seven values the table on screen shows, in the
              // same order. An export that disagrees with the screen it
              // was taken from is worse than no export.
              headers: const [
                'Reg No',
                'Name',
                'Theory',
                'Lab',
                'Classes',
                'Points',
                'Overall %',
              ],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
                color: PdfColors.white,
              ),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.blue700),
              cellStyle: const pw.TextStyle(fontSize: 9.5),
              cellAlignment: pw.Alignment.centerLeft,
              rowDecoration: const pw.BoxDecoration(
                border: pw.Border(
                    bottom:
                        pw.BorderSide(color: PdfColors.grey300, width: .5)),
              ),
              cellPadding:
                  const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              data: rows
                  .map((r) => [
                        r.regNo.isEmpty ? '--' : r.regNo,
                        r.name,
                        r.totals.theoryHeld == 0
                            ? '--'
                            : '${r.totals.theoryAttended}/'
                                '${r.totals.theoryHeld}  '
                                '(${r.theoryPercent.toStringAsFixed(0)}%)',
                        r.totals.labHeld == 0
                            ? '--'
                            : '${r.totals.labAttended}/${r.totals.labHeld}  '
                                '(${r.labPercent.toStringAsFixed(0)}%)',
                        '${r.totals.attended}/${r.held}',
                        '${r.totals.attendedPoints}/'
                            '${r.totals.heldPoints}',
                        r.held == 0
                            ? '--'
                            : '${r.percent.toStringAsFixed(1)}%',
                      ])
                  .toList(),
            ),
          ],
        ),
      );

      await Printing.sharePdf(
        bytes: await doc.save(),
        filename:
            _wholeSemester
                ? 'attendance_year${_year}_semester.pdf'
                : 'attendance_year${_year}_${_month.year}-'
                    '${_month.month.toString().padLeft(2, '0')}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Couldn't build the PDF: $e"),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Opens the student's calendar, then reloads — a correction made
  /// there should be reflected in the table the admin comes back to.
  void _openStudent(_Row row) {
    final user = FirebaseAuth.instance.currentUser;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentAttendanceScreen(
          studentUid: row.uid,
          studentData: row.data,
          marker: AttendanceMarker.admin(
            uid: user?.uid ?? '',
            name: user?.displayName?.trim().isNotEmpty == true
                ? user!.displayName!.trim()
                : 'Admin',
          ),
        ),
      ),
    ).then((_) {
      if (mounted) _load();
    });
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Attendance Analysis"),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          IconButton(
            tooltip: "Refresh",
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
          IconButton(
            tooltip: "Export PDF",
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _loading || _rows.isEmpty || _exporting
                ? null
                : _exportPdf,
          ),
        ],
      ),
      body: MaxWidthBody(
        child: Column(
          children: [
            _buildFilters(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: Responsive.symmetric(horizontal: 18, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _Dropdown<DateTime>(
                  label: "Month",
                  icon: Icons.calendar_month_outlined,
                  value: _selectableMonths.any((m) =>
                          m.year == _month.year && m.month == _month.month)
                      ? _selectableMonths.firstWhere((m) =>
                          m.year == _month.year && m.month == _month.month)
                      : _selectableMonths.last,
                  items: {
                    for (final m in _selectableMonths.reversed)
                      m: _labelFor(m),
                  },
                  onChanged: (m) {
                    if (m == null) return;
                    setState(() => _month = m);
                    _load();
                  },
                ),
              ),
              SizedBox(width: Responsive.w(12)),
              Expanded(
                flex: 2,
                child: _Dropdown<int>(
                  label: "Year",
                  icon: Icons.school_outlined,
                  value: _year,
                  items: const {
                    1: "1st Year",
                    2: "2nd Year",
                    3: "3rd Year",
                    4: "4th Year",
                  },
                  onChanged: (y) {
                    if (y == null) return;
                    setState(() => _year = y);
                    _load();
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: Responsive.h(10)),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _Dropdown<AnalysisSort>(
                  label: "Sort by",
                  icon: Icons.sort_rounded,
                  value: _sort,
                  items: {for (final s in AnalysisSort.values) s: s.label},
                  onChanged: (s) {
                    if (s == null) return;
                    setState(() => _sort = s);
                  },
                ),
              ),
              SizedBox(width: Responsive.w(12)),
              Expanded(
                flex: 2,
                child: _Dropdown<bool>(
                  label: "Period",
                  icon: Icons.date_range_rounded,
                  value: _wholeSemester,
                  items: const {
                    true: "Whole semester",
                    false: "Selected month",
                  },
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _wholeSemester = v);
                    _load();
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: Responsive.h(8)),
          Text(
            _wholeSemester
                ? 'Semester to date. A lab counts '
                    '${ClassWeight.lab}, a theory class '
                    '${ClassWeight.theory}; percentages are over classes '
                    'actually held, not the whole timetable.'
                : 'Selected month only. Eligibility is judged on the '
                    'semester, so switch back before deciding anything.',
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: Responsive.all(24),
          child: Text("Couldn't load attendance: $_error",
              textAlign: TextAlign.center, style: AppTextStyles.body),
        ),
      );
    }

    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: Responsive.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: Responsive.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .08),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.query_stats_rounded,
                    size: Responsive.sp(38), color: AppColors.primary),
              ),
              SizedBox(height: Responsive.h(16)),
              Text("No students in Year $_year",
                  style: AppTextStyles.title, textAlign: TextAlign.center),
              SizedBox(height: Responsive.h(6)),
              Text("Register students in this year to analyse their month.",
                  textAlign: TextAlign.center, style: AppTextStyles.caption),
            ],
          ),
        ),
      );
    }

    final rows = _sortedRows;

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        Responsive.w(18),
        0,
        Responsive.w(18),
        Responsive.h(28),
      ),
      itemCount: rows.length + 2,
      separatorBuilder: (_, _) => SizedBox(height: Responsive.h(8)),
      itemBuilder: (context, index) {
        if (index == 0) return _buildSummary(rows.length);
        if (index == 1) return _buildTableHeader();
        return _StudentRow(
          row: rows[index - 2],
          rank: index - 1,
          onTap: () => _openStudent(rows[index - 2]),
        );
      },
    );
  }

  Widget _buildSummary(int count) {
    return Container(
      margin: EdgeInsets.only(bottom: Responsive.h(6)),
      padding: Responsive.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Year $_year  •  $_monthLabel", style: AppTextStyles.title),
          SizedBox(height: Responsive.h(12)),
          Row(
            children: [
              _Metric(
                value: "$count",
                label: "Students",
                color: AppColors.primary,
              ),
              _Metric(
                value: "${_classAverage.toStringAsFixed(1)}%",
                label: "Class average",
                color: _classAverage >= 75
                    ? AppColors.success
                    : AppColors.warning,
              ),
              _Metric(
                value: "$_shortCount",
                label: "Below 75%",
                color: _shortCount == 0
                    ? AppColors.success
                    : AppColors.danger,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: Responsive.w(14), vertical: Responsive.h(4)),
      child: Row(
        children: [
          SizedBox(width: Responsive.w(34)),
          Expanded(
            flex: 4,
            child: Text("STUDENT", style: _headerStyle),
          ),
          Expanded(
            flex: 3,
            child: Text("P / A / L",
                textAlign: TextAlign.center, style: _headerStyle),
          ),
          SizedBox(
            width: Responsive.w(58),
            child:
                Text("%", textAlign: TextAlign.right, style: _headerStyle),
          ),
        ],
      ),
    );
  }

  TextStyle get _headerStyle => TextStyle(
        fontSize: Responsive.sp(10),
        fontWeight: FontWeight.w800,
        color: AppColors.textSecondary,
        letterSpacing: .5,
      );
}

/// One student's line in the table. Tapping opens their calendar, so a
/// short-attendance student can be inspected and corrected in one hop.
class _StudentRow extends StatelessWidget {
  final _Row row;
  final int rank;
  final VoidCallback onTap;

  const _StudentRow({
    required this.row,
    required this.rank,
    required this.onTap,
  });

  Color get _percentColor {
    if (row.held == 0) return AppColors.textSecondary;
    if (row.percent >= 75) return AppColors.success;
    if (row.percent >= 65) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 10, offset: Offset(0, 4)),
        ],
        border: row.isShort
            ? Border.all(color: AppColors.danger.withValues(alpha: .35))
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: Responsive.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: Responsive.w(34),
                  child: Text(
                    "$rank",
                    style: TextStyle(
                      fontSize: Responsive.sp(12),
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.title
                            .copyWith(fontSize: Responsive.sp(14)),
                      ),
                      SizedBox(height: Responsive.h(2)),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              row.regNo.isEmpty ? "No reg no" : row.regNo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption,
                            ),
                          ),
                          if (row.totals.daysPartial > 0) ...[
                            SizedBox(width: Responsive.w(6)),
                            Icon(Icons.hourglass_bottom_rounded,
                                size: Responsive.sp(13),
                                color: Colors.amber.shade700),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Theory and lab side by side, each over the classes
                // actually held. The combined figure lives in the
                // percentage pill on the right; showing it here as well
                // is where two numbers start drifting apart.
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _MiniStat(
                        icon: Icons.menu_book_rounded,
                        value: row.totals.theoryHeld == 0
                            ? '--'
                            : '${row.totals.theoryAttended}/'
                                '${row.totals.theoryHeld}',
                        short: row.totals.isShortTheory,
                      ),
                      SizedBox(height: Responsive.h(3)),
                      _MiniStat(
                        icon: Icons.science_rounded,
                        value: row.totals.labHeld == 0
                            ? '--'
                            : '${row.totals.labAttended}/'
                                '${row.totals.labHeld}',
                        short: row.totals.isShortLab,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: Responsive.w(58),
                  child: Text(
                    row.held == 0
                        ? "--"
                        : "${row.percent.toStringAsFixed(0)}%",
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: Responsive.sp(15),
                      fontWeight: FontWeight.w800,
                      color: _percentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _Metric({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: AppTextStyles.headline
                  .copyWith(color: color, fontSize: Responsive.sp(20))),
          SizedBox(height: Responsive.h(2)),
          Text(label, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;

  const _Dropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            Responsive.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
      ),
      items: items.entries
          .map((e) => DropdownMenuItem<T>(
                value: e.key,
                child: Text(e.value,
                    style: TextStyle(fontSize: Responsive.sp(13))),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }
}

/// One icon plus a fraction, for the theory / lab pair on each row.
class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final bool short;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.short,
  });

  @override
  Widget build(BuildContext context) {
    final colour = short ? AppColors.danger : AppColors.textSecondary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: Responsive.sp(12), color: colour),
        SizedBox(width: Responsive.w(4)),
        Text(
          value,
          style: AppTextStyles.caption.copyWith(
            fontWeight: FontWeight.w700,
            color: short ? AppColors.danger : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
