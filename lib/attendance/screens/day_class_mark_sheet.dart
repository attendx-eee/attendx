import 'package:flutter/material.dart';

import '../../admin/models/period_model.dart';
import '../../admin/services/timetable_service.dart';
import '../../core/constants/app_config.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';
import '../../faculty/models/period_attendance.dart';
import '../../faculty/services/period_attendance_service.dart';

/// One day's timetable with a tick beside each class.
///
/// The day-level Present / Absent buttons can only say "all of it" or
/// "none of it". This is for the case in between: a student who sat
/// through the morning and missed the afternoon. Whatever the admin
/// doesn't tick is recorded as an absence for that class, which is the
/// whole point — a partial day has to name which classes were missed or
/// it isn't partial, it's just vague.
///
/// Returns true from [show] if anything was saved.
class DayClassMarkSheet extends StatefulWidget {
  final String studentUid;
  final String studentName;
  final Map<String, dynamic> studentData;
  final DateTime date;
  final String markerUid;
  final String markerName;
  final String markerRole;

  const DayClassMarkSheet({
    super.key,
    required this.studentUid,
    required this.studentName,
    required this.studentData,
    required this.date,
    required this.markerUid,
    required this.markerName,
    required this.markerRole,
  });

  static Future<bool> show({
    required BuildContext context,
    required String studentUid,
    required String studentName,
    required Map<String, dynamic> studentData,
    required DateTime date,
    required String markerUid,
    required String markerName,
    required String markerRole,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => DayClassMarkSheet(
        studentUid: studentUid,
        studentName: studentName,
        studentData: studentData,
        date: date,
        markerUid: markerUid,
        markerName: markerName,
        markerRole: markerRole,
      ),
    );

    return saved ?? false;
  }

  @override
  State<DayClassMarkSheet> createState() => _DayClassMarkSheetState();
}

class _DayClassMarkSheetState extends State<DayClassMarkSheet> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<PeriodModel> _periods = const [];

  /// Period numbers ticked as attended.
  final Set<int> _present = {};

  /// Periods a faculty member has already registered, so the admin can
  /// see what they're overriding rather than overwriting it blind.
  final Map<int, PeriodAttendance> _existing = {};

  late final String _batch = (widget.studentData['batch'] ?? '').toString();

  /// Set when the student's batch matched none of the day's classes and
  /// the unfiltered list is being shown instead.
  bool _batchMismatch = false;

  /// Filled only when the day comes back empty: what was looked up, and
  /// which years do have a timetable. "No classes scheduled" on its own
  /// is a dead end — it could mean the timetable is missing, the year
  /// resolved wrong, or the weekday genuinely has nothing, and the admin
  /// has no way to tell which.
  String? _diagnosis;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final department = AppConfig.departmentOf(widget.studentData);
    final year = AppConfig.yearOf(widget.studentData);
    final weekday = AppConfig.dayName(widget.date);

    try {
      // Read straight from the timetable rather than through
      // AttendanceService: that path filters out free periods and short-
      // circuits on holidays, both of which look identical to "the
      // timetable is missing" from in here.
      final all = await TimetableService.instance.getDaySchedule(
        department: department,
        academicYear: AppConfig.academicYear,
        year: year,
        day: weekday,
      );

      final scheduled = all
          .where((p) => !p.isFree && p.subject.isNotEmpty)
          .toList()
        ..sort((a, b) => a.periodNo.compareTo(b.periodNo));

      // A lab for another batch was never this student's class.
      var periods = scheduled
          .where((p) =>
              p.batch.isEmpty || _batch.isEmpty || p.batch == _batch)
          .toList();

      // If the batch filter emptied a day that clearly has classes, the
      // labels disagree — the timetable says "B1" and the student record
      // says "1", or similar. Showing nothing would look like the
      // timetable is missing and leave the admin with no way to mark the
      // day at all, so fall back to the full list and say why.
      if (periods.isEmpty && scheduled.isNotEmpty) {
        periods = scheduled;
        _batchMismatch = true;
      }

      if (periods.isEmpty) {
        _diagnosis = await _diagnose(
          department: department,
          year: year,
          weekday: weekday,
          rawCount: all.length,
        );
      }

      final records = await PeriodAttendanceService.instance.dayForYear(
        department: department,
        year: year,
        date: AppConfig.dateId(widget.date),
      );

      // Start from what's already on record, so opening the sheet and
      // saving without touching anything is a no-op rather than a
      // silent wipe.
      for (final p in periods) {
        final record = records[p.periodNo];
        if (record != null &&
            record.covers(widget.studentUid) &&
            record.wasPresent(widget.studentUid)) {
          _present.add(p.periodNo);
        }
      }

      if (mounted) {
        setState(() {
          _periods = periods;
          _existing
            ..clear()
            ..addAll(records);
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

  /// Works out *why* the day came back empty and says so.
  ///
  /// Three very different causes look identical from the sheet: the
  /// weekday has nothing on it, the whole year has no timetable, or the
  /// student's year resolved to one that was never filled in. The third
  /// is the common one — a student record with no `year` field falls
  /// back to Year 1 — and it is invisible unless something checks the
  /// other years and says which do have a timetable.
  Future<String> _diagnose({
    required String department,
    required int year,
    required String weekday,
    required int rawCount,
  }) async {
    final where = '$department • Year $year • $weekday • '
        '${AppConfig.academicYear}';

    if (rawCount > 0) {
      return 'The $weekday timetable for Year $year has $rawCount slot'
          '${rawCount == 1 ? '' : 's'}, but all of them are free periods '
          'or have no subject set.\n\nLooked in: $where';
    }

    // Which years do have something on this weekday?
    final withTimetable = <int>[];
    for (final y in const [1, 2, 3, 4]) {
      try {
        final periods = await TimetableService.instance.getDaySchedule(
          department: department,
          academicYear: AppConfig.academicYear,
          year: y,
          day: weekday,
        );
        if (periods.any((p) => !p.isFree && p.subject.isNotEmpty)) {
          withTimetable.add(y);
        }
      } catch (_) {
        // A year we can't read tells us nothing; skip it.
      }
    }

    final explicitYear = widget.studentData['year'];
    final yearGuessed = explicitYear is! int;

    final buffer = StringBuffer();

    if (withTimetable.isEmpty) {
      buffer.write('No year has a $weekday timetable for '
          '${AppConfig.academicYear}. Add the periods under '
          'Timetables first.');
    } else if (!withTimetable.contains(year)) {
      buffer.write('Year $year has no $weekday timetable, but '
          'Year${withTimetable.length == 1 ? '' : 's'} '
          '${withTimetable.join(', ')} '
          '${withTimetable.length == 1 ? 'does' : 'do'}.');

      if (yearGuessed) {
        buffer.write('\n\nThis student record has no "year" field, so the '
            'app fell back to Year $year. That is very likely the '
            'problem — set their year on the student record.');
      }
    } else {
      buffer.write('The $weekday timetable for Year $year is empty.');
    }

    buffer.write('\n\nLooked in: $where');
    return buffer.toString();
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    // Grabbed before the sheet closes: after `pop` this State's context
    // is defunct, and looking the messenger up through it then would
    // throw instead of showing the confirmation.
    final messenger = ScaffoldMessenger.of(context);

    try {
      final count = await PeriodAttendanceService.instance.markStudentDay(
        uid: widget.studentUid,
        studentData: widget.studentData,
        date: widget.date,
        periods: _periods,
        presentPeriodNos: _present,
        markerUid: widget.markerUid,
        markerName: widget.markerName,
        markerRole: widget.markerRole,
      );

      if (!mounted) return;

      Navigator.pop(context, true);

      messenger.showSnackBar(
        SnackBar(
          content: Text('${widget.studentName}: ${_present.length} of '
              '$count classes present on '
              '${AppConfig.dateId(widget.date)}.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text("Couldn't save those classes: $e"),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return SafeArea(
      child: Padding(
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
              'Classes on ${AppConfig.dayName(widget.date)}, '
              '${AppConfig.dateId(widget.date)}',
              style: AppTextStyles.title,
            ),
            SizedBox(height: Responsive.h(4)),
            Text(
              'Tick the classes ${widget.studentName} attended. The rest '
              'are recorded as absent for them — nobody else is affected.',
              style: AppTextStyles.caption,
            ),
            SizedBox(height: Responsive.h(3)),
            // Which timetable is being read. Cheap to show and it makes
            // a wrong year visible at a glance instead of only when the
            // list comes back empty.
            Text(
              '${AppConfig.departmentOf(widget.studentData)} • Year '
              '${AppConfig.yearOf(widget.studentData)}'
              '${_batch.isEmpty ? '' : ' • Batch $_batch'}',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_batchMismatch) ...[
              SizedBox(height: Responsive.h(10)),
              Container(
                width: double.infinity,
                padding: Responsive.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  _batch.isEmpty
                      ? 'This student has no lab batch on record, so every '
                          'class for the year is listed.'
                      : 'No class on this day is labelled batch "$_batch", '
                          'so every class for the year is listed. Check the '
                          'batch labels on the timetable if that looks wrong.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.warning),
                ),
              ),
            ],
            SizedBox(height: Responsive.h(14)),
            if (_saving) const LinearProgressIndicator(minHeight: 2),
            Flexible(child: _buildContent()),
            if (!_loading && _error == null && _periods.isNotEmpty) ...[
              SizedBox(height: Responsive.h(14)),
              _buildActions(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return Padding(
        padding: Responsive.symmetric(vertical: 40),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: Responsive.symmetric(vertical: 30),
        child: Text("Couldn't load the timetable: $_error",
            style: AppTextStyles.caption),
      );
    }

    if (_periods.isEmpty) {
      return SingleChildScrollView(
        child: Padding(
          padding: Responsive.symmetric(vertical: 24),
          child: Column(
            children: [
              Icon(Icons.event_busy_rounded,
                  size: Responsive.sp(34), color: AppColors.textSecondary),
              SizedBox(height: Responsive.h(10)),
              Text('No classes found for this day',
                  style: AppTextStyles.body),
              SizedBox(height: Responsive.h(10)),
              if (_diagnosis != null)
                Container(
                  width: double.infinity,
                  padding: Responsive.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: .35)),
                  ),
                  child: Text(_diagnosis!, style: AppTextStyles.caption),
                ),
              SizedBox(height: Responsive.h(10)),
              Text(
                'Use the day buttons if you still need to record '
                'something for this date.',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: _periods.length,
      separatorBuilder: (_, _) => SizedBox(height: Responsive.h(8)),
      itemBuilder: (context, i) {
        final period = _periods[i];
        final ticked = _present.contains(period.periodNo);
        final record = _existing[period.periodNo];
        final isLab = period.classType.toLowerCase() == 'lab';

        return Container(
          decoration: BoxDecoration(
            color: ticked
                ? AppColors.success.withValues(alpha: .08)
                : AppColors.background,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: ticked
                  ? AppColors.success.withValues(alpha: .4)
                  : AppColors.divider,
            ),
          ),
          child: CheckboxListTile(
            value: ticked,
            activeColor: AppColors.success,
            controlAffinity: ListTileControlAffinity.leading,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md)),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    period.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isLab ? AppColors.teal : AppColors.primary)
                        .withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isLab ? 'Lab' : 'Theory',
                    style: TextStyle(
                      color: isLab ? AppColors.tealDark : AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: Responsive.sp(10),
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: Responsive.h(2)),
                Text(
                  'Period ${period.periodNo}  •  ${period.startTime} - '
                  '${period.endTime}'
                  '${period.batch.isEmpty ? '' : '  •  Batch ${period.batch}'}'
                  '${period.facultyName.isEmpty ? '' : '  •  ${period.facultyName}'}',
                  style: AppTextStyles.caption,
                ),
                if (record != null) ...[
                  SizedBox(height: Responsive.h(3)),
                  Text(
                    record.covers(widget.studentUid)
                        ? 'Already registered by '
                            '${record.markedByName.isEmpty ? 'staff' : record.markedByName}'
                            ' — ${record.wasPresent(widget.studentUid) ? 'present' : 'absent'}'
                        : 'Registered for other students only',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
            onChanged: _saving
                ? null
                : (v) => setState(() {
                      if (v == true) {
                        _present.add(period.periodNo);
                      } else {
                        _present.remove(period.periodNo);
                      }
                    }),
          ),
        );
      },
    );
  }

  Widget _buildActions() {
    final total = _periods.length;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving
                    ? null
                    : () => setState(() =>
                        _present.addAll(_periods.map((p) => p.periodNo))),
                child: const Text('All present'),
              ),
            ),
            SizedBox(width: Responsive.w(10)),
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : () => setState(_present.clear),
                child: const Text('All absent'),
              ),
            ),
          ],
        ),
        SizedBox(height: Responsive.h(10)),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_rounded, size: 18),
            label: Text('Save — ${_present.length} of $total present'),
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
    );
  }
}
