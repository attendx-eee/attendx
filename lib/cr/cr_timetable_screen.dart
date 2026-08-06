import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../admin/models/period_model.dart';
import '../admin/models/room_model.dart';
import '../admin/models/subject_model.dart';
import '../admin/services/master_data_service.dart';
import '../admin/services/timetable_service.dart';
import '../core/constants/app_config.dart';
import '../core/responsive/responsive.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radius.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/primary_card.dart';
import '../core/widgets/section_header.dart';
import '../core/widgets/status_chip.dart';
import '../timetable/models/timetable_override_model.dart';
import '../timetable/services/timetable_override_service.dart';

/// Where a period sits relative to the CR's edit window.
enum _PeriodPhase {
  /// Not started, or within 15 minutes of starting — still editable.
  upcoming,

  /// Started more than 15 minutes ago and not yet finished. Locked.
  ongoing,

  /// Finished, or on a past date. Locked.
  completed,
}

/// CR-only screen: temporarily adjust the timetable for a specific date
/// (cancel a class, set a replacement, change the room). Every change is
/// broadcast instantly to all students of the CR's year.
class CrTimetableScreen extends StatefulWidget {
  final Map<String, dynamic> studentData;

  const CrTimetableScreen({super.key, required this.studentData});

  @override
  State<CrTimetableScreen> createState() => _CrTimetableScreenState();
}

class _CrTimetableScreenState extends State<CrTimetableScreen> {
  late final String _department = AppConfig.departmentOf(widget.studentData);
  late final int _year = AppConfig.yearOf(widget.studentData);

  late DateTime _selectedDate;
  List<PeriodModel> _basePeriods = [];
  bool _loading = true;
  bool _saving = false;

  /// Master data for the replacement dialogs: this year's theory
  /// subjects, all rooms, and each subject's fixed faculty (looked up
  /// from the year's timetable — one faculty per subject per year).
  List<SubjectModel> _subjects = [];
  List<RoomModel> _rooms = [];
  final Map<String, ({String id, String name})> _subjectFaculty = {};

  /// Next 7 college days — Sundays are skipped entirely.
  late final List<DateTime> _upcomingDates = () {
    final dates = <DateTime>[];
    var day = DateTime.now();
    while (dates.length < 7) {
      if (day.weekday != DateTime.sunday) {
        dates.add(DateTime(day.year, day.month, day.day));
      }
      day = day.add(const Duration(days: 1));
    }
    return dates;
  }();

  /// Repaints the list every minute so a period flips to GOING ON on its
  /// own. Without this the lock would only appear the next time some
  /// other event happened to rebuild the screen, and a CR staring at the
  /// page at 11:14 would still see an editable card at 11:20.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _selectedDate = _upcomingDates.first;
    _loadBaseSchedule();
    _loadMasterData();

    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _dateId => AppConfig.dateId(_selectedDate);
  String get _dayName => AppConfig.dayName(_selectedDate);

  /// How far along a period is on the selected date.
  ///
  /// The edit window closes 15 minutes after the class starts, not when
  /// it ends: a cancellation or room change is only worth broadcasting
  /// while students can still act on it, and once everyone is seated the
  /// "temporary update" would be rewriting history rather than warning
  /// anyone. Past dates are fully locked; future dates are wide open.
  _PeriodPhase _phaseOf(PeriodModel period) {
    final now = DateTime.now();
    final selectedId = AppConfig.dateId(_selectedDate);
    final todayId = AppConfig.dateId(now);

    if (selectedId != todayId) {
      // _upcomingDates only ever holds today onwards, but guard anyway so
      // a stale screen left open overnight can't edit yesterday.
      return _selectedDate.isBefore(DateTime(now.year, now.month, now.day))
          ? _PeriodPhase.completed
          : _PeriodPhase.upcoming;
    }

    final end = AppConfig.timeOn(_selectedDate, period.endTime);
    if (end != null && now.isAfter(end)) return _PeriodPhase.completed;

    final lock =
        AppConfig.overrideLockTime(_selectedDate, period.startTime);
    if (lock != null && now.isAfter(lock)) return _PeriodPhase.ongoing;

    return _PeriodPhase.upcoming;
  }

  /// "11:15" — the cutoff for this period, for messages and the card hint.
  String _lockLabel(PeriodModel period) {
    final lock =
        AppConfig.overrideLockTime(_selectedDate, period.startTime);
    if (lock == null) return period.startTime;
    return "${lock.hour.toString().padLeft(2, '0')}:"
        "${lock.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _loadMasterData() async {
    try {
      final subjects =
          await MasterDataService.instance.getSubjectsByYear(_year).first;
      final rooms = await MasterDataService.instance.getRooms().first;

      // Map each subject to its fixed faculty from the year's timetable.
      for (final day in AppConfig.weekDays) {
        final periods = await TimetableService.instance.getDaySchedule(
          department: _department,
          academicYear: AppConfig.academicYear,
          year: _year,
          day: day,
        );
        for (final p in periods) {
          if (p.subject.isNotEmpty && p.facultyName.isNotEmpty) {
            _subjectFaculty.putIfAbsent(
                p.subject, () => (id: p.facultyId, name: p.facultyName));
          }
        }
      }

      if (mounted) {
        setState(() {
          _subjects = subjects;
          _rooms = rooms.where((r) => r.active).toList();
        });
      }
    } catch (e) {
      debugPrint('CR master data load failed: $e');
    }
  }

  Future<void> _loadBaseSchedule() async {
    setState(() => _loading = true);

    List<PeriodModel> periods = [];

    if (_dayName != 'Sunday') {
      try {
        periods = await TimetableService.instance.getDaySchedule(
          department: _department,
          academicYear: AppConfig.academicYear,
          year: _year,
          day: _dayName,
        );
      } catch (e) {
        debugPrint('CR schedule load failed: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _basePeriods = periods;
      _loading = false;
    });
  }

  Future<void> _apply(TimetableOverride override) async {
    setState(() => _saving = true);

    try {
      await TimetableOverrideService.instance.applyOverride(override);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                "${OverrideType.label(override.type)} saved. Year $_year students notified."),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to save change: $e"),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _revert(TimetableOverride override) async {
    setState(() => _saving = true);

    try {
      await TimetableOverrideService.instance.revertOverride(override);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Reverted to regular timetable. Students notified."),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  TimetableOverride _draft({
    required PeriodModel period,
    required String type,
    String newSubject = '',
    String newFacultyName = '',
    String newRoom = '',
    String note = '',
  }) {
    final user = FirebaseAuth.instance.currentUser;

    return TimetableOverride(
      id: '',
      department: _department,
      academicYear: AppConfig.academicYear,
      year: _year,
      date: _dateId,
      day: _dayName,
      periodNo: period.periodNo,
      startTime: period.startTime,
      endTime: period.endTime,
      type: type,
      originalSubject: period.subject,
      originalFacultyName: period.facultyName,
      originalRoom: period.room,
      newSubject: newSubject,
      newFacultyName: newFacultyName,
      newRoom: newRoom,
      batch: period.batch,
      note: note,
      createdBy: user?.uid ?? '',
      createdByName: widget.studentData['name'] ?? 'CR',
    );
  }

  // ---------------------------------------------------------------- dialogs

  void _showActions(PeriodModel period, TimetableOverride? existing) {
    final phase = _phaseOf(period);

    // Once a class is under way (or done), it's read-only.
    if (phase != _PeriodPhase.upcoming) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            phase == _PeriodPhase.ongoing
                ? "${period.subject} started at ${period.startTime} and is "
                    "going on — changes were only possible until "
                    "${_lockLabel(period)}."
                : "This class is already over — it can't be changed.",
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: Responsive.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.only(bottom: Responsive.h(14)),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              Text(period.subject, style: AppTextStyles.title),
              Text(
                "${period.startTime} - ${period.endTime}  •  $_dayName, $_dateId",
                style: AppTextStyles.caption,
              ),
              SizedBox(height: Responsive.h(12)),
              _actionTile(
                icon: Icons.cancel_outlined,
                color: AppColors.danger,
                label: "Cancel Class",
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showCancelDialog(period);
                },
              ),
              _actionTile(
                icon: Icons.swap_horiz_rounded,
                color: AppColors.primary,
                label: "Replacement Class",
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showReplacementDialog(period);
                },
              ),
              _actionTile(
                icon: Icons.meeting_room_outlined,
                color: AppColors.warning,
                label: "Change Classroom",
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showRoomChangeDialog(period);
                },
              ),
              if (existing != null)
                _actionTile(
                  icon: Icons.undo_rounded,
                  color: AppColors.textSecondary,
                  label:
                      "Revert ${OverrideType.label(existing.type)} (back to normal)",
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _revert(existing);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      leading: Container(
        padding: Responsive.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        label,
        style: AppTextStyles.body.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
    );
  }

  void _showCancelDialog(PeriodModel period) {
    final noteController = TextEditingController();

    _showFormDialog(
      title: "Cancel Class",
      subtitle:
          "${period.subject} (${period.startTime} - ${period.endTime}) on $_dateId",
      confirmLabel: "Cancel Class & Notify",
      confirmColor: AppColors.danger,
      fields: [
        _field(noteController, "Reason / note (optional)"),
      ],
      onConfirm: () {
        _apply(_draft(
          period: period,
          type: OverrideType.cancelled,
          note: noteController.text.trim(),
        ));
        return true;
      },
    );
  }

  static const String _otherOption = '__other__';

  /// Replacement: pick from this year's subjects (faculty comes fixed
  /// with the subject) or enter a brand-new subject; room from the room
  /// list or a new one.
  void _showReplacementDialog(PeriodModel period) {
    String? selectedSubject;
    String? selectedRoom = period.room.isEmpty ? null : period.room;
    final customSubjectController = TextEditingController();
    final customFacultyController = TextEditingController();
    final customRoomController = TextEditingController();
    final noteController = TextEditingController();

    final subjectNames = _subjects.map((s) => s.name).toSet().toList();
    final roomNumbers = _rooms.map((r) => r.roomNumber).toSet().toList();
    if (selectedRoom != null && !roomNumbers.contains(selectedRoom)) {
      roomNumbers.insert(0, selectedRoom);
    }

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final isOtherSubject = selectedSubject == _otherOption;
          final isOtherRoom = selectedRoom == _otherOption;

          // Faculty is fixed per subject for the whole year.
          final autoFaculty = selectedSubject != null && !isOtherSubject
              ? (_subjectFaculty[selectedSubject]?.name ?? '')
              : '';

          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            title: Text("Replacement Class", style: AppTextStyles.title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Replaces ${period.subject} (${period.startTime} - ${period.endTime}) on $_dateId",
                    style: AppTextStyles.caption,
                  ),
                  SizedBox(height: Responsive.h(16)),

                  // ------------------------------ subject dropdown
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: selectedSubject,
                    decoration: const InputDecoration(
                      labelText: 'New subject *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.book_outlined),
                    ),
                    items: [
                      ...subjectNames.map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(s,
                                style: const TextStyle(fontSize: 14)),
                          )),
                      const DropdownMenuItem(
                        value: _otherOption,
                        child: Text('Other (new subject)',
                            style: TextStyle(fontSize: 14)),
                      ),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => selectedSubject = v),
                  ),
                  SizedBox(height: Responsive.h(12)),

                  if (isOtherSubject) ...[
                    _field(customSubjectController, "New subject name *"),
                    _field(customFacultyController, "Faculty name"),
                  ] else if (selectedSubject != null) ...[
                    // Faculty is bound to the subject — shown, not editable.
                    TextField(
                      enabled: false,
                      controller: TextEditingController(
                          text: autoFaculty.isEmpty
                              ? 'Faculty not found in timetable'
                              : autoFaculty),
                      decoration: const InputDecoration(
                        labelText: 'Faculty (fixed for this subject)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    SizedBox(height: Responsive.h(12)),
                  ],

                  // --------------------------------- room dropdown
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: selectedRoom,
                    decoration: const InputDecoration(
                      labelText: 'Room',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.meeting_room_outlined),
                    ),
                    items: [
                      ...roomNumbers.map((r) => DropdownMenuItem(
                            value: r,
                            child: Text('Room $r',
                                style: const TextStyle(fontSize: 14)),
                          )),
                      const DropdownMenuItem(
                        value: _otherOption,
                        child: Text('Other (new room)',
                            style: TextStyle(fontSize: 14)),
                      ),
                    ],
                    onChanged: (v) => setDialogState(() => selectedRoom = v),
                  ),
                  SizedBox(height: Responsive.h(12)),

                  if (isOtherRoom)
                    _field(customRoomController, "New room *"),

                  _field(noteController, "Note (optional)"),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
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
                onPressed: () {
                  final subject = isOtherSubject
                      ? customSubjectController.text.trim()
                      : (selectedSubject ?? '');
                  if (subject.isEmpty || subject == _otherOption) return;

                  final faculty = isOtherSubject
                      ? customFacultyController.text.trim()
                      : autoFaculty;

                  final room = isOtherRoom
                      ? customRoomController.text.trim()
                      : (selectedRoom ?? period.room);
                  if (isOtherRoom && room.isEmpty) return;

                  _apply(_draft(
                    period: period,
                    type: OverrideType.replacement,
                    newSubject: subject,
                    newFacultyName: faculty,
                    newRoom: room,
                    note: noteController.text.trim(),
                  ));
                  Navigator.pop(dialogContext);
                },
                child: const Text("Save & Notify"),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Room change: pick from the room list, or enter a new room.
  void _showRoomChangeDialog(PeriodModel period) {
    String? selectedRoom;
    final customRoomController = TextEditingController();
    final noteController = TextEditingController();

    final roomNumbers = _rooms
        .map((r) => r.roomNumber)
        .where((r) => r != period.room) // moving TO a different room
        .toSet()
        .toList();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final isOtherRoom = selectedRoom == _otherOption;

          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            title: Text("Change Classroom", style: AppTextStyles.title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${period.subject} (${period.startTime}) — currently in ${period.room}",
                    style: AppTextStyles.caption,
                  ),
                  SizedBox(height: Responsive.h(16)),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: selectedRoom,
                    decoration: const InputDecoration(
                      labelText: 'New room *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.meeting_room_outlined),
                    ),
                    items: [
                      ...roomNumbers.map((r) => DropdownMenuItem(
                            value: r,
                            child: Text('Room $r',
                                style: const TextStyle(fontSize: 14)),
                          )),
                      const DropdownMenuItem(
                        value: _otherOption,
                        child: Text('Other (new room)',
                            style: TextStyle(fontSize: 14)),
                      ),
                    ],
                    onChanged: (v) => setDialogState(() => selectedRoom = v),
                  ),
                  SizedBox(height: Responsive.h(12)),
                  if (isOtherRoom)
                    _field(customRoomController, "New room name/number *"),
                  _field(noteController, "Note (optional)"),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text("Back",
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                ),
                onPressed: () {
                  final room = isOtherRoom
                      ? customRoomController.text.trim()
                      : (selectedRoom ?? '');
                  if (room.isEmpty || room == _otherOption) return;

                  _apply(_draft(
                    period: period,
                    type: OverrideType.roomChange,
                    newRoom: room,
                    note: noteController.text.trim(),
                  ));
                  Navigator.pop(dialogContext);
                },
                child: const Text("Save & Notify"),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return Padding(
      padding: EdgeInsets.only(bottom: Responsive.h(12)),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          contentPadding:
              Responsive.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  void _showFormDialog({
    required String title,
    required String subtitle,
    required String confirmLabel,
    required Color confirmColor,
    required List<Widget> fields,
    required bool Function() onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text(title, style: AppTextStyles.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle, style: AppTextStyles.caption),
              SizedBox(height: Responsive.h(16)),
              ...fields,
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Back",
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
            ),
            onPressed: () {
              if (onConfirm()) Navigator.pop(dialogContext);
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("CR Timetable Tools",
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildDateStrip(),
          if (_saving) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildScheduleList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDateStrip() {
    return Container(
      color: AppColors.primary,
      padding: EdgeInsets.only(bottom: Responsive.h(14)),
      child: SizedBox(
        height: Responsive.h(72),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: Responsive.symmetric(horizontal: 16),
          itemCount: _upcomingDates.length,
          separatorBuilder: (_, _) => SizedBox(width: Responsive.w(8)),
          itemBuilder: (context, index) {
            final date = _upcomingDates[index];
            final selected = AppConfig.dateId(date) == _dateId;

            return GestureDetector(
              onTap: () {
                setState(() => _selectedDate = date);
                _loadBaseSchedule();
              },
              child: Container(
                width: Responsive.w(58),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      AppConfig.dayName(date).substring(0, 3).toUpperCase(),
                      style: TextStyle(
                        fontSize: Responsive.sp(11),
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? AppColors.primary
                            : Colors.white.withValues(alpha: .85),
                      ),
                    ),
                    SizedBox(height: Responsive.h(4)),
                    Text(
                      "${date.day}",
                      style: TextStyle(
                        fontSize: Responsive.sp(18),
                        fontWeight: FontWeight.w700,
                        color: selected ? AppColors.textPrimary : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildScheduleList() {
    if (_dayName == 'Sunday') {
      return Center(
        child: Text("No classes on Sunday", style: AppTextStyles.body),
      );
    }

    return StreamBuilder<List<TimetableOverride>>(
      stream: TimetableOverrideService.instance.watchForDate(
        department: _department,
        academicYear: AppConfig.academicYear,
        year: _year,
        date: _dateId,
      ),
      builder: (context, snapshot) {
        final overrides = {
          for (final o in snapshot.data ?? <TimetableOverride>[])
            o.periodNo: o
        };

        final periods = _basePeriods
            .where((p) => !p.isFree && p.subject.isNotEmpty)
            .toList();

        if (periods.isEmpty) {
          return Center(
            child: Text("No classes scheduled for $_dayName",
                style: AppTextStyles.body),
          );
        }

        return ListView(
          padding: Responsive.all(20),
          children: [
            SectionHeader(
              title: "$_dayName Schedule",
              subtitle:
                  "Year $_year • $_department • Tap a class to adjust it",
            ),
            SizedBox(height: Responsive.h(16)),
            ...periods.map(
              (period) => Padding(
                padding: EdgeInsets.only(bottom: Responsive.h(14)),
                child: _PeriodCard(
                  period: period,
                  overRide: overrides[period.periodNo],
                  phase: _phaseOf(period),
                  lockLabel: _lockLabel(period),
                  onTap: () =>
                      _showActions(period, overrides[period.periodNo]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PeriodCard extends StatelessWidget {
  final PeriodModel period;
  final TimetableOverride? overRide;
  final _PeriodPhase phase;

  /// "11:15" — when this period's edit window closed.
  final String lockLabel;

  final VoidCallback onTap;

  const _PeriodCard({
    required this.period,
    required this.overRide,
    required this.phase,
    required this.lockLabel,
    required this.onTap,
  });

  bool get _locked => phase != _PeriodPhase.upcoming;

  ChipState get _chipState {
    switch (overRide?.type) {
      case OverrideType.cancelled:
        return ChipState.danger;
      case OverrideType.replacement:
        return ChipState.info;
      case OverrideType.roomChange:
        return ChipState.warning;
      default:
        return ChipState.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cancelled = overRide?.type == OverrideType.cancelled;
    final replaced = overRide?.type == OverrideType.replacement;
    final roomChanged = overRide?.type == OverrideType.roomChange;

    final subject = replaced ? overRide!.newSubject : period.subject;
    final faculty = replaced && overRide!.newFacultyName.isNotEmpty
        ? overRide!.newFacultyName
        : period.facultyName;
    final room = (replaced && overRide!.newRoom.isNotEmpty) || roomChanged
        ? overRide!.newRoom
        : period.room;

    return Opacity(
      opacity: _locked ? 0.55 : 1,
      child: PrimaryCard(
      onTap: onTap,
      child: Row(
        children: [
          Column(
            children: [
              Text(period.startTime, style: AppTextStyles.body),
              SizedBox(height: Responsive.h(4)),
              Text(period.endTime, style: AppTextStyles.caption),
            ],
          ),
          SizedBox(width: Responsive.w(16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject,
                  style: AppTextStyles.title.copyWith(
                    decoration:
                        cancelled ? TextDecoration.lineThrough : null,
                    color: cancelled
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
                if (replaced)
                  Text("was: ${period.subject}",
                      style: AppTextStyles.caption.copyWith(
                        decoration: TextDecoration.lineThrough,
                      )),
                SizedBox(height: Responsive.h(4)),
                Text(faculty, style: AppTextStyles.body),
                Text(
                  "${roomChanged ? "$room (was ${period.room})" : room}"
                  "${period.batch.isEmpty ? '' : '  •  Batch ${period.batch}'}",
                  style: AppTextStyles.caption,
                ),
                if ((overRide?.note ?? '').isNotEmpty) ...[
                  SizedBox(height: Responsive.h(4)),
                  Text("Note: ${overRide!.note}",
                      style: AppTextStyles.caption
                          .copyWith(fontStyle: FontStyle.italic)),
                ],
                // Spell the cutoff out on the card itself, so a CR sees
                // the deadline before they've missed it rather than only
                // discovering it in a snackbar afterwards.
                if (phase == _PeriodPhase.ongoing) ...[
                  SizedBox(height: Responsive.h(4)),
                  Text("Locked — changes closed at $lockLabel",
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.warning)),
                ],
              ],
            ),
          ),
          SizedBox(width: Responsive.w(8)),
          if (phase == _PeriodPhase.ongoing)
            const StatusChip(
              text: "GOING ON",
              state: ChipState.warning,
            )
          else if (phase == _PeriodPhase.completed)
            const StatusChip(
              text: "COMPLETED",
              state: ChipState.success,
            )
          else if (overRide != null)
            StatusChip(
              text: OverrideType.label(overRide!.type),
              state: _chipState,
            )
          else
            const Icon(Icons.edit_calendar_outlined,
                color: AppColors.textSecondary, size: 20),
        ],
      ),
      ),
    );
  }
}
