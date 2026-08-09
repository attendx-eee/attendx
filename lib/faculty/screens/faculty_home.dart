import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../admin/models/period_model.dart';
import '../../admin/services/timetable_service.dart';
import '../../admin/widgets/master_tile.dart';
import '../../core/auth/account_lookup.dart';
import '../../core/constants/app_config.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/section_header.dart';
import '../../notifications/services/local_notification_service.dart';
import '../../screens/face_enrollment_screen.dart';
// ScanProfile lives here, not in the enrollment screen. Dart imports
// aren't transitive, so importing the screen alone doesn't bring the
// enum its constructor takes.
import '../../services/enrollment/scan_harvester.dart';
import '../models/faculty_account.dart';
import '../models/period_attendance.dart';
import '../services/period_attendance_service.dart';
import 'classroom_scan_screen.dart';
import 'faculty_settings_screen.dart';

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

  /// The live account, re-read on every refresh.
  ///
  /// The one passed in was resolved once, when RoleRouter built this
  /// screen. Approval happens elsewhere and later, so relying on that
  /// snapshot meant a newly-approved lecturer stared at the waiting
  /// screen until they killed the app — pulling to refresh did nothing,
  /// because nothing re-read the field that had changed.
  late FacultyAccount _account = widget.account;

  /// Periods already marked today, keyed "year:periodNo".
  ///
  /// Keyed by both because period 3 for first years and period 3 for
  /// third years are different classes, and a faculty member teaching
  /// across years would otherwise see one marked and think both were.
  Map<String, PeriodAttendance> _marked = {};

  DateTime get _now => DateTime.now();

  String get _department => _account.department.isEmpty
      ? AppConfig.department
      : _account.department;

  @override
  void initState() {
    super.initState();
    _load();

    // Nothing scheduled faculty notifications before: the only caller
    // was the student dashboard, which a faculty account never reaches.
    if (widget.account.isApproved) {
      LocalNotificationService.instance.bootstrapForFaculty(
        uid: widget.account.uid,
        facultyId: widget.account.facultyId,
        department: _department,
      );
    }
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
          if (p.facultyId != _account.facultyId) continue;
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

      // Re-read alongside the timetable, so one refresh picks up both a
      // face enrolled moments ago and an approval granted since open.
      final me = await FirebaseFirestore.instance
          .collection(AccountLookup.facultyAccounts)
          .doc(widget.account.uid)
          .get();

      final data = me.data();

      if (mounted) {
        setState(() {
          _today = mine;
          _marked = marked;
          if (data != null) {
            _account = FacultyAccount.fromMap(widget.account.uid, data);
          }
          _faceEnrolled = data?['faceEnrolled'] == true;
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

  /// Entry point for the Capture card.
  ///
  /// Straight into the scan when there's only one candidate, a picker
  /// when there are several, and the whole week's subjects when nothing
  /// is scheduled — a lecturer taking an extra class on a Sunday still
  /// needs to be able to mark it.
  Future<void> _startCapture() async {
    if (_today.length == 1) {
      await _openScan(_today.first);
      return;
    }

    final candidates =
        _today.isNotEmpty ? _today : await _allMyPeriodsThisWeek();

    if (!mounted) return;

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No classes are assigned to you on the timetable '
              'yet. Ask the office to add them.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final chosen = await showModalBottomSheet<_TodayPeriod>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: Responsive.symmetric(horizontal: 12, vertical: 16),
          children: [
            Padding(
              padding: Responsive.symmetric(horizontal: 8),
              child: Text(
                _today.isNotEmpty
                    ? 'Which class are you marking?'
                    : 'Nothing scheduled today — pick a subject',
                style: AppTextStyles.title,
              ),
            ),
            SizedBox(height: Responsive.h(10)),
            ...candidates.map((entry) {
              final done =
                  _marked.containsKey('${entry.year}:${entry.period.periodNo}');
              return ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm)),
                leading: Icon(
                  done
                      ? Icons.check_circle_rounded
                      : Icons.menu_book_rounded,
                  color: done ? AppColors.success : AppColors.primary,
                ),
                title: Text(entry.period.subject,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  'Year ${entry.year} • ${entry.period.startTime}'
                  '${entry.period.batch.isEmpty ? '' : ' • Batch ${entry.period.batch}'}'
                  '${done ? ' • already marked' : ''}',
                  style: AppTextStyles.caption,
                ),
                onTap: () => Navigator.pop(sheetContext, entry),
              );
            }),
          ],
        ),
      ),
    );

    if (chosen != null) await _openScan(chosen);
  }

  /// Every period this faculty member teaches across the week, used when
  /// today has nothing on it.
  Future<List<_TodayPeriod>> _allMyPeriodsThisWeek() async {
    final mine = <_TodayPeriod>[];
    final seen = <String>{};

    try {
      for (final day in AppConfig.weekDays) {
        for (var year = 1; year <= 4; year++) {
          final periods = await TimetableService.instance.getDaySchedule(
            department: _department,
            academicYear: AppConfig.academicYear,
            year: year,
            day: day,
          );

          for (final p in periods) {
            if (p.isFree || p.subject.isEmpty) continue;
            if (p.facultyId != _account.facultyId) continue;

            // One entry per subject+year, not per timetable slot — the
            // point is choosing what to mark, and the same subject
            // appearing four times would just be noise.
            final key = '${p.subject}|$year|${p.batch}';
            if (!seen.add(key)) continue;

            mine.add(_TodayPeriod(period: p, year: year));
          }
        }
      }
    } catch (e) {
      debugPrint('Weekly period lookup failed: $e');
    }

    mine.sort((a, b) => a.period.subject.compareTo(b.period.subject));
    return mine;
  }

  Future<void> _openScan(_TodayPeriod entry) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ClassroomScanScreen(
          period: entry.period,
          year: entry.year,
          facultyId: _account.facultyId,
          facultyName: _account.name,
          facultyUid: widget.account.uid,
        ),
      ),
    );

    // Reload rather than just repainting — the period's record now
    // exists and the card should show its counts.
    if (saved == true && mounted) await _load();
  }

  /// Whether this account already has a face on file.
  bool _faceEnrolled = false;

  Future<void> _openFaceEnrollment() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        // Not mandatory: a staff account is already usable without it,
        // unlike a student's, so this stays skippable and repeatable.
        // Frontal-only — staff are matched close up and deliberately,
        // never across a room, so the wide sweep buys nothing.
        builder: (_) => const FaceEnrollmentScreen(
          mandatory: false,
          scanProfile: ScanProfile.frontalOnly,
        ),
      ),
    );
    if (mounted) await _load();
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
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              switch (value) {
                case 'settings':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          FacultySettingsScreen(account: _account),
                    ),
                  ).then((_) {
                    if (mounted) _load();
                  });
                case 'signout':
                  _confirmLogout();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings_outlined, size: 19),
                    SizedBox(width: 12),
                    Text('Settings'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'signout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded,
                        size: 19, color: AppColors.danger),
                    SizedBox(width: 12),
                    Text('Sign out',
                        style: TextStyle(color: AppColors.danger)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: MaxWidthBody(
        maxWidth: 820,
        child: !_account.isApproved
            ? _buildAwaitingApproval()
            : _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _buildBody(),
                  ),
      ),
    );
  }

  /// Shown until an admin approves the account and links it to a
  /// timetable record. Without that link there are no periods to list
  /// and nothing this screen could usefully do.
  Widget _buildAwaitingApproval() {
    final rejected = _account.isRejected;

    return ListView(
      padding: Responsive.all(24),
      children: [
        SizedBox(height: Responsive.h(40)),
        Center(
          child: Container(
            padding: Responsive.all(22),
            decoration: BoxDecoration(
              color: (rejected ? AppColors.danger : AppColors.warning)
                  .withValues(alpha: .1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              rejected
                  ? Icons.block_rounded
                  : Icons.hourglass_top_rounded,
              size: Responsive.sp(40),
              color: rejected ? AppColors.danger : AppColors.warning,
            ),
          ),
        ),
        SizedBox(height: Responsive.h(20)),
        Text(
          rejected
              ? 'Account not approved'
              : 'Waiting for admin approval',
          textAlign: TextAlign.center,
          style: AppTextStyles.title,
        ),
        SizedBox(height: Responsive.h(10)),
        Text(
          rejected
              ? (_account.decisionNote.isEmpty
                  ? 'Your staff account request was not approved. '
                      'Contact the department office.'
                  : _account.decisionNote)
              : 'The department office needs to confirm you and link your '
                  'account to your name on the timetable. Your classes '
                  'appear here as soon as they do.',
          textAlign: TextAlign.center,
          style: AppTextStyles.caption,
        ),
        SizedBox(height: Responsive.h(26)),

        // The way out of the waiting state. Approval happens on someone
        // else's screen, so this is what the lecturer taps once the
        // office tells them it's done.
        if (!rejected)
          Center(
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _load,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Check again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: Responsive.symmetric(horizontal: 22, vertical: 12),
              ),
            ),
          ),

        // Face setup is worth finishing while they wait — it's the one
        // thing they can do before approval, and doing it now means one
        // less step later.
        if (!_faceEnrolled) ...[
          SizedBox(height: Responsive.h(16)),
          Center(
            child: TextButton.icon(
              onPressed: _openFaceEnrollment,
              icon: const Icon(Icons.face_rounded, size: 18),
              label: const Text('Enroll my face'),
            ),
          ),
        ],

        SizedBox(height: Responsive.h(18)),
        Center(
          child: OutlinedButton.icon(
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign out'),
          ),
        ),
      ],
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
        SizedBox(height: Responsive.h(18)),

        // The primary action, and deliberately the first thing on the
        // screen. Marking a class is what a lecturer opens this app to
        // do; everything else here is context for it.
        _buildCaptureCard(),

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

        // Only shown when there's no face on file. Once it's set up,
        // re-scanning is a Settings concern rather than something the
        // home screen should keep advertising.
        if (!_faceEnrolled) ...[
          SizedBox(height: Responsive.h(18)),
          const SectionHeader(
            title: 'Finish setting up',
            subtitle: 'One step left',
          ),
          SizedBox(height: Responsive.h(14)),
          MasterTile(
            icon: Icons.face_rounded,
            title: 'Enroll my face',
            subtitle: 'Lets you sign in without typing a password',
            color: AppColors.teal,
            onTap: _openFaceEnrollment,
          ),
        ],
      ],
    );
  }

  /// The capture entry point.
  ///
  /// Kept separate from the period cards below because it answers a
  /// different question. The cards say "what am I teaching today"; this
  /// says "mark the class in front of me now" — and on a day with
  /// several classes, or none scheduled at all, the lecturer still needs
  /// a way in.
  Widget _buildCaptureCard() {
    final marked = _today
        .where((e) =>
            _marked.containsKey('${e.year}:${e.period.periodNo}'))
        .length;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.tealDark],
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: .3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          onTap: _startCapture,
          child: Padding(
            padding: Responsive.all(18),
            child: Row(
              children: [
                Container(
                  padding: Responsive.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(Icons.center_focus_strong_rounded,
                      color: Colors.white, size: Responsive.sp(26)),
                ),
                SizedBox(width: Responsive.w(16)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Capture attendance',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: Responsive.sp(17),
                        ),
                      ),
                      SizedBox(height: Responsive.h(4)),
                      Text(
                        _today.isEmpty
                            ? 'Pick a subject and scan the room'
                            : marked == _today.length
                                ? 'All of today\'s classes marked — tap to redo one'
                                : 'Scan the room to mark your subject',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .9),
                          fontSize: Responsive.sp(12),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.white70, size: Responsive.sp(15)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final initial = _account.name.isNotEmpty
        ? _account.name[0].toUpperCase()
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
                  _account.name,
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
                  '${_account.designation} • '
                  '${_account.department}',
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

