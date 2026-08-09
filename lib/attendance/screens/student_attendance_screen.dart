import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../admin/models/holiday_model.dart';
import '../../admin/services/holiday_service.dart';
import '../../core/constants/app_config.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/attendance_palette.dart';
import '../../faculty/services/period_attendance_service.dart';
import '../../services/attendance_service.dart';
import '../models/attendance_marker.dart';
import '../models/attendance_permission_model.dart';
import '../models/day_summary.dart';
import '../models/manual_attendance_model.dart';
import '../services/attendance_permission_service.dart';
import '../services/manual_attendance_service.dart';
import 'day_class_mark_sheet.dart';

/// One student's attendance, month by month, with marking.
///
/// The calendar opens on the current month and can be walked back to the
/// month the semester began — there's nothing before that to correct, so
/// the back arrow simply stops there rather than letting the admin
/// wander into empty months.
///
/// Marking rights differ by role and that difference is enforced here,
/// per displayed month:
/// - an admin can mark any past or present day outright;
/// - a CR can only mark inside a month the admin has approved for them,
///   and the banner at the top of the screen is how they request it.
class StudentAttendanceScreen extends StatefulWidget {
  final String studentUid;
  final Map<String, dynamic> studentData;
  final AttendanceMarker marker;

  const StudentAttendanceScreen({
    super.key,
    required this.studentUid,
    required this.studentData,
    required this.marker,
  });

  @override
  State<StudentAttendanceScreen> createState() =>
      _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen> {
  late final String _studentName =
      (widget.studentData['name'] ?? 'Student').toString();
  late final int _studentYear = AppConfig.yearOf(widget.studentData);

  /// First month the calendar may show — the semester's opening month.
  late final DateTime _firstMonth = () {
    final start = AttendanceService.instance.semesterStart();
    return DateTime(start.year, start.month);
  }();

  late DateTime _visibleMonth = () {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }();

  /// Pi check-in events for this student, keyed by yyyy-MM-dd. Fetched
  /// once — they're immutable from the app's side, so there's nothing to
  /// keep listening for.
  Map<String, Map<String, dynamic>> _events = {};
  bool _loadingEvents = true;
  bool _saving = false;

  /// The month currently drawn, and a fingerprint of what produced it.
  ///
  /// Resolving a month is async (it walks the timetable day by day), so
  /// driving it from a FutureBuilder inline in `build` would kick off a
  /// fresh computation — and flash a spinner — on every rebuild, including
  /// harmless ones like toggling the saving bar. Instead the result is
  /// held here and only recomputed when the inputs actually change; until
  /// the new month lands, the previous one stays on screen.
  Map<int, DayVerdict>? _verdicts;
  String? _verdictKey;

  /// Per-class counts for the visible month, keyed by day-of-month.
  ///
  /// Loaded alongside the verdicts rather than folded into them: a
  /// verdict answers "was this student in college", a summary answers
  /// "how much of the day did they attend", and the calendar needs both
  /// — a day can be a whole-day present by the gate and still be 1 of 2
  /// classes once the registers are in.
  Map<int, DaySummary> _periodDays = const {};

  /// Bumped after a per-class save so the month reloads even though
  /// neither the month nor the manual marks changed.
  int _periodRevision = 0;

  /// Days picked out for a single bulk action, by day-of-month.
  ///
  /// Empty means normal mode: tapping a day opens its sheet. Non-empty
  /// means selection mode, entered by long-pressing any day — tapping
  /// then adds and removes days instead, and one status is applied to
  /// all of them at once. Marking a week of medical leave shouldn't be
  /// seven sheets, seven writes and seven notifications.
  final Set<int> _selectedDays = {};

  bool get _selecting => _selectedDays.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    try {
      final events =
          await AttendanceService.instance.eventsFor(widget.studentUid);
      if (mounted) {
        setState(() {
          _events = events;
          _loadingEvents = false;
        });
      }
    } catch (e) {
      debugPrint('Attendance events load failed: $e');
      if (mounted) setState(() => _loadingEvents = false);
    }
  }

  String get _monthId => AttendancePermission.monthId(_visibleMonth);

  String get _monthLabel => AttendancePermission.monthLabel(_monthId);

  bool get _canGoBack => _visibleMonth.isAfter(_firstMonth);

  bool get _canGoForward {
    final now = DateTime.now();
    return _visibleMonth.isBefore(DateTime(now.year, now.month));
  }

  void _shiftMonth(int delta) {
    setState(() {
      _visibleMonth =
          DateTime(_visibleMonth.year, _visibleMonth.month + delta);
      // Drop the old month's grid rather than showing it under the new
      // month's heading for a frame — a brief spinner beats wrong data.
      _verdicts = null;
      // Selections are day-of-month numbers, so carrying them across a
      // month boundary would silently retarget them at different dates.
      _selectedDays.clear();
    });
  }

  /// Recomputes the visible month if — and only if — the month or the
  /// manual marks behind it have changed since the last pass.
  void _refreshVerdicts(Map<String, ManualAttendance> manual) {
    final marks = manual.entries
        .map((e) => '${e.key}:${e.value.status}')
        .toList()
      ..sort();
    final key = '$_monthId|$_periodRevision|${marks.join(',')}';

    if (key == _verdictKey) return;
    _verdictKey = key;

    AttendanceService.instance
        .monthVerdicts(
      studentData: widget.studentData,
      eventsByDate: _events,
      manualByDate: manual,
      calendarYear: _visibleMonth.year,
      month: _visibleMonth.month,
    )
        .then((verdicts) {
      // A later month may have been picked while this was resolving —
      // only the newest request is allowed to paint.
      if (mounted && key == _verdictKey) {
        setState(() => _verdicts = verdicts);
      }
    });

    // Runs in parallel; the calendar paints on the verdicts and the
    // fractions fill in a beat later rather than holding the grid back.
    PeriodAttendanceService.instance
        .monthSummary(
      uid: widget.studentUid,
      studentData: widget.studentData,
      calendarYear: _visibleMonth.year,
      month: _visibleMonth.month,
    )
        .then((summary) {
      if (mounted && key == _verdictKey) {
        setState(() => _periodDays = summary.days);
      }
    }).catchError((Object e) {
      debugPrint('Period summary load failed: $e');
    });
  }

  // ------------------------------------------------------------- marking

  Future<void> _mark(DayVerdict verdict, String status, String reason) async {
    setState(() => _saving = true);

    try {
      await ManualAttendanceService.instance.mark(
        uid: widget.studentUid,
        studentName: _studentName,
        studentData: widget.studentData,
        date: verdict.date,
        status: status,
        markerName: widget.marker.name,
        markerRole: widget.marker.role,
        reason: reason,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                "$_studentName marked ${ManualAttendanceStatus.label(status).toLowerCase()} "
                "for ${AppConfig.dateId(verdict.date)}."),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      _showError("Couldn't save the mark: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Applies one status to every selected day.
  Future<void> _markSelected(String status, String reason) async {
    final verdicts = _verdicts;
    if (verdicts == null || _selectedDays.isEmpty) return;

    final dates = _selectedDays
        .map((d) => verdicts[d]?.date)
        .whereType<DateTime>()
        .toList();

    if (dates.isEmpty) return;

    setState(() => _saving = true);

    try {
      final count = await ManualAttendanceService.instance.markMany(
        uid: widget.studentUid,
        studentData: widget.studentData,
        dates: dates,
        status: status,
        markerName: widget.marker.name,
        markerRole: widget.marker.role,
        reason: reason,
      );

      if (mounted) {
        setState(_selectedDays.clear);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count day${count == 1 ? '' : 's'} marked '
                '${ManualAttendanceStatus.label(status).toLowerCase()} '
                'for $_studentName.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      _showError("Couldn't save those days: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Asks for an optional reason, then applies [status] to the selection.
  Future<void> _confirmBulk(String status) async {
    final reasonController = TextEditingController();
    final count = _selectedDays.length;

    final go = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            title: Text(
              'Mark $count day${count == 1 ? '' : 's'} '
              '${ManualAttendanceStatus.label(status).toLowerCase()}',
              style: AppTextStyles.title,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This replaces whatever those days currently show for '
                  '$_studentName, and notifies them once.',
                  style: AppTextStyles.caption,
                ),
                SizedBox(height: Responsive.h(16)),
                TextField(
                  controller: reasonController,
                  decoration: InputDecoration(
                    labelText: 'Reason (optional)',
                    hintText: 'Medical leave, on duty, scanner down…',
                    hintStyle: AppTextStyles.caption,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Back',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('Mark $count'),
              ),
            ],
          ),
        ) ??
        false;

    if (go) await _markSelected(status, reasonController.text.trim());
  }

  /// Declares [date] a department-wide holiday.
  ///
  /// Distinct from marking a student present: this says the college was
  /// closed, so the day stops counting for everyone rather than being
  /// excused for one person.
  Future<void> _declareHoliday(DateTime date) async {
    final nameController = TextEditingController();
    final reasonController = TextEditingController();
    final dateId = AppConfig.dateId(date);

    final go = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg)),
            title: Text('Holiday on $dateId', style: AppTextStyles.title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This closes the day for the whole department — nobody '
                  'is counted absent for it.',
                  style: AppTextStyles.caption,
                ),
                SizedBox(height: Responsive.h(16)),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Occasion *',
                    hintText: 'Bandh, VC announcement, cyclone…',
                    hintStyle: AppTextStyles.caption,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                ),
                SizedBox(height: Responsive.h(12)),
                TextField(
                  controller: reasonController,
                  decoration: InputDecoration(
                    labelText: 'Reason (shown to students)',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Back',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Declare holiday'),
              ),
            ],
          ),
        ) ??
        false;

    if (!go || nameController.text.trim().isEmpty) return;

    setState(() => _saving = true);

    try {
      await HolidayService.instance.save(Holiday(
        date: dateId,
        name: nameController.text.trim(),
        reason: reasonController.text.trim(),
        type: HolidayType.unscheduled,
      ));

      AttendanceService.instance.clearScheduleCache();

      if (mounted) {
        // Force the month to recompute — the day is no longer a
        // working day and every verdict on it has just changed.
        setState(() {
          _verdicts = null;
          _verdictKey = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$dateId is now a holiday for everyone.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _showError("Couldn't save the holiday: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// One line explaining what kind of closure this is.
  String _holidayNote(DateTime date) {
    final stored = HolidayService.instance.on(date);

    if (stored == null) {
      // Sunday and second Saturday are rules rather than records.
      return 'A standing weekly closure. Attendance is not counted and '
          'cannot be marked.';
    }

    final parts = <String>[
      if (stored.reason.isNotEmpty) stored.reason,
      'Attendance is not counted for this day.',
    ];

    return parts.join('  •  ');
  }

  /// Turns a stored holiday back into a working day.
  ///
  /// The counterpart to declaring one — a date entered by mistake, or a
  /// closure that was called off, shouldn't need a trip to a separate
  /// holidays screen to undo.
  Future<void> _removeHoliday(DateTime date) async {
    final dateId = AppConfig.dateId(date);
    final holiday = HolidayService.instance.on(date);

    final go = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg)),
            title: Text('Make $dateId a working day',
                style: AppTextStyles.title),
            content: Text(
              holiday == null
                  ? 'This reopens the day for the whole department.'
                  : '"${holiday.name}" is currently closing this day for '
                      'the whole department. Removing it means classes '
                      'count again and students can be marked absent.',
              style: AppTextStyles.caption,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Back',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Remove holiday'),
              ),
            ],
          ),
        ) ??
        false;

    if (!go) return;

    setState(() => _saving = true);

    try {
      await HolidayService.instance.delete(dateId);

      // The whole month's verdicts turn on this date being closed, and
      // the timetable cache was filled while it was.
      AttendanceService.instance.clearScheduleCache();

      if (mounted) {
        setState(() {
          _verdicts = null;
          _verdictKey = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$dateId is a working day again.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _showError("Couldn't remove the holiday: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Selects every markable day in the visible month that has a class.
  void _selectAllClassDays() {
    final verdicts = _verdicts;
    if (verdicts == null) return;

    setState(() {
      _selectedDays
        ..clear()
        ..addAll(verdicts.entries
            .where((e) =>
                e.value.status != DayStatus.noClass &&
                e.value.status != DayStatus.upcoming)
            .map((e) => e.key));
    });
  }

  Future<void> _clear(DayVerdict verdict) async {
    setState(() => _saving = true);

    try {
      await ManualAttendanceService.instance.clear(
        uid: widget.studentUid,
        date: verdict.date,
        markerName: widget.marker.name,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Manual mark removed — the check-in record applies "
                "again."),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _showError("Couldn't remove the mark: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Bottom sheet for one day: what it currently resolves to, who set it
  /// if it was set by hand, and the three status buttons.
  void _openDaySheet(DayVerdict verdict, bool canMark) {
    // A holiday always opens, even though it can't be marked — the whole
    // point is to answer "why is this day grey", and a snackbar saying
    // "you can't mark this" answers the wrong question.
    if (!canMark && !verdict.isHoliday) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.marker.isAdmin
              ? "Only days up to today can be marked."
              : "You need admin approval for $_monthLabel before you can "
                  "mark attendance."),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final reasonController =
        TextEditingController(text: verdict.manual?.reason ?? '');

    final summary = _periodDays[verdict.date.day];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: Responsive.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: EdgeInsets.only(bottom: Responsive.h(16)),
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
                Text(
                  "${AppConfig.dayName(verdict.date)}, "
                  "${AppConfig.dateId(verdict.date)}",
                  style: AppTextStyles.title,
                ),
                SizedBox(height: Responsive.h(4)),
                if (!verdict.isHoliday)
                  Text(
                    "$_studentName • Currently "
                    "${_statusText(verdict.status).toLowerCase()}",
                    style: AppTextStyles.caption,
                  ),

                // A holiday isn't an attendance question, so the sheet
                // stops being a marking form and becomes an explanation.
                // Offering Present / Late / Absent on a day the college
                // was shut invites a mark that would be meaningless and
                // then has to be undone.
                if (verdict.isHoliday) ...[
                  SizedBox(height: Responsive.h(10)),
                  Container(
                    width: double.infinity,
                    padding: Responsive.all(14),
                    decoration: BoxDecoration(
                      color: holidayFill.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                          color: holidayFill.withValues(alpha: .35)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.beach_access_rounded,
                            size: Responsive.sp(20), color: holidayFill),
                        SizedBox(width: Responsive.w(10)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                verdict.closureReason ?? 'Holiday',
                                style: AppTextStyles.title.copyWith(
                                  fontSize: Responsive.sp(14),
                                  color: holidayFill,
                                ),
                              ),
                              SizedBox(height: Responsive.h(3)),
                              Text(
                                _holidayNote(verdict.date),
                                style: AppTextStyles.caption,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (summary != null && summary.total > 0) ...[
                  SizedBox(height: Responsive.h(4)),
                  Text(
                    summary.marked == 0
                        ? "${summary.total} class"
                            "${summary.total == 1 ? '' : 'es'} scheduled, "
                            "none registered yet"
                        : "${summary.fraction} classes attended  •  "
                            "${summary.breakdown}",
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (verdict.manual != null) ...[
                  SizedBox(height: Responsive.h(12)),
                  Container(
                    width: double.infinity,
                    padding: Responsive.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: .07),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Marked by hand by "
                          "${verdict.manual!.markedByName} "
                          "(${verdict.manual!.markedByRole.toUpperCase()})",
                          style: AppTextStyles.caption
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (verdict.manual!.reason.isNotEmpty) ...[
                          SizedBox(height: Responsive.h(4)),
                          Text("Reason: ${verdict.manual!.reason}",
                              style: AppTextStyles.caption),
                        ],
                      ],
                    ),
                  ),
                ],
                if (!verdict.isHoliday) ...[
                  SizedBox(height: Responsive.h(16)),
                  TextField(
                    controller: reasonController,
                    decoration: InputDecoration(
                      labelText: "Reason (optional)",
                      hintText: "On duty, medical leave, scanner down…",
                      hintStyle: AppTextStyles.caption,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      contentPadding:
                          Responsive.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  SizedBox(height: Responsive.h(16)),
                  Row(
                    children: [
                      Expanded(
                        child: _StatusButton(
                          label: "Present",
                          color: AppColors.success,
                          selected: verdict.manual?.status ==
                              ManualAttendanceStatus.present,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _mark(verdict, ManualAttendanceStatus.present,
                                reasonController.text.trim());
                          },
                        ),
                      ),
                      SizedBox(width: Responsive.w(10)),
                      Expanded(
                        child: _StatusButton(
                          label: "Late",
                          color: AppColors.warning,
                          selected: verdict.manual?.status ==
                              ManualAttendanceStatus.late,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _mark(verdict, ManualAttendanceStatus.late,
                                reasonController.text.trim());
                          },
                        ),
                      ),
                      SizedBox(width: Responsive.w(10)),
                      Expanded(
                        child: _StatusButton(
                          label: "Absent",
                          color: AppColors.danger,
                          selected: verdict.manual?.status ==
                              ManualAttendanceStatus.absent,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _mark(verdict, ManualAttendanceStatus.absent,
                                reasonController.text.trim());
                          },
                        ),
                      ),
                      // The in-between case the other three can't express.
                      // Present and Absent are whole-day verdicts; Partial
                      // opens the day's timetable so the answer names which
                      // classes were attended rather than implying it.
                      if (widget.marker.isAdmin) ...[
                        SizedBox(width: Responsive.w(10)),
                        Expanded(
                          child: _StatusButton(
                            label: "Partial",
                            color: Colors.amber.shade700,
                            selected: summary != null &&
                                summary.status == DayAttendance.partial,
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _openClassSheet(verdict.date);
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (widget.marker.isAdmin) ...[
                    SizedBox(height: Responsive.h(6)),
                    Text(
                      'Partial opens the day\'s classes — tick the ones '
                      'attended. Tick them all and the day counts as full '
                      'present.',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ],

                if (verdict.manual != null && !verdict.isHoliday) ...[
                  SizedBox(height: Responsive.h(8)),
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _clear(verdict);
                      },
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      label: const Text("Remove manual mark"),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary),
                    ),
                  ),
                ],

                // Declaring a closure, rather than marking one student.
                //
                // A holiday called at short notice — a bandh, a VC's
                // announcement, a cyclone — would otherwise have to be
                // absorbed one student at a time, which is both tedious
                // and wrong: it isn't an attendance correction, the
                // college simply wasn't open. Marking the day here
                // clears it for the whole department at once.
                if (widget.marker.isAdmin) ...[
                  SizedBox(height: Responsive.h(4)),
                  Center(
                    child: HolidayService.instance.on(verdict.date) != null
                        // Only a stored holiday can be lifted. Sunday and
                        // second Saturday are rules, not records — there
                        // is nothing to delete, so no button is offered.
                        ? TextButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              _removeHoliday(verdict.date);
                            },
                            icon: const Icon(Icons.event_available_rounded,
                                size: 18),
                            label: const Text(
                                'Not a holiday — make it a working day'),
                            style: TextButton.styleFrom(
                                foregroundColor: AppColors.danger),
                          )
                        : TextButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              _declareHoliday(verdict.date);
                            },
                            icon: const Icon(Icons.beach_access_rounded,
                                size: 18),
                            label:
                                const Text('Mark this a holiday for everyone'),
                            style: TextButton.styleFrom(
                                foregroundColor: AppColors.primary),
                          ),
                  ),
                ],
                SizedBox(height: Responsive.h(8)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the day's timetable so the admin can tick class by class.
  Future<void> _openClassSheet(DateTime date) async {
    final saved = await DayClassMarkSheet.show(
      context: context,
      studentUid: widget.studentUid,
      studentName: _studentName,
      studentData: widget.studentData,
      date: date,
      markerUid: FirebaseAuth.instance.currentUser?.uid ?? widget.marker.uid,
      markerName: widget.marker.name,
      markerRole: widget.marker.role,
    );

    if (saved && mounted) {
      // Nothing the verdict cache keys on has changed, so nudge it or
      // the day would keep showing its old fraction until the month was
      // switched away and back.
      setState(() {
        _periodRevision++;
        _verdictKey = null;
      });
    }
  }

  // ------------------------------------------------------- CR permission

  Future<void> _requestPermission() async {
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            title: Text("Request Attendance Access",
                style: AppTextStyles.title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Ask the admin to let you mark attendance for Year "
                  "${widget.marker.lockedYear} students for $_monthLabel.",
                  style: AppTextStyles.caption,
                ),
                SizedBox(height: Responsive.h(16)),
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: "Why do you need it?",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("Back",
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text("Send Request"),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      await AttendancePermissionService.instance.request(
        crUid: widget.marker.uid,
        crName: widget.marker.name,
        department: AppConfig.department,
        year: widget.marker.lockedYear ?? _studentYear,
        month: _monthId,
        note: noteController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Request sent. The admin will review it for "
                "$_monthLabel."),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _showError("Couldn't send the request: $e");
    }
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_studentName,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: MaxWidthBody(
        maxWidth: 820,
        child: Column(
          children: [
            if (_saving) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _loadingEvents
                  ? const Center(child: CircularProgressIndicator())
                  : _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  /// The permission gate. Admins short-circuit it; a CR's ability to mark
  /// is re-evaluated every time the visible month changes, which is why
  /// this listens per-month rather than resolving once on open.
  Widget _buildBody() {
    if (widget.marker.isAdmin) {
      return _buildCalendarStream(canMark: true, banner: null);
    }

    return StreamBuilder<AttendancePermission?>(
      stream: AttendancePermissionService.instance.watchGrant(
        crUid: widget.marker.uid,
        month: _monthId,
      ),
      builder: (context, snapshot) {
        final grant = snapshot.data;
        final approved = grant?.isApproved ?? false;

        return _buildCalendarStream(
          canMark: approved,
          banner: _PermissionBanner(
            grant: grant,
            monthLabel: _monthLabel,
            onRequest: _requestPermission,
          ),
        );
      },
    );
  }

  Widget _buildCalendarStream({required bool canMark, Widget? banner}) {
    return StreamBuilder<Map<String, ManualAttendance>>(
      stream: ManualAttendanceService.instance.watchStudent(widget.studentUid),
      builder: (context, manualSnapshot) {
        _refreshVerdicts(manualSnapshot.data ?? const {});

        final verdicts = _verdicts;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            Responsive.w(18),
            Responsive.h(10),
            Responsive.w(18),
            Responsive.h(28),
          ),
          children: [
            _buildStudentHeader(),
            SizedBox(height: Responsive.h(14)),
            ?banner,
            if (banner != null) SizedBox(height: Responsive.h(14)),
            _buildMonthSwitcher(),
            SizedBox(height: Responsive.h(14)),
            if (verdicts == null)
              Padding(
                padding: Responsive.symmetric(vertical: 40),
                child: const Center(child: CircularProgressIndicator()),
              )
            else ...[
              _buildSummary(verdicts),
              SizedBox(height: Responsive.h(14)),
              _buildCalendar(verdicts, canMark),
              if (_selecting && canMark) ...[
                SizedBox(height: Responsive.h(14)),
                _buildSelectionBar(),
              ],
              SizedBox(height: Responsive.h(14)),
              _buildLegend(),
            ],
          ],
        );
      },
    );
  }

  Widget _buildStudentHeader() {
    final regNo = (widget.studentData['regNo'] ?? '--').toString();
    final photoUrl = widget.studentData['profileImageUrl'] as String?;
    final initial =
        _studentName.isNotEmpty ? _studentName[0].toUpperCase() : '?';

    return Container(
      padding: Responsive.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: Responsive.w(26),
            backgroundColor: AppColors.primary.withValues(alpha: .1),
            child: ClipOval(
              child: photoUrl != null && photoUrl.isNotEmpty
                  ? Image.network(
                      photoUrl,
                      width: Responsive.w(52),
                      height: Responsive.w(52),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Text(initial,
                          style: TextStyle(
                            fontSize: Responsive.sp(18),
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          )),
                    )
                  : Text(initial,
                      style: TextStyle(
                        fontSize: Responsive.sp(18),
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      )),
            ),
          ),
          SizedBox(width: Responsive.w(14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_studentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.title),
                SizedBox(height: Responsive.h(4)),
                Text("Reg $regNo  •  Year $_studentYear  •  "
                    "${AppConfig.department}",
                    style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSwitcher() {
    return Container(
      padding: Responsive.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: _canGoBack ? "Previous month" : "Start of semester",
            icon: const Icon(Icons.chevron_left_rounded),
            color: _canGoBack
                ? AppColors.textPrimary
                : AppColors.divider,
            onPressed: _canGoBack ? () => _shiftMonth(-1) : null,
          ),
          Expanded(
            child: Column(
              children: [
                Text(_monthLabel,
                    style: AppTextStyles.title
                        .copyWith(fontSize: Responsive.sp(16))),
                Text(
                  _canGoBack
                      ? "Semester started "
                          "${AttendancePermission.monthLabel(AttendancePermission.monthId(_firstMonth))}"
                      : "Start of the semester",
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _canGoForward ? "Next month" : "Current month",
            icon: const Icon(Icons.chevron_right_rounded),
            color: _canGoForward
                ? AppColors.textPrimary
                : AppColors.divider,
            onPressed: _canGoForward ? () => _shiftMonth(1) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(Map<int, DayVerdict> verdicts) {
    var present = 0;
    var lateCount = 0;
    var absent = 0;
    var manual = 0;

    for (final v in verdicts.values) {
      if (v.isManual) manual++;

      // A late day still counts as present — it's tracked separately so
      // the admin can see punctuality without it dragging the rate down.
      if (v.status == DayStatus.present) {
        present++;
      } else if (v.status == DayStatus.late) {
        present++;
        lateCount++;
      } else if (v.status == DayStatus.absent) {
        absent++;
      }
    }

    final total = present + absent;
    final percent = total == 0 ? 0 : ((present / total) * 100).round();

    return Container(
      padding: Responsive.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _SummaryCell(
                  value: "$present", label: "Present", color: AppColors.success),
              _SummaryCell(
                  value: "$absent", label: "Absent", color: AppColors.danger),
              _SummaryCell(
                  value: "$lateCount",
                  label: "Late",
                  color: AppColors.warning),
              _SummaryCell(
                  value: "$percent%",
                  label: "Rate",
                  color: AppColors.primary),
            ],
          ),
          if (manual > 0) ...[
            SizedBox(height: Responsive.h(12)),
            Row(
              children: [
                Icon(Icons.edit_note_rounded,
                    size: Responsive.sp(15), color: AppColors.primary),
                SizedBox(width: Responsive.w(6)),
                Expanded(
                  child: Text(
                    "$manual day${manual == 1 ? '' : 's'} in this month "
                    "${manual == 1 ? 'was' : 'were'} marked by hand.",
                    style: AppTextStyles.caption,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCalendar(Map<int, DayVerdict> verdicts, bool canMark) {
    final firstWeekdayOffset =
        DateTime(_visibleMonth.year, _visibleMonth.month, 1).weekday % 7;
    final daysInMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final todayId = AppConfig.dateId(DateTime.now());

    return Container(
      padding: Responsive.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            !canMark
                ? "Read-only — you can't mark this month"
                : _selecting
                    ? "Tap days to add or remove them"
                    : "Tap a day to mark it • long-press to select several",
            style: AppTextStyles.caption,
          ),
          SizedBox(height: Responsive.h(14)),
          Row(
            children: const [
              _WeekdayLabel("S"),
              _WeekdayLabel("M"),
              _WeekdayLabel("T"),
              _WeekdayLabel("W"),
              _WeekdayLabel("T"),
              _WeekdayLabel("F"),
              _WeekdayLabel("S"),
            ],
          ),
          SizedBox(height: Responsive.h(10)),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: firstWeekdayOffset + daysInMonth,
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemBuilder: (_, index) {
              if (index < firstWeekdayOffset) return const SizedBox();

              final day = index - firstWeekdayOffset + 1;
              final verdict = verdicts[day];
              if (verdict == null) return const SizedBox();

              final isToday = AppConfig.dateId(verdict.date) == todayId;
              final markable = canMark && verdict.isMarkable;

              return _DayCell(
                day: day,
                verdict: verdict,
                summary: _periodDays[day],
                isToday: isToday,
                // A holiday isn't dimmed. It can't be marked, but it's a
                // deliberate, meaningful state rather than a disabled
                // one, and fading it would read as "not loaded yet".
                enabled: markable || verdict.isHoliday,
                selected: _selectedDays.contains(day),
                onTap: () {
                  if (_selecting) {
                    // In selection mode a tap adds or removes, so days
                    // can be picked out one by one without the sheet
                    // interrupting every time.
                    if (!markable) return;
                    setState(() {
                      if (!_selectedDays.remove(day)) _selectedDays.add(day);
                    });
                    return;
                  }
                  _openDaySheet(verdict, markable);
                },
                onLongPress: markable
                    ? () => setState(() => _selectedDays.add(day))
                    : null,
              );
            },
          ),
        ],
      ),
    );
  }

  /// The bar that appears once days are selected.
  Widget _buildSelectionBar() {
    final count = _selectedDays.length;

    return Container(
      padding: Responsive.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.primary.withValues(alpha: .35)),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline_rounded,
                  size: Responsive.sp(18), color: AppColors.primary),
              SizedBox(width: Responsive.w(8)),
              Expanded(
                child: Text(
                  '$count day${count == 1 ? '' : 's'} selected',
                  style: AppTextStyles.title
                      .copyWith(fontSize: Responsive.sp(14)),
                ),
              ),
              TextButton(
                onPressed: _selectAllClassDays,
                child: const Text('All class days'),
              ),
              TextButton(
                onPressed: () => setState(_selectedDays.clear),
                child: const Text('Cancel',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            ],
          ),
          SizedBox(height: Responsive.h(2)),
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: Responsive.sp(13), color: AppColors.textSecondary),
              SizedBox(width: Responsive.w(6)),
              Expanded(
                child: Text(
                  'Whole days only. To mark part of a day, open that day '
                  'on its own and pick the classes.',
                  style: AppTextStyles.caption,
                ),
              ),
            ],
          ),
          SizedBox(height: Responsive.h(10)),
          Row(
            children: [
              Expanded(
                child: _StatusButton(
                  label: 'Present',
                  color: AppColors.success,
                  selected: false,
                  onTap: () =>
                      _confirmBulk(ManualAttendanceStatus.present),
                ),
              ),
              SizedBox(width: Responsive.w(10)),
              Expanded(
                child: _StatusButton(
                  label: 'Late',
                  color: AppColors.warning,
                  selected: false,
                  onTap: () => _confirmBulk(ManualAttendanceStatus.late),
                ),
              ),
              SizedBox(width: Responsive.w(10)),
              Expanded(
                child: _StatusButton(
                  label: 'Absent',
                  color: AppColors.danger,
                  selected: false,
                  onTap: () => _confirmBulk(ManualAttendanceStatus.absent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: Responsive.w(14),
      runSpacing: Responsive.h(10),
      children: [
        const _LegendDot(color: AppColors.success, label: "All classes"),
        _LegendDot(
            color: attendanceShade(0.5), label: "Part of the day"),
        const _LegendDot(color: AppColors.danger, label: "None attended"),
        const _LegendDot(color: AppColors.warning, label: "Late"),
        const _LegendDot(color: holidayFill, label: "Holiday"),
        const _LegendDot(color: AppColors.divider, label: "No class"),
        const _LegendDot(
            color: AppColors.primary, label: "Dot = marked by hand"),
      ],
    );
  }

  String _statusText(DayStatus status) {
    switch (status) {
      case DayStatus.present:
        return "Present";
      case DayStatus.late:
        return "Present (late)";
      case DayStatus.absent:
        return "Absent";
      case DayStatus.noClass:
        return "No class scheduled";
      case DayStatus.upcoming:
        return "Upcoming";
    }
  }
}

/// Sits above the calendar for CRs only: shows where their request for
/// the visible month stands and gives them the button to raise it.
class _PermissionBanner extends StatelessWidget {
  final AttendancePermission? grant;
  final String monthLabel;
  final VoidCallback onRequest;

  const _PermissionBanner({
    required this.grant,
    required this.monthLabel,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    final status = grant?.status;

    final (Color color, IconData icon, String title, String body) = switch (
        status) {
      PermissionStatus.approved => (
          AppColors.success,
          Icons.verified_rounded,
          "Approved for $monthLabel",
          "You can mark attendance for any day in this month.",
        ),
      PermissionStatus.pending => (
          AppColors.warning,
          Icons.hourglass_top_rounded,
          "Waiting on the admin",
          "Your request for $monthLabel hasn't been decided yet.",
        ),
      PermissionStatus.rejected => (
          AppColors.danger,
          Icons.block_rounded,
          "Request declined",
          grant!.decisionNote.isEmpty
              ? "The admin declined your request for $monthLabel."
              : grant!.decisionNote,
        ),
      PermissionStatus.revoked => (
          AppColors.danger,
          Icons.lock_outline_rounded,
          "Access withdrawn",
          grant!.decisionNote.isEmpty
              ? "Your access for $monthLabel was withdrawn."
              : grant!.decisionNote,
        ),
      _ => (
          AppColors.primary,
          Icons.lock_outline_rounded,
          "Admin approval needed",
          "Marking attendance is an admin action. Request access for "
              "$monthLabel to do it yourself.",
        ),
    };

    final canRequest = status == null ||
        status == PermissionStatus.rejected ||
        status == PermissionStatus.revoked;

    return Container(
      padding: Responsive.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: Responsive.sp(22)),
          SizedBox(width: Responsive.w(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTextStyles.title.copyWith(
                        fontSize: Responsive.sp(14), color: color)),
                SizedBox(height: Responsive.h(4)),
                Text(body, style: AppTextStyles.caption),
                if (canRequest) ...[
                  SizedBox(height: Responsive.h(10)),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onRequest,
                      icon: const Icon(Icons.send_rounded, size: 17),
                      label: const Text("Request Access"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: Responsive.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.xs),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single date in the grid. Colour carries the verdict; the small dot
/// in the corner says a human set it rather than the scanner.
class _DayCell extends StatelessWidget {
  final int day;
  final DayVerdict verdict;

  /// Per-class counts for the day, when any class has been registered.
  final DaySummary? summary;

  final bool isToday;
  final bool enabled;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _DayCell({
    required this.day,
    required this.verdict,
    required this.summary,
    required this.isToday,
    required this.enabled,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final (Color baseFill, Color baseText) = switch (verdict.status) {
      DayStatus.present => (AppColors.success, Colors.white),
      DayStatus.late => (AppColors.warning, Colors.white),
      DayStatus.absent => (AppColors.danger, Colors.white),
      DayStatus.noClass => (AppColors.background, AppColors.textSecondary),
      DayStatus.upcoming => (Colors.transparent, AppColors.textPrimary),
    };

    Color fill = baseFill;
    Color text = baseText;

    // Registers beat the gate, and the shade carries the percentage:
    // red at nothing attended, amber at half, green at all of it. A flat
    // colour would make 1-of-6 and 5-of-6 look alike.
    final marks = (summary != null && summary!.marked > 0) ? summary : null;

    if (marks != null) {
      fill = attendanceShade(marks.ratio);
      text = Colors.white;
    }

    // A closed day is not the same as a day with an empty timetable, and
    // showing both as blank grey is why holidays were invisible here.
    // Dark grey, and it wins over everything below it: if the college
    // was shut, no amount of missing check-in makes it an absence.
    if (verdict.isHoliday) {
      fill = holidayFill;
      text = Colors.white;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Responsive.radius(10)),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Opacity(
          opacity: enabled ? 1 : .65,
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(Responsive.radius(10)),
              // A selected day gets a heavy blue ring, which reads over
              // any of the status fills underneath it.
              border: Border.all(
                color: selected
                    ? AppColors.primary
                    : (isToday ? AppColors.primary : AppColors.divider),
                width: selected ? 3 : (isToday ? 2 : 1),
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "$day",
                        style: TextStyle(
                          color: text,
                          fontWeight: FontWeight.w700,
                          fontSize: Responsive.sp(12),
                        ),
                      ),
                      if (verdict.isHoliday && marks == null)
                        Icon(Icons.beach_access_rounded,
                            size: Responsive.sp(9), color: text)
                      else if (marks != null)
                        Text(
                          marks.fraction,
                          maxLines: 1,
                          style: TextStyle(
                            color: text.withValues(alpha: .85),
                            fontWeight: FontWeight.w600,
                            fontSize: Responsive.sp(8),
                          ),
                        ),
                    ],
                  ),
                ),
                if (verdict.isManual)
                  Positioned(
                    top: 3,
                    right: 3,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: verdict.status == DayStatus.noClass ||
                                verdict.status == DayStatus.upcoming
                            ? AppColors.primary
                            : Colors.white,
                        shape: BoxShape.circle,
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

class _StatusButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _StatusButton({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? color : color.withValues(alpha: .12),
        foregroundColor: selected ? Colors.white : color,
        elevation: 0,
        padding: Responsive.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      child: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w700, fontSize: Responsive.sp(13))),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _SummaryCell({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
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

class _WeekdayLabel extends StatelessWidget {
  final String day;

  const _WeekdayLabel(this.day);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          day,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            fontSize: Responsive.sp(11),
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: Responsive.w(12),
          height: Responsive.w(12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(Responsive.radius(4)),
          ),
        ),
        SizedBox(width: Responsive.w(6)),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }
}
