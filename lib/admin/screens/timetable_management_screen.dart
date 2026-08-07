import 'package:flutter/material.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';
import '../models/faculty_model.dart';
import '../models/lab_model.dart';
import '../models/period_model.dart';
import '../models/room_model.dart';
import '../models/subject_model.dart';
import '../models/time_slot_model.dart';
import '../services/batch_service.dart';
import '../services/master_data_service.dart';
import '../services/timetable_service.dart';
import '../import/import_entry.dart';
import '../widgets/add_time_slot_dialog.dart';
import '../widgets/add_subject_dialog.dart';
import '../widgets/add_lab_dialog.dart';
import '../widgets/add_faculty_dialog.dart';
import '../widgets/add_room_dialog.dart';

/// Theory and Lab periods are color-coded so a glance at the grid tells
/// you which is which — the same "color-coded classes" convention used
/// by every modern timetable app.
Color _classTypeColor(String classType) =>
    classType == 'Lab' ? AppColors.teal : AppColors.primary;

/// Time slots are stored as 24-hour "H:mm" strings (e.g. "14:30") — this
/// renders them the way people actually read a timetable: "2:30 PM".
String _to12Hour(String time24) {
  final parts = time24.split(':');
  if (parts.length != 2) return time24;

  final hour24 = int.tryParse(parts[0]);
  final minute = parts[1].padLeft(2, '0');
  if (hour24 == null) return time24;

  final period = hour24 >= 12 ? 'PM' : 'AM';
  var hour12 = hour24 % 12;
  if (hour12 == 0) hour12 = 12;

  return '$hour12:$minute $period';
}

InputDecoration _fieldDecoration({
  required String label,
  required IconData icon,
}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 20, color: AppColors.primary),
    filled: true,
    fillColor: AppColors.background,
    labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
    contentPadding:
        const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: const BorderSide(color: AppColors.divider),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: const BorderSide(color: AppColors.divider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
    ),
  );
}

class TimetableManagementScreen extends StatefulWidget {
  const TimetableManagementScreen({super.key});

  @override
  State<TimetableManagementScreen> createState() => _TimetableManagementScreenState();
}

class _TimetableManagementScreenState extends State<TimetableManagementScreen> {
  static const String _department = 'EEE';
  static const String _academicYear = '2026-2027';

  int _selectedYear = 1;
  String _selectedDay = 'Monday';

  final List<String> days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  late Stream<List<SubjectModel>> subjectsStream;
  late Stream<List<LabModel>> labsStream;
  late Stream<List<FacultyModel>> facultyStream;
  late Stream<List<RoomModel>> roomsStream;
  late Stream<List<TimeSlotModel>> slotsStream;

  TimeSlotModel? _selectedSlot;
  SubjectModel? _selectedSubject;
  LabModel? _selectedLab;
  FacultyModel? _selectedFaculty;
  RoomModel? _selectedRoom;
  bool _isLabClass = false;

  /// Lab batch selection ('' = whole class) + configured count per year.
  String _selectedBatch = '';
  int _batchCountForYear = 1;

  Map<String, List<PeriodModel>> _weekPeriods = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    subjectsStream = MasterDataService.instance.getSubjectsByYear(_selectedYear);
    labsStream = MasterDataService.instance.getLabsByYear(_selectedYear);
    facultyStream = MasterDataService.instance.getFaculty();
    roomsStream = MasterDataService.instance.getRooms();
    slotsStream = MasterDataService.instance.getTimeSlots();
    _loadTimetableData();
    _loadBatchCount();
  }

  void _updateStreams() {
    setState(() {
      subjectsStream = MasterDataService.instance.getSubjectsByYear(_selectedYear);
      labsStream = MasterDataService.instance.getLabsByYear(_selectedYear);
    });
    _loadBatchCount();
  }

  Future<void> _loadBatchCount() async {
    final count = await BatchService.instance.batchCount(
      department: _department,
      year: _selectedYear,
    );
    if (mounted) {
      setState(() {
        _batchCountForYear = count;
        _selectedBatch = '';
      });
    }
  }

  Future<void> _loadTimetableData() async {
    await _loadWeekTimetable();
  }

  Future<void> _loadWeekTimetable() async {
    final weekPeriods = <String, List<PeriodModel>>{};

    for (final day in days) {
      try {
        final periods = await TimetableService.instance.getDaySchedule(
          department: _department,
          academicYear: _academicYear,
          year: _selectedYear,
          day: day,
        );
        weekPeriods[day] = periods;
      } catch (_) {
        weekPeriods[day] = [];
      }
    }

    if (mounted) {
      setState(() => _weekPeriods = weekPeriods);
    }
  }

  Future<void> _refreshTimetable() async {
    _updateStreams();
    await _loadTimetableData();
  }

  /// Matches a period to EXACTLY its own slot: slot number, start time
  /// AND end time must all agree. Coinciding slots (e.g. 9:00-10:40 and
  /// 9:00-11:00) can never both claim the same period.
  PeriodModel? _getPeriodForDayAndSlot(String day, TimeSlotModel slot) {
    for (final period in _weekPeriods[day] ?? const <PeriodModel>[]) {
      if (period.periodNo != slot.slotNumber) continue;

      if (period.startTime.isNotEmpty &&
          slot.startTime.isNotEmpty &&
          period.startTime != slot.startTime) {
        continue;
      }

      if (period.endTime.isNotEmpty &&
          slot.endTime.isNotEmpty &&
          period.endTime != slot.endTime) {
        continue;
      }

      return period;
    }
    return null;
  }

  /// Time slots exist for all four years, but an individual year's
  /// timetable rarely uses them all — only show slots that actually have
  /// a theory/lab scheduled somewhere in this year's week.
  List<TimeSlotModel> _slotsUsedThisWeek(List<TimeSlotModel> slots) {
    return slots.where((slot) {
      return days.any((day) {
        final period = _getPeriodForDayAndSlot(day, slot);
        return period != null && !period.isFree && period.subject.isNotEmpty;
      });
    }).toList();
  }

  Future<void> _addPeriod() async {
    final hasRequiredSelection = _selectedSlot != null &&
        _selectedFaculty != null &&
        _selectedRoom != null &&
        (_isLabClass ? _selectedLab != null : _selectedSubject != null);

    if (!hasRequiredSelection) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a slot, class, faculty and room first.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final period = PeriodModel(
        periodNo: _selectedSlot!.slotNumber,
        startTime: _selectedSlot!.startTime,
        endTime: _selectedSlot!.endTime,
        subject: _isLabClass ? (_selectedLab?.name ?? '') : (_selectedSubject?.name ?? ''),
        facultyId: _selectedFaculty!.id,
        facultyName: _selectedFaculty!.name,
        room: _selectedRoom!.roomNumber,
        classType: _isLabClass ? 'Lab' : 'Theory',
        batch: _isLabClass ? _selectedBatch : '',
        isFree: false,
        status: 'draft',
      );

      await TimetableService.instance.updatePeriod(
        department: _department,
        academicYear: _academicYear,
        year: _selectedYear,
        day: _selectedDay,
        period: period,
      );

      await _loadTimetableData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Period ${period.periodNo} added to $_selectedDay')),
        );
      }

      if (mounted) {
        setState(() {
          _selectedSlot = null;
          _selectedSubject = null;
          _selectedLab = null;
          _selectedFaculty = null;
          _selectedRoom = null;
          _isLabClass = false;
          _selectedBatch = '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add period: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deletePeriod(String day, int periodNo) async {
    setState(() => _isSaving = true);

    try {
      await TimetableService.instance.deletePeriod(
        department: _department,
        academicYear: _academicYear,
        year: _selectedYear,
        day: day,
        periodNo: periodNo,
      );
      await _loadTimetableData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove period: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Long-press on a period card triggers this — asks for confirmation
  /// before removing a scheduled class, since a stray long-press
  /// shouldn't be able to silently wipe a period off the timetable.
  Future<void> _confirmDeletePeriod(String day, PeriodModel period) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        icon: const Icon(Icons.delete_outline_rounded,
            color: AppColors.danger, size: 34),
        title: const Text('Remove this period?', textAlign: TextAlign.center),
        content: Text(
          '${period.subject.isEmpty ? period.classType : period.subject} on '
          '$day will be removed from the timetable.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deletePeriod(day, period.periodNo);
    }
  }

  Future<void> _showEditPeriodDialog(String day, PeriodModel period) async {
    bool isLab = period.classType == 'Lab';
    SubjectModel? selectedSubject;
    LabModel? selectedLab;
    FacultyModel? selectedFaculty;
    RoomModel? selectedRoom;

    // Why the last Save attempt didn't go through.
    //
    // This used to be a SnackBar raised from inside the dialog, which
    // meant it rendered on the Scaffold *behind* the modal barrier —
    // invisible. Pressing Save on an incomplete period therefore looked
    // like the button did nothing at all, which is exactly what it
    // looked like from the outside.
    String? saveError;

    // Whether the dropdowns had anything to offer. An empty Master Data
    // set produces empty dropdowns and an unsatisfiable form, and the
    // student deserves to be told that rather than left guessing.
    var hadOptions = true;

    // Fresh streams for this dialog — deliberately NOT the shared
    // `subjectsStream` / `facultyStream` / ... fields.
    //
    // Those are already subscribed by _buildAddPeriodForm, which is part
    // of the main build. Firestore's snapshots() is single-subscription,
    // so listening a second time throws "Stream has already been
    // listened to", every StreamBuilder here lands in its error state,
    // and `snapshot.data ?? []` quietly turns that into empty dropdowns.
    //
    // Nothing looked broken; the form simply had nothing to offer and no
    // way to say why.
    final dialogSubjects =
        MasterDataService.instance.getSubjectsByYear(_selectedYear);
    final dialogLabs = MasterDataService.instance.getLabsByYear(_selectedYear);
    final dialogFaculty = MasterDataService.instance.getFaculty();
    final dialogRooms = MasterDataService.instance.getRooms();

    await showDialog(
      context: context,
      builder: (context) {
        // The StatefulBuilder wraps the whole dialog, not just its
        // content: the Save button lives in `actions` and needs to be
        // able to redraw the error message it sets.
        return StatefulBuilder(
          builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg)),
          icon: Icon(
            period.classType == 'Lab'
                ? Icons.science_rounded
                : Icons.menu_book_rounded,
            color: _classTypeColor(period.classType),
            size: 34,
          ),
          title: Text('Edit ${period.classType} Period',
              textAlign: TextAlign.center,
              style: AppTextStyles.title),
          content: SizedBox(
            width: 360,
            child: Builder(
              builder: (context) {
                return StreamBuilder<List<SubjectModel>>(
                  stream: dialogSubjects,
                  builder: (context, subjectsSnapshot) {
                    final subjects = subjectsSnapshot.data ?? [];

                    return StreamBuilder<List<LabModel>>(
                      stream: dialogLabs,
                      builder: (context, labsSnapshot) {
                        final labs = labsSnapshot.data ?? [];

                        return StreamBuilder<List<FacultyModel>>(
                          stream: dialogFaculty,
                          builder: (context, facultySnapshot) {
                            final faculty = facultySnapshot.data ?? [];

                            return StreamBuilder<List<RoomModel>>(
                              stream: dialogRooms,
                              builder: (context, roomsSnapshot) {
                                final rooms = roomsSnapshot.data ?? [];

                                selectedSubject ??= subjects.where((item) => item.name == period.subject).isNotEmpty
                                    ? subjects.firstWhere((item) => item.name == period.subject)
                                    : null;
                                selectedLab ??= labs.where((item) => item.name == period.subject).isNotEmpty
                                    ? labs.firstWhere((item) => item.name == period.subject)
                                    : null;
                                selectedFaculty ??= faculty.where((item) => item.id == period.facultyId || item.name == period.facultyName).isNotEmpty
                                    ? faculty.firstWhere((item) => item.id == period.facultyId || item.name == period.facultyName)
                                    : null;
                                selectedRoom ??= rooms.where((item) => item.roomNumber == period.room).isNotEmpty
                                    ? rooms.firstWhere((item) => item.roomNumber == period.room)
                                    : null;

                                hadOptions = faculty.isNotEmpty &&
                                    rooms.isNotEmpty &&
                                    (isLab ? labs.isNotEmpty : subjects.isNotEmpty);

                                // An empty dropdown looks identical
                                // whether the list is genuinely empty or
                                // the read was refused — and the second
                                // case is the one that needs a different
                                // fix, so it's worth telling them apart.
                                final failed = [
                                  subjectsSnapshot,
                                  labsSnapshot,
                                  facultySnapshot,
                                  roomsSnapshot,
                                ].where((s) => s.hasError).toList();

                                final loadFailed = failed.isNotEmpty
                                    ? failed.first.error.toString()
                                    : null;

                                final stillLoading = [
                                  subjectsSnapshot,
                                  labsSnapshot,
                                  facultySnapshot,
                                  roomsSnapshot,
                                ].any((s) =>
                                    s.connectionState ==
                                    ConnectionState.waiting);

                                return SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (loadFailed != null) ...[
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          margin: const EdgeInsets.only(bottom: 12),
                                          decoration: BoxDecoration(
                                            color: AppColors.danger.withValues(alpha: .1),
                                            borderRadius: BorderRadius.circular(AppRadius.sm),
                                            border: Border.all(
                                                color: AppColors.danger.withValues(alpha: .3)),
                                          ),
                                          child: Text(
                                            "Couldn't load the lists: $loadFailed",
                                            style: AppTextStyles.caption
                                                .copyWith(color: AppColors.danger),
                                          ),
                                        ),
                                      ] else if (stillLoading) ...[
                                        const Padding(
                                          padding: EdgeInsets.only(bottom: 12),
                                          child: LinearProgressIndicator(minHeight: 2),
                                        ),
                                      ] else if (!hadOptions) ...[
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          margin: const EdgeInsets.only(bottom: 12),
                                          decoration: BoxDecoration(
                                            color: AppColors.warning.withValues(alpha: .1),
                                            borderRadius: BorderRadius.circular(AppRadius.sm),
                                          ),
                                          child: Text(
                                            'Nothing to choose from yet. Add '
                                            '${isLab ? 'labs' : 'subjects'}, faculty and rooms '
                                            'under Master Data first — this form can only offer '
                                            'what exists there.',
                                            style: AppTextStyles.caption,
                                          ),
                                        ),
                                      ],
                                      if (saveError != null) ...[
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          margin: const EdgeInsets.only(bottom: 12),
                                          decoration: BoxDecoration(
                                            color: AppColors.danger.withValues(alpha: .1),
                                            borderRadius: BorderRadius.circular(AppRadius.sm),
                                            border: Border.all(
                                                color: AppColors.danger.withValues(alpha: .3)),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Icon(Icons.error_outline_rounded,
                                                  color: AppColors.danger, size: 17),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  saveError!,
                                                  style: AppTextStyles.caption
                                                      .copyWith(color: AppColors.danger),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      SegmentedButton<String>(
                                        segments: const [
                                          ButtonSegment(value: 'Theory', icon: Icon(Icons.book), label: Text('Theory')),
                                          ButtonSegment(value: 'Lab', icon: Icon(Icons.science), label: Text('Lab')),
                                        ],
                                        selected: {isLab ? 'Lab' : 'Theory'},
                                        onSelectionChanged: (selection) {
                                          setModalState(() {
                                            isLab = selection.first == 'Lab';
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      if (isLab)
                                        DropdownButtonFormField<LabModel>(
                                          initialValue: selectedLab,
                                          decoration: _fieldDecoration(
                                            label: 'Lab',
                                            icon: Icons.science_rounded,
                                          ),
                                          items: labs
                                              .map((lab) => DropdownMenuItem(
                                                    value: lab,
                                                    child: Text(lab.name),
                                                  ))
                                              .toList(),
                                          onChanged: (value) {
                                            setModalState(() {
                                              selectedLab = value;
                                            });
                                          },
                                        )
                                      else
                                        DropdownButtonFormField<SubjectModel>(
                                          initialValue: selectedSubject,
                                          decoration: _fieldDecoration(
                                            label: 'Subject',
                                            icon: Icons.menu_book_rounded,
                                          ),
                                          items: subjects
                                              .map((subject) => DropdownMenuItem(
                                                    value: subject,
                                                    child: Text(subject.name),
                                                  ))
                                              .toList(),
                                          onChanged: (value) {
                                            setModalState(() {
                                              selectedSubject = value;
                                            });
                                          },
                                        ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<FacultyModel>(
                                        initialValue: selectedFaculty,
                                        decoration: _fieldDecoration(
                                          label: 'Faculty',
                                          icon: Icons.person_rounded,
                                        ),
                                        items: faculty
                                            .map((item) => DropdownMenuItem(
                                                  value: item,
                                                  child: Text(item.name),
                                                ))
                                            .toList(),
                                        onChanged: (value) {
                                          setModalState(() {
                                            selectedFaculty = value;
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<RoomModel>(
                                        initialValue: selectedRoom,
                                        decoration: _fieldDecoration(
                                          label: 'Room',
                                          icon: Icons.meeting_room_rounded,
                                        ),
                                        items: rooms
                                            .where((item) => item.active)
                                            .map((item) => DropdownMenuItem(
                                                  value: item,
                                                  child: Text('Room ${item.roomNumber} (${item.type})'),
                                                ))
                                            .toList(),
                                        onChanged: (value) {
                                          setModalState(() {
                                            selectedRoom = value;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                // Name the missing field. "Please choose a valid class,
                // faculty and room" is no help when three of the four
                // are already filled in and the user can't tell which
                // one the form is unhappy about.
                final missing = <String>[
                  if (isLab && selectedLab == null) 'lab',
                  if (!isLab && selectedSubject == null) 'subject',
                  if (selectedFaculty == null) 'faculty',
                  if (selectedRoom == null) 'room',
                ];

                if (missing.isNotEmpty) {
                  setModalState(() {
                    saveError = missing.length == 1
                        ? 'Choose a ${missing.first} before saving.'
                        : 'Still needed: ${missing.join(', ')}.';
                  });
                  return;
                }

                final updatedPeriod = period.copyWith(
                  subject: isLab ? selectedLab!.name : selectedSubject!.name,
                  facultyId: selectedFaculty!.id,
                  facultyName: selectedFaculty!.name,
                  room: selectedRoom!.roomNumber,
                  classType: isLab ? 'Lab' : 'Theory',
                  isFree: false,
                  status: 'draft',
                );

                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);
                setState(() => _isSaving = true);

                try {
                  await TimetableService.instance.updatePeriod(
                    department: _department,
                    academicYear: _academicYear,
                    year: _selectedYear,
                    day: day,
                    period: updatedPeriod,
                  );
                  await _loadTimetableData();
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Failed to update period: $e')),
                    );
                  }
                } finally {
                  if (mounted) {
                    setState(() => _isSaving = false);
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Responsive.init(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Timetable Management'),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          // Reading a sheet is an alternative to typing it, never a
          // replacement — the manual editor below is unchanged, and the
          // import only ever produces something to check.
          if (canImportFromImage)
            IconButton(
              tooltip: 'Import from image',
              icon: const Icon(Icons.document_scanner_outlined),
              onPressed: () => openTimetableImport(context),
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshTimetable,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeroHeader(),
            const SizedBox(height: 18),
            _buildFilterCard(theme),
            const SizedBox(height: 16),
            _buildAddPeriodForm(theme),
            const SizedBox(height: 16),
            _buildTimetablePreview(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader() {
    return Container(
      width: double.infinity,
      padding: Responsive.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Responsive.radius(24)),
        gradient: AppColors.brandGradient,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: Responsive.w(120),
              height: Responsive.w(120),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: Responsive.w(52),
                height: Responsive.w(52),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .16),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.calendar_month_rounded,
                    color: Colors.white, size: Responsive.sp(26)),
              ),
              SizedBox(width: Responsive.w(16)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Plan & Manage Class Schedules',
                        style: AppTextStyles.title.copyWith(color: Colors.white)),
                    SizedBox(height: Responsive.h(4)),
                    Text(
                      'Build the weekly timetable, slot by slot',
                      style: AppTextStyles.body.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterCard(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Year', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(4, (index) {
              final year = index + 1;
              return _FilterPill(
                label: 'Year $year',
                selected: _selectedYear == year,
                onTap: () {
                  setState(() => _selectedYear = year);
                  _refreshTimetable();
                },
              );
            }),
          ),
          const SizedBox(height: 18),
          Text('Add periods to', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: days.map((day) {
              return _FilterPill(
                label: day,
                selected: _selectedDay == day,
                onTap: () {
                  setState(() => _selectedDay = day);
                  _refreshTimetable();
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Pairs a dropdown with a small "+" button so admins can create a
  /// missing Subject/Lab/Faculty/Room/Time Slot right from this form
  /// instead of having to leave and go to Master Data first. The add
  /// dialogs write straight to Firestore via MasterDataService, and every
  /// dropdown here is fed by a live stream, so the new item shows up
  /// immediately — both in this form and in every other screen watching
  /// the same collection.
  Widget _buildDropdownWithQuickAdd<T>({
    required Widget dropdown,
    required String tooltip,
    required VoidCallback onAddNew,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: dropdown),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: IconButton(
            tooltip: tooltip,
            icon: const Icon(Icons.add_rounded, color: AppColors.primary),
            onPressed: onAddNew,
          ),
        ),
      ],
    );
  }

  Widget _buildAddPeriodForm(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: StreamBuilder<List<TimeSlotModel>>(
          stream: slotsStream,
          builder: (context, slotsSnapshot) {
            if (!slotsSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final slots = slotsSnapshot.data ?? [];

            return StreamBuilder<List<SubjectModel>>(
              stream: subjectsStream,
              builder: (context, subjectsSnapshot) {
                if (!subjectsSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final subjects = subjectsSnapshot.data ?? [];

                return StreamBuilder<List<FacultyModel>>(
                  stream: facultyStream,
                  builder: (context, facultySnapshot) {
                    if (!facultySnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final faculty = facultySnapshot.data ?? [];

                    return StreamBuilder<List<RoomModel>>(
                      stream: roomsStream,
                      builder: (context, roomsSnapshot) {
                        if (!roomsSnapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final rooms = roomsSnapshot.data ?? [];

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: .1),
                                    borderRadius: BorderRadius.circular(AppRadius.xs),
                                  ),
                                  child: const Icon(Icons.add_task_rounded,
                                      color: AppColors.primary, size: 18),
                                ),
                                const SizedBox(width: 10),
                                Text('Add Period', style: AppTextStyles.title),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SegmentedButton<String>(
                              style: SegmentedButton.styleFrom(
                                selectedBackgroundColor: AppColors.primary,
                                selectedForegroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppRadius.sm)),
                              ),
                              segments: const [
                                ButtonSegment(value: 'Theory', icon: Icon(Icons.menu_book_rounded), label: Text('Theory')),
                                ButtonSegment(value: 'Lab', icon: Icon(Icons.science_rounded), label: Text('Lab')),
                              ],
                              selected: {_isLabClass ? 'Lab' : 'Theory'},
                              onSelectionChanged: (selection) {
                                setState(() {
                                  _isLabClass = selection.first == 'Lab';
                                  _selectedSubject = null;
                                  _selectedLab = null;
                                });
                              },
                            ),
                            const SizedBox(height: 14),
                            _buildDropdownWithQuickAdd<TimeSlotModel>(
                              dropdown: DropdownButtonFormField<TimeSlotModel>(
                                initialValue: _selectedSlot,
                                decoration: _fieldDecoration(
                                    label: 'Time Slot', icon: Icons.access_time_rounded),
                                items: slots
                                    .where((slot) => slot.active)
                                    .map((slot) => DropdownMenuItem(
                                          value: slot,
                                          child: Text(
                                              '${slot.slotNumber}: ${_to12Hour(slot.startTime)} - ${_to12Hour(slot.endTime)}'),
                                        ))
                                    .toList(),
                                onChanged: (value) => setState(() => _selectedSlot = value),
                              ),
                              tooltip: 'Add a new time slot',
                              onAddNew: () => showDialog(
                                context: context,
                                builder: (context) => const AddTimeSlotDialog(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_isLabClass)
                              StreamBuilder<List<LabModel>>(
                                stream: labsStream,
                                builder: (context, labsSnapshot) {
                                  if (!labsSnapshot.hasData) {
                                    return const Center(child: CircularProgressIndicator());
                                  }

                                  final labs = labsSnapshot.data ?? [];

                                  return Column(
                                    children: [
                                      _buildDropdownWithQuickAdd<LabModel>(
                                        dropdown: DropdownButtonFormField<LabModel>(
                                          initialValue: _selectedLab,
                                          decoration: _fieldDecoration(
                                              label: 'Lab', icon: Icons.science_rounded),
                                          items: labs
                                              .map((lab) => DropdownMenuItem(
                                                    value: lab,
                                                    child: Text(lab.name),
                                                  ))
                                              .toList(),
                                          onChanged: (value) => setState(() => _selectedLab = value),
                                        ),
                                        tooltip: 'Add a new lab for Year $_selectedYear',
                                        onAddNew: () => showDialog(
                                          context: context,
                                          builder: (context) =>
                                              AddLabDialog(initialYear: _selectedYear),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      if (_batchCountForYear > 1) ...[
                                        DropdownButtonFormField<String>(
                                          initialValue: _selectedBatch,
                                          decoration: _fieldDecoration(
                                              label: 'Batch', icon: Icons.groups_rounded),
                                          items: [
                                            const DropdownMenuItem(
                                              value: '',
                                              child: Text('Whole class (all batches)'),
                                            ),
                                            ...BatchService.labels(_batchCountForYear).map(
                                              (b) => DropdownMenuItem(
                                                value: b,
                                                child: Text('Batch $b'),
                                              ),
                                            ),
                                          ],
                                          onChanged: (value) =>
                                              setState(() => _selectedBatch = value ?? ''),
                                        ),
                                        const SizedBox(height: 12),
                                      ],
                                    ],
                                  );
                                },
                              )
                            else
                              _buildDropdownWithQuickAdd<SubjectModel>(
                                dropdown: DropdownButtonFormField<SubjectModel>(
                                  initialValue: _selectedSubject,
                                  decoration: _fieldDecoration(
                                      label: 'Subject', icon: Icons.menu_book_rounded),
                                  items: subjects
                                      .map((subject) => DropdownMenuItem(
                                            value: subject,
                                            child: Text(subject.name),
                                          ))
                                      .toList(),
                                  onChanged: (value) => setState(() => _selectedSubject = value),
                                ),
                                tooltip: 'Add a new subject for Year $_selectedYear',
                                onAddNew: () => showDialog(
                                  context: context,
                                  builder: (context) =>
                                      AddSubjectDialog(initialYear: _selectedYear),
                                ),
                              ),
                            const SizedBox(height: 12),
                            _buildDropdownWithQuickAdd<FacultyModel>(
                              dropdown: DropdownButtonFormField<FacultyModel>(
                                initialValue: _selectedFaculty,
                                decoration: _fieldDecoration(
                                    label: 'Faculty', icon: Icons.person_rounded),
                                items: faculty
                                    .map((fac) => DropdownMenuItem(
                                          value: fac,
                                          child: Text(fac.name),
                                        ))
                                    .toList(),
                                onChanged: (value) => setState(() => _selectedFaculty = value),
                              ),
                              tooltip: 'Add a new faculty member',
                              onAddNew: () => showDialog(
                                context: context,
                                builder: (context) => const AddFacultyDialog(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildDropdownWithQuickAdd<RoomModel>(
                              dropdown: DropdownButtonFormField<RoomModel>(
                                initialValue: _selectedRoom,
                                decoration: _fieldDecoration(
                                    label: 'Room', icon: Icons.meeting_room_rounded),
                                items: rooms
                                    .where((room) => room.active)
                                    .map((room) => DropdownMenuItem(
                                          value: room,
                                          child: Text('Room ${room.roomNumber} (${room.type})'),
                                        ))
                                    .toList(),
                                onChanged: (value) => setState(() => _selectedRoom = value),
                              ),
                              tooltip: 'Add a new room',
                              onAddNew: () => showDialog(
                                context: context,
                                builder: (context) => const AddRoomDialog(),
                              ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(AppRadius.sm)),
                                ),
                                onPressed: _isSaving ? null : _addPeriod,
                                icon: _isSaving
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.add_circle_outline_rounded),
                                label: const Text('Add to Timetable',
                                    style: TextStyle(fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
    );
  }

  Widget _buildTimetablePreview(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const [
          BoxShadow(color: AppColors.shadow, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPreviewHeaderRow(),
          const SizedBox(height: 14),
          StreamBuilder<List<TimeSlotModel>>(
            stream: slotsStream,
            builder: (context, slotsSnapshot) {
              if (!slotsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final allSlots = slotsSnapshot.data ?? [];
              if (allSlots.isEmpty) {
                return const Text('No time slots available.');
              }

              // Only slots this year's timetable actually uses.
              final slots = _slotsUsedThisWeek(allSlots);
              if (slots.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                      'No classes scheduled yet for this year. Add periods above to build the timetable.'),
                );
              }

              return _buildTimetableGrid(slots);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewHeaderRow() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: const Icon(Icons.view_agenda_rounded, color: AppColors.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Text('Year $_selectedYear Timetable', style: AppTextStyles.title),
        const Spacer(),
        _LegendDot(color: AppColors.primary, label: 'Theory'),
        const SizedBox(width: 10),
        _LegendDot(color: AppColors.teal, label: 'Lab'),
      ],
    );
  }

  Widget _buildTimetableGrid(List<TimeSlotModel> slots) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
        boxShadow: const [
          BoxShadow(color: AppColors.shadow, blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 14,
          horizontalMargin: 12,
          dividerThickness: 0.7,
          headingRowColor: WidgetStateProperty.resolveWith(
              (states) => AppColors.primary.withValues(alpha: 0.08)),
          headingTextStyle: AppTextStyles.caption
              .copyWith(fontWeight: FontWeight.w800, color: AppColors.primary),
          dataTextStyle: AppTextStyles.caption.copyWith(height: 1.35),
          dataRowMinHeight: 84,
          dataRowMaxHeight: 110,
          columns: [
            const DataColumn(label: Text('Time slot')),
            ...days.map((day) => DataColumn(label: Text(day))),
          ],
          rows: slots.map((slot) => _buildTimetableRow(slot)).toList(),
        ),
      ),
    );
  }

  DataRow _buildTimetableRow(TimeSlotModel slot) {
    return DataRow(
      cells: [
        DataCell(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '${_to12Hour(slot.startTime)}\n${_to12Hour(slot.endTime)}',
              style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        ...days.map((day) {
          final period = _getPeriodForDayAndSlot(day, slot);

          if (period == null) {
            return DataCell(_buildFreeSlotCell());
          }

          return DataCell(_buildPeriodCell(day, period));
        }),
      ],
    );
  }

  Widget _buildFreeSlotCell() {
    return Container(
      width: 132,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        'Free',
        style: AppTextStyles.caption.copyWith(
          color: AppColors.textSecondary.withValues(alpha: 0.6),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// A single scheduled period card — tap opens the edit dialog,
  /// long-press asks for confirmation and deletes it. Replaces the old
  /// three-dot popup menu with direct, discoverable gestures. Styled with
  /// a clearly-visible tinted fill (not just a faint wash) so it reads at
  /// a glance, and a small pencil hint so the tap target is obvious.
  Widget _buildPeriodCell(String day, PeriodModel period) {
    final typeColor = _classTypeColor(period.classType);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showEditPeriodDialog(day, period),
        onLongPress: () => _confirmDeletePeriod(day, period),
        child: Container(
          width: 132,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                typeColor.withValues(alpha: 0.22),
                typeColor.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: typeColor.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    period.classType == 'Lab'
                        ? Icons.science_rounded
                        : Icons.menu_book_rounded,
                    size: 13,
                    color: typeColor,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      period.subject.isEmpty ? 'Free slot' : period.subject,
                      style: AppTextStyles.caption
                          .copyWith(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.edit_rounded, size: 12, color: typeColor.withValues(alpha: 0.7)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                period.batch.isEmpty
                    ? period.classType
                    : '${period.classType} • Batch ${period.batch}',
                style: AppTextStyles.caption
                    .copyWith(color: typeColor, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${period.facultyName.isEmpty ? 'Unassigned' : period.facultyName}\nRoom ${period.room.isEmpty ? '—' : period.room}',
                style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gradient pill selector used for the Year / Day filters — same visual
/// recipe as the CR Directory's year selector (brandGradient when
/// selected, subtle outlined chip otherwise).
class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xxl),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.brandGradient : null,
          color: selected ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(
            color: selected ? Colors.transparent : AppColors.divider,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Small colored dot + label used for the Theory/Lab legend above the
/// timetable grid.
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
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppTextStyles.caption
              .copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
