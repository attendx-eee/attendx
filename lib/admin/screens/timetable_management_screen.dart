import 'package:flutter/material.dart';
import '../models/faculty_model.dart';
import '../models/lab_model.dart';
import '../models/period_model.dart';
import '../models/room_model.dart';
import '../models/subject_model.dart';
import '../models/time_slot_model.dart';
import '../services/batch_service.dart';
import '../services/master_data_service.dart';
import '../services/timetable_service.dart';

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

  Future<void> _showEditPeriodDialog(String day, PeriodModel period) async {
    bool isLab = period.classType == 'Lab';
    SubjectModel? selectedSubject;
    LabModel? selectedLab;
    FacultyModel? selectedFaculty;
    RoomModel? selectedRoom;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit ${period.classType} period'),
          content: SizedBox(
            width: 360,
            child: StatefulBuilder(
              builder: (context, setModalState) {
                return StreamBuilder<List<SubjectModel>>(
                  stream: subjectsStream,
                  builder: (context, subjectsSnapshot) {
                    final subjects = subjectsSnapshot.data ?? [];

                    return StreamBuilder<List<LabModel>>(
                      stream: labsStream,
                      builder: (context, labsSnapshot) {
                        final labs = labsSnapshot.data ?? [];

                        return StreamBuilder<List<FacultyModel>>(
                          stream: facultyStream,
                          builder: (context, facultySnapshot) {
                            final faculty = facultySnapshot.data ?? [];

                            return StreamBuilder<List<RoomModel>>(
                              stream: roomsStream,
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

                                return SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
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
                                          decoration: const InputDecoration(
                                            labelText: 'Lab',
                                            border: OutlineInputBorder(),
                                            prefixIcon: Icon(Icons.science),
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
                                          decoration: const InputDecoration(
                                            labelText: 'Subject',
                                            border: OutlineInputBorder(),
                                            prefixIcon: Icon(Icons.book),
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
                                        decoration: const InputDecoration(
                                          labelText: 'Faculty',
                                          border: OutlineInputBorder(),
                                          prefixIcon: Icon(Icons.person),
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
                                        decoration: const InputDecoration(
                                          labelText: 'Room',
                                          border: OutlineInputBorder(),
                                          prefixIcon: Icon(Icons.meeting_room),
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
                if (selectedFaculty == null || selectedRoom == null || (isLab ? selectedLab == null : selectedSubject == null)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please choose a valid class, faculty and room.')),
                  );
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timetable Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshTimetable,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [theme.colorScheme.surface, theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Plan and manage class schedules', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
              const SizedBox(height: 16),
              _buildFilterCard(theme),
              const SizedBox(height: 16),
              _buildAddPeriodForm(theme),
              const SizedBox(height: 16),
              _buildTimetablePreview(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterCard(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select Year', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: List.generate(4, (index) {
                final year = index + 1;
                return FilterChip(
                  selected: _selectedYear == year,
                  label: Text('Year $year'),
                  onSelected: (selected) {
                    setState(() => _selectedYear = year);
                    _refreshTimetable();
                  },
                );
              }),
            ),
            const SizedBox(height: 16),
            Text('Select Day', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: days.map((day) {
                return FilterChip(
                  selected: _selectedDay == day,
                  label: Text(day),
                  onSelected: (selected) {
                    setState(() => _selectedDay = day);
                    _refreshTimetable();
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddPeriodForm(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                                Icon(Icons.schedule, color: theme.colorScheme.primary),
                                const SizedBox(width: 8),
                                Text('Add Period', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'Theory', icon: Icon(Icons.book), label: Text('Theory')),
                                ButtonSegment(value: 'Lab', icon: Icon(Icons.science), label: Text('Lab')),
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
                            const SizedBox(height: 12),
                            DropdownButtonFormField<TimeSlotModel>(
                              initialValue: _selectedSlot,
                              decoration: const InputDecoration(
                                labelText: 'Time Slot',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.access_time),
                              ),
                              items: slots
                                  .where((slot) => slot.active)
                                  .map((slot) => DropdownMenuItem(
                                        value: slot,
                                        child: Text('${slot.slotNumber}: ${slot.startTime} - ${slot.endTime}'),
                                      ))
                                  .toList(),
                              onChanged: (value) => setState(() => _selectedSlot = value),
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
                                      DropdownButtonFormField<LabModel>(
                                        initialValue: _selectedLab,
                                        decoration: const InputDecoration(
                                          labelText: 'Lab',
                                          border: OutlineInputBorder(),
                                          prefixIcon: Icon(Icons.science),
                                        ),
                                        items: labs
                                            .map((lab) => DropdownMenuItem(
                                                  value: lab,
                                                  child: Text(lab.name),
                                                ))
                                            .toList(),
                                        onChanged: (value) => setState(() => _selectedLab = value),
                                      ),
                                      const SizedBox(height: 12),
                                      if (_batchCountForYear > 1) ...[
                                        DropdownButtonFormField<String>(
                                          initialValue: _selectedBatch,
                                          decoration: const InputDecoration(
                                            labelText: 'Batch',
                                            border: OutlineInputBorder(),
                                            prefixIcon: Icon(Icons.groups),
                                          ),
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
                              DropdownButtonFormField<SubjectModel>(
                                initialValue: _selectedSubject,
                                decoration: const InputDecoration(
                                  labelText: 'Subject',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.book),
                                ),
                                items: subjects
                                    .map((subject) => DropdownMenuItem(
                                          value: subject,
                                          child: Text(subject.name),
                                        ))
                                    .toList(),
                                onChanged: (value) => setState(() => _selectedSubject = value),
                              ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<FacultyModel>(
                              initialValue: _selectedFaculty,
                              decoration: const InputDecoration(
                                labelText: 'Faculty',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person),
                              ),
                              items: faculty
                                  .map((fac) => DropdownMenuItem(
                                        value: fac,
                                        child: Text(fac.name),
                                      ))
                                  .toList(),
                              onChanged: (value) => setState(() => _selectedFaculty = value),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<RoomModel>(
                              initialValue: _selectedRoom,
                              decoration: const InputDecoration(
                                labelText: 'Room',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.meeting_room),
                              ),
                              items: rooms
                                  .where((room) => room.active)
                                  .map((room) => DropdownMenuItem(
                                        value: room,
                                        child: Text('Room ${room.roomNumber} (${room.type})'),
                                      ))
                                  .toList(),
                              onChanged: (value) => setState(() => _selectedRoom = value),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _isSaving ? null : _addPeriod,
                                icon: _isSaving
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.add_circle_outline),
                                label: const Text('Add to timetable'),
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
      ),
    );
  }

  Widget _buildTimetablePreview(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.view_agenda, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Year $_selectedYear timetable', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
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

                return Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 14,
                      horizontalMargin: 12,
                      dividerThickness: 0.7,
                      headingRowColor: WidgetStateProperty.resolveWith((states) => theme.colorScheme.primaryContainer.withValues(alpha: 0.35)),
                      headingTextStyle: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                      dataTextStyle: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                      dataRowMinHeight: 84,
                      dataRowMaxHeight: 110,
                      columns: [
                        const DataColumn(label: Text('Time slot')),
                        ...days.map((day) => DataColumn(label: Text(day))),
                      ],
                      rows: slots.map((slot) {
                        return DataRow(
                          cells: [
                            DataCell(
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  '${slot.startTime}\n${slot.endTime}',
                                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            ...days.map((day) {
                              final period = _getPeriodForDayAndSlot(day, slot);
                              if (period == null) {
                                return const DataCell(Text('—'));
                              }

                              return DataCell(
                                Container(
                                  width: 132,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [theme.colorScheme.primaryContainer.withValues(alpha: 0.65), theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.85)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.15)),
                                  ),
                                  child: Stack(
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            period.subject.isEmpty ? 'Free slot' : period.subject,
                                            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            period.batch.isEmpty
                                                ? period.classType
                                                : '${period.classType} • Batch ${period.batch}',
                                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${period.facultyName.isEmpty ? 'Unassigned' : period.facultyName}\nRoom ${period.room.isEmpty ? '—' : period.room}',
                                            style: theme.textTheme.bodySmall,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: PopupMenuButton<String>(
                                          tooltip: 'Edit or delete period',
                                          iconColor: theme.colorScheme.primary,
                                          iconSize: 18,
                                          onSelected: (value) {
                                            if (value == 'edit') {
                                              _showEditPeriodDialog(day, period);
                                            } else if (value == 'delete') {
                                              _deletePeriod(day, period.periodNo);
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                            const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
