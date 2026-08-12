import 'package:flutter/material.dart';

import '../admin/models/period_model.dart';
import '../core/constants/app_config.dart';
import '../core/responsive/responsive.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radius.dart';
import '../core/theme/app_text_styles.dart';
import '../timetable/models/timetable_override_model.dart';
import '../timetable/services/schedule_resolver.dart';

/// Books a class into a period the year has free.
///
/// Every subject has a fixed number of classes to fit into the term, and
/// days go missing to holidays, exams and staff absence. The remedy is
/// the one departments have always used: hold the missed class in a free
/// period, agreed on the day. The CR knows which periods are actually
/// free and which lecturer has agreed to come, so the CR books it.
///
/// Two things are deliberately different from a normal period:
///
/// - **The time is typed, not picked.** A period borrowed at short
///   notice rarely lines up with the bells — it might run 3:10 to 4:05
///   because that's when the room and the lecturer were both free.
/// - **It exists for one date only.** Nothing about the master timetable
///   changes, so next Tuesday is unaffected.
class ExtraClassSheet extends StatefulWidget {
  final String department;
  final int year;
  final DateTime date;

  /// The day's master timetable, used to work out which periods are free.
  final List<PeriodModel> basePeriods;

  final String crUid;
  final String crName;

  const ExtraClassSheet({
    super.key,
    required this.department,
    required this.year,
    required this.date,
    required this.basePeriods,
    required this.crUid,
    required this.crName,
  });

  static Future<TimetableOverride?> show({
    required BuildContext context,
    required String department,
    required int year,
    required DateTime date,
    required List<PeriodModel> basePeriods,
    required String crUid,
    required String crName,
  }) {
    return showModalBottomSheet<TimetableOverride>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => ExtraClassSheet(
        department: department,
        year: year,
        date: date,
        basePeriods: basePeriods,
        crUid: crUid,
        crName: crName,
      ),
    );
  }

  @override
  State<ExtraClassSheet> createState() => _ExtraClassSheetState();
}

class _ExtraClassSheetState extends State<ExtraClassSheet> {
  final _subject = TextEditingController();
  final _faculty = TextEditingController();
  final _room = TextEditingController();
  final _note = TextEditingController();

  List<int> _vacant = const [];
  int? _periodNo;

  TimeOfDay _start = const TimeOfDay(hour: 15, minute: 10);
  TimeOfDay _end = const TimeOfDay(hour: 16, minute: 0);

  String _classType = 'Theory';
  String _batch = '';

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVacant();
  }

  @override
  void dispose() {
    for (final c in [_subject, _faculty, _room, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadVacant() async {
    final vacant = await ScheduleResolver.instance.vacantPeriods(
      department: widget.department,
      year: widget.year,
      date: widget.date,
      base: widget.basePeriods.where((p) => !p.isFree).toList(),
    );

    if (!mounted) return;
    setState(() {
      _vacant = vacant;
      _periodNo = vacant.isEmpty ? null : vacant.first;
      _loading = false;
    });
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
    );

    if (picked == null || !mounted) return;

    setState(() {
      if (start) {
        _start = picked;
        // Keeps the end after the start without arguing with the CR
        // about it — they can still change it afterwards.
        final endMinutes = _end.hour * 60 + _end.minute;
        if (endMinutes <= picked.hour * 60 + picked.minute) {
          final shifted = picked.hour * 60 + picked.minute + 50;
          _end = TimeOfDay(hour: (shifted ~/ 60) % 24, minute: shifted % 60);
        }
      } else {
        _end = picked;
      }
    });
  }

  bool get _valid {
    if (_periodNo == null) return false;
    if (_subject.text.trim().isEmpty) return false;
    return _end.hour * 60 + _end.minute > _start.hour * 60 + _start.minute;
  }

  void _save() {
    if (!_valid) {
      setState(() => _error = _periodNo == null
          ? 'No free period left on this day.'
          : _subject.text.trim().isEmpty
              ? 'Name the subject.'
              : 'The end time has to be after the start time.');
      return;
    }

    Navigator.pop(
      context,
      TimetableOverride(
        id: '',
        department: widget.department,
        academicYear: AppConfig.academicYear,
        year: widget.year,
        date: AppConfig.dateId(widget.date),
        day: AppConfig.dayName(widget.date),
        periodNo: _periodNo!,
        startTime: _fmt(_start),
        endTime: _fmt(_end),
        type: OverrideType.extraClass,
        // Nothing was displaced — the slot was empty.
        originalSubject: '',
        originalFacultyName: '',
        originalRoom: '',
        newSubject: _subject.text.trim(),
        newFacultyName: _faculty.text.trim(),
        newRoom: _room.text.trim(),
        batch: _batch,
        classType: _classType,
        note: _note.text.trim(),
        createdBy: widget.crUid,
        createdByName: widget.crName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
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
              Text('Extra class', style: AppTextStyles.title),
              SizedBox(height: Responsive.h(4)),
              Text(
                '${AppConfig.dayName(widget.date)}, '
                '${AppConfig.dateId(widget.date)} — this date only. The '
                'regular timetable is unchanged.',
                style: AppTextStyles.caption,
              ),
              SizedBox(height: Responsive.h(16)),

              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_vacant.isEmpty)
                Container(
                  padding: Responsive.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    'Every period is already taken on this day, so there '
                    'is nowhere to put an extra class. Cancel a class '
                    'first, or pick another date.',
                    style: AppTextStyles.caption,
                  ),
                )
              else ...[
                Text('Free period', style: AppTextStyles.caption),
                SizedBox(height: Responsive.h(6)),
                Wrap(
                  spacing: Responsive.w(8),
                  runSpacing: Responsive.h(8),
                  children: [
                    for (final n in _vacant)
                      ChoiceChip(
                        label: Text('Period $n'),
                        selected: _periodNo == n,
                        onSelected: (_) => setState(() => _periodNo = n),
                      ),
                  ],
                ),
                SizedBox(height: Responsive.h(16)),

                // Typed, not chosen from the bell schedule. A borrowed
                // period keeps its own hours.
                Row(
                  children: [
                    Expanded(
                      child: _TimeField(
                        label: 'Starts',
                        value: _fmt(_start),
                        onTap: () => _pickTime(start: true),
                      ),
                    ),
                    SizedBox(width: Responsive.w(12)),
                    Expanded(
                      child: _TimeField(
                        label: 'Ends',
                        value: _fmt(_end),
                        onTap: () => _pickTime(start: false),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: Responsive.h(14)),

                _field(_subject, 'Subject *', Icons.menu_book_rounded),
                SizedBox(height: Responsive.h(10)),
                _field(_faculty, 'Faculty', Icons.person_outline_rounded),
                SizedBox(height: Responsive.h(10)),
                _field(_room, 'Room', Icons.meeting_room_outlined),
                SizedBox(height: Responsive.h(10)),
                _field(_note, 'Note to the class', Icons.notes_rounded),

                SizedBox(height: Responsive.h(14)),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _classType,
                        decoration: InputDecoration(
                          labelText: 'Type',
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'Theory', child: Text('Theory')),
                          DropdownMenuItem(value: 'Lab', child: Text('Lab')),
                        ],
                        onChanged: (v) =>
                            setState(() => _classType = v ?? 'Theory'),
                      ),
                    ),
                    SizedBox(width: Responsive.w(12)),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _batch,
                        decoration: InputDecoration(
                          labelText: 'Batch',
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: '', child: Text('Whole class')),
                          DropdownMenuItem(value: 'A', child: Text('Batch A')),
                          DropdownMenuItem(value: 'B', child: Text('Batch B')),
                          DropdownMenuItem(value: 'C', child: Text('Batch C')),
                        ],
                        onChanged: (v) => setState(() => _batch = v ?? ''),
                      ),
                    ),
                  ],
                ),

                if (_error != null) ...[
                  SizedBox(height: Responsive.h(12)),
                  Text(_error!,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.danger)),
                ],

                SizedBox(height: Responsive.h(10)),
                Container(
                  padding: Responsive.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    'This class counts towards attendance once the '
                    'faculty marks it — a ${_classType.toLowerCase()} is '
                    'worth the same as any other on the timetable. '
                    'Everyone in Year ${widget.year} is notified.',
                    style: AppTextStyles.caption,
                  ),
                ),

                SizedBox(height: Responsive.h(16)),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add the class'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: Responsive.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                  ),
                ),
              ],
              SizedBox(height: Responsive.h(10)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
          TextEditingController controller, String label, IconData icon) =>
      TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: Responsive.sp(18)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          contentPadding:
              Responsive.symmetric(horizontal: 14, vertical: 12),
        ),
      );
}

class _TimeField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(Icons.schedule_rounded, size: Responsive.sp(18)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          contentPadding:
              Responsive.symmetric(horizontal: 14, vertical: 12),
        ),
        child: Text(value,
            style: AppTextStyles.body
                .copyWith(color: AppColors.textPrimary)),
      ),
    );
  }
}
