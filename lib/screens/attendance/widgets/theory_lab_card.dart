import 'package:flutter/material.dart';

import '../../../attendance/models/day_summary.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// Theory and lab attendance side by side, counted by period.
///
/// Kept apart rather than merged because colleges apply the 75% rule to
/// each separately — a student comfortably above the line overall can
/// still be short in labs, and a single blended number hides exactly the
/// case that matters.
class TheoryLabCard extends StatelessWidget {
  final AttendanceTotals totals;
  final String monthLabel;

  const TheoryLabCard({
    super.key,
    required this.totals,
    required this.monthLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (totals.scheduled == 0) return const SizedBox.shrink();

    return Container(
      padding: Responsive.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Responsive.radius(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Class-wise Attendance',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: Responsive.sp(18),
                ),
              ),
              const Spacer(),
              Text(
                monthLabel,
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: Responsive.sp(13),
                ),
              ),
            ],
          ),
          SizedBox(height: Responsive.h(4)),
          Text(
            'Counted per class over the classes actually held. A lab is '
            'worth ${ClassWeight.lab} and a theory class '
            '${ClassWeight.theory}, so the overall figure reflects the '
            'time each one takes.',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: Responsive.sp(11),
            ),
          ),
          SizedBox(height: Responsive.h(18)),

          if (totals.theoryScheduled > 0)
            _Bar(
              label: 'Theory',
              icon: Icons.menu_book_rounded,
              attended: totals.theoryAttended,
              total: totals.theoryHeld,
              percent: totals.theoryPercent,
              short: totals.isShortTheory,
            ),

          if (totals.theoryScheduled > 0 && totals.labScheduled > 0)
            SizedBox(height: Responsive.h(16)),

          if (totals.labScheduled > 0)
            _Bar(
              label: 'Lab',
              icon: Icons.science_rounded,
              attended: totals.labAttended,
              total: totals.labHeld,
              percent: totals.labPercent,
              short: totals.isShortLab,
            ),

          SizedBox(height: Responsive.h(18)),
          Divider(color: Colors.grey.shade200, height: 1),
          SizedBox(height: Responsive.h(14)),

          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'Overall',
                  value: '${totals.overallPercent.toStringAsFixed(1)}%',
                  color: totals.overallPercent >= 75
                      ? AppColors.success
                      : AppColors.danger,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'Classes',
                  value: '${totals.attended}/${totals.held}',
                  color: AppColors.textPrimary,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'Points',
                  value: '${totals.attendedPoints}/${totals.heldPoints}',
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),

          if (totals.isShortTheory || totals.isShortLab) ...[
            SizedBox(height: Responsive.h(14)),
            Container(
              padding: Responsive.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(Responsive.radius(12)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: AppColors.danger, size: Responsive.sp(18)),
                  SizedBox(width: Responsive.w(8)),
                  Expanded(
                    child: Text(
                      totals.isShortTheory && totals.isShortLab
                          ? 'Below 75% in both theory and labs.'
                          : totals.isShortTheory
                              ? 'Below 75% in theory classes.'
                              : 'Below 75% in labs.',
                      style: TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                        fontSize: Responsive.sp(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final String label;
  final IconData icon;
  final int attended;
  final int total;
  final double percent;
  final bool short;

  const _Bar({
    required this.label,
    required this.icon,
    required this.attended,
    required this.total,
    required this.percent,
    required this.short,
  });

  @override
  Widget build(BuildContext context) {
    final color = short
        ? AppColors.danger
        : percent >= 90
            ? AppColors.success
            : AppColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: Responsive.sp(16), color: color),
            SizedBox(width: Responsive.w(6)),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: Responsive.sp(13),
              ),
            ),
            const Spacer(),
            Text(
              '$attended/$total  •  ${percent.toStringAsFixed(1)}%',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: Responsive.sp(12),
              ),
            ),
          ],
        ),
        SizedBox(height: Responsive.h(8)),
        ClipRRect(
          borderRadius: BorderRadius.circular(Responsive.radius(6)),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : attended / total,
            minHeight: Responsive.h(8),
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Stat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: Responsive.sp(16),
          ),
        ),
        SizedBox(height: Responsive.h(2)),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: Responsive.sp(11),
          ),
        ),
      ],
    );
  }
}
