import 'package:flutter/material.dart';

import '../../attendance/services/semester_totals_service.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';
import '../models/subject_model.dart';
import '../services/master_data_service.dart';

/// Classes held against classes planned, per subject.
///
/// A term is planned around a fixed count — usually
/// [SubjectModel.defaultTarget] for a theory subject — and then days
/// disappear to holidays, exams and staff absence. The shortfall is
/// normally discovered in the last fortnight, when the only remedy is
/// cramming three classes into a week nobody has free.
///
/// Showing the count as it goes turns that into a decision made in
/// October, when there is still room to book extra classes in the free
/// periods the CR can see.
class SyllabusProgressCard extends StatefulWidget {
  final String department;
  final int year;

  /// Only these subjects, when the viewer is a lecturer who teaches
  /// some of them. Empty shows everything for the year, which is what
  /// an admin wants.
  final Set<String> onlySubjects;

  const SyllabusProgressCard({
    super.key,
    required this.department,
    required this.year,
    this.onlySubjects = const {},
  });

  @override
  State<SyllabusProgressCard> createState() => _SyllabusProgressCardState();
}

class _SyllabusProgressCardState extends State<SyllabusProgressCard> {
  bool _loading = true;
  String? _error;
  List<SubjectProgress> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final held = await SemesterTotalsService.instance.heldBySubject(
        department: widget.department,
        year: widget.year,
      );

      final subjects = await MasterDataService.instance.getSubjects().first;

      final forYear =
          subjects.where((s) => s.year == widget.year).toList();

      final rows = <SubjectProgress>[];

      for (final subject in forYear) {
        if (widget.onlySubjects.isNotEmpty &&
            !widget.onlySubjects.contains(subject.name)) {
          continue;
        }

        rows.add(SubjectProgress(
          subject: subject.name,
          held: held[subject.name] ?? 0,
          target: subject.targetClasses,
        ));
      }

      // Subjects registered against the timetable but missing from
      // master data still show. Dropping them would hide real classes
      // just because the subject list is out of date.
      for (final entry in held.entries) {
        if (rows.any((r) => r.subject == entry.key)) continue;
        if (widget.onlySubjects.isNotEmpty &&
            !widget.onlySubjects.contains(entry.key)) {
          continue;
        }

        rows.add(SubjectProgress(
          subject: entry.key,
          held: entry.value,
          target: SubjectModel.defaultTarget,
        ));
      }

      // Furthest behind first — the ones needing a decision.
      rows.sort((a, b) => a.fraction.compareTo(b.fraction));

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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Padding(
        padding: Responsive.symmetric(vertical: 20),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _rows.isEmpty) {
      return const SizedBox.shrink();
    }

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rtl_rounded,
                  size: Responsive.sp(20), color: AppColors.primary),
              SizedBox(width: Responsive.w(10)),
              Expanded(
                child: Text('Syllabus progress',
                    style: AppTextStyles.title
                        .copyWith(fontSize: Responsive.sp(15))),
              ),
              Text('Year ${widget.year}', style: AppTextStyles.caption),
            ],
          ),
          SizedBox(height: Responsive.h(4)),
          Text(
            'Classes held against the count each subject is planned '
            'around. Counted from registers, so a class that was on the '
            'timetable but never taken does not move the bar.',
            style: AppTextStyles.caption,
          ),
          SizedBox(height: Responsive.h(16)),
          for (final row in _rows) ...[
            _Row(progress: row),
            SizedBox(height: Responsive.h(14)),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final SubjectProgress progress;

  const _Row({required this.progress});

  @override
  Widget build(BuildContext context) {
    final colour = progress.complete
        ? AppColors.success
        : progress.fraction >= .6
            ? AppColors.primary
            : AppColors.warning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                progress.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Text(
              '${progress.held} / ${progress.target}',
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: colour,
              ),
            ),
          ],
        ),
        SizedBox(height: Responsive.h(6)),
        ClipRRect(
          borderRadius: BorderRadius.circular(Responsive.radius(6)),
          child: LinearProgressIndicator(
            value: progress.fraction,
            minHeight: Responsive.h(7),
            backgroundColor: AppColors.divider,
            valueColor: AlwaysStoppedAnimation(colour),
          ),
        ),
        SizedBox(height: Responsive.h(4)),
        Text(
          progress.overrun
              ? '${progress.held - progress.target} past the plan'
              : progress.complete
                  ? 'Complete'
                  : '${progress.remaining} to go',
          style: AppTextStyles.caption,
        ),
      ],
    );
  }
}
