import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../admin/models/period_model.dart';
import '../../admin/services/timetable_service.dart';
import '../../admin/widgets/master_tile.dart';
import '../../core/constants/app_config.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/section_header.dart';
import '../models/faculty_account.dart';
import '../models/period_attendance.dart';
import '../services/period_attendance_service.dart';
import 'classroom_scan_screen.dart';

/// A period this faculty member teaches today, with the year it's for.
class _TodayPeriod {
  final PeriodModel period;
  final int year;

  const _TodayPeriod({required this.period, required this.year});
}

/// The faculty member's day.
///
/// Their timetable isn't stored per-teacher — it's stored per year, with
/// a facultyId on each period — so their day has to be assembled by
/// reading all four years' schedules for today and keeping the periods
/// that name them. Four reads, once, on open.
class FacultyHome extends StatefulWidget {
  final FacultyAccount account;
  final Future<void> Function(BuildContext context)? onLogout;

  const FacultyHome({
    super.key,
    required this.account,
    this.onLogout,
  });

  @override
  State<FacultyHome> createState() => _FacultyHomeState();
}

class _FacultyHomeState extends State<FacultyHome> {
  bool _loading = true;
  String? _error;
  List<_TodayPeriod> _today = const [];

  /// Periods already marked today, keyed "year:periodNo".
  ///
  /// Keyed by both because period 3 for first years and period 3 for
  /// third years are different classes, and a faculty member teaching
  /// across years would otherwise see one marked and think both were.
  Map<String, PeriodAttendance> _marked = {};

  DateTime get _now => DateTime.now();

  String get _department => widget.account.department.isEmpty
      ? AppConfig.department
      : widget.account.department;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final weekday = AppConfig.dayName(_now);

      if (weekday == 'Sunday') {
        if (mounted) {
          setState(() {
            _today = const [];
            _loading = false;
          });
        }
        return;
      }

      final mine = <_TodayPeriod>[];

      for (var year = 1; year <= 4; year++) {
        final periods = await TimetableService.instance.getDaySchedule(
          department: _department,
          academicYear: AppConfig.academicYear,
          year: year,
          day: weekday,
        );

        for (final p in periods) {
          if (p.isFree || p.subject.isEmpty) continue;
          if (p.facultyId != widget.account.facultyId) continue;
          mine.add(_TodayPeriod(period: p, year: year));
        }
      }

      mine.sort((a, b) => a.period.startTime.compareTo(b.period.startTime));

      // Which of those are already marked. One lookup per period rather
      // than a stream, because a faculty member can teach several years
      // in a day and a single year-scoped stream would miss the rest.
      final dateId = AppConfig.dateId(_now);
      final marked = <String, PeriodAttendance>{};

      for (final entry in mine) {
        final record = await PeriodAttendanceService.instance.forPeriod(
          department: _department,
          year: entry.year,
          date: dateId,
          periodNo: entry.period.periodNo,
        );
        if (record != null) {
          marked['${entry.year}:${entry.period.periodNo}'] = record;
        }
      }

      if (mounted) {
        setState(() {
          _today = mine;
          _marked = marked;
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

  Future<void> _openScan(_TodayPeriod entry) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ClassroomScanScreen(
          period: entry.period,
          year: entry.year,
          facultyId: widget.account.facultyId,
          facultyName: widget.account.name,
          facultyUid: widget.account.uid,
        ),
      ),
    );

    // Reload rather than just repainting — the period's record now
    // exists and the card should show its counts.
    if (saved == true && mounted) await _load();
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md)),
            icon: const Icon(Icons.logout_rounded,
                color: AppColors.danger, size: 34),
            title: const Text('Sign out?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Stay'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    if (widget.onLogout != null) {
      await widget.onLogout!(context);
    } else {
      await FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Classes'),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: MaxWidthBody(
        maxWidth: 820,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: _buildBody(),
              ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return ListView(
        padding: Responsive.all(24),
        children: [
          Text("Couldn't load your timetable: $_error",
              textAlign: TextAlign.center, style: AppTextStyles.body),
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        Responsive.w(18),
        Responsive.h(10),
        Responsive.w(18),
        Responsive.h(28),
      ),
      children: [
        _buildHeader(),
        SizedBox(height: Responsive.h(20)),
        SectionHeader(
          title: 'Today — ${AppConfig.dayName(_now)}',
          subtitle: _today.isEmpty
              ? 'Nothing scheduled'
              : '${_today.length} class${_today.length == 1 ? '' : 'es'}',
        ),
        SizedBox(height: Responsive.h(14)),
        if (_today.isEmpty)
          _buildEmpty()
        else
          ..._today.map((entry) => _PeriodCard(
                entry: entry,
                record: _marked['${entry.year}:${entry.period.periodNo}'],
                onTap: () => _openScan(entry),
              )),
      ],
    );
  }

  Widget _buildHeader() {
    final initial = widget.account.name.isNotEmpty
        ? widget.account.name[0].toUpperCase()
        : '?';

    return Container(
      padding: Responsive.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: Responsive.w(26),
            backgroundColor: Colors.white24,
            child: Text(
              initial,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: Responsive.sp(20),
              ),
            ),
          ),
          SizedBox(width: Responsive.w(14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: Responsive.sp(17),
                  ),
                ),
                SizedBox(height: Responsive.h(3)),
                Text(
                  '${widget.account.designation} • '
                  '${widget.account.department}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .88),
                    fontSize: Responsive.sp(12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: Responsive.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            padding: Responsive.all(20),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.free_breakfast_rounded,
                size: Responsive.sp(38), color: AppColors.primary),
          ),
          SizedBox(height: Responsive.h(16)),
          Text('No classes today', style: AppTextStyles.title),
          SizedBox(height: Responsive.h(6)),
          Text(
            'Classes assigned to you on the timetable will appear here.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}

/// One of today's classes, and whether it's been marked yet.
class _PeriodCard extends StatelessWidget {
  final _TodayPeriod entry;
  final PeriodAttendance? record;
  final VoidCallback onTap;

  const _PeriodCard({
    required this.entry,
    required this.record,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final marked = record != null;

    return MasterTile(
      icon: marked
          ? Icons.check_circle_rounded
          : Icons.center_focus_strong_rounded,
      title: entry.period.subject,
      subtitle: marked
          ? '${record!.presentUids.length} present • '
              '${record!.recognisedCount} by camera • tap to redo'
          : 'Year ${entry.year} • ${entry.period.startTime}-'
              '${entry.period.endTime} • ${entry.period.room}'
              '${entry.period.batch.isEmpty ? '' : ' • Batch ${entry.period.batch}'}',
      color: marked ? AppColors.success : AppColors.primary,
      onTap: onTap,
    );
  }
}

