import 'package:flutter/material.dart';

import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';
import '../models/day_summary.dart';
import '../services/semester_totals_service.dart';

/// A month, counted in classes rather than in days.
///
/// This replaced a card that showed days present, days absent and late.
/// Days were the wrong unit once attendance became per-period: a student
/// who turned up for one of three classes was a present day, and a
/// student who sat through all three was also a present day. The office
/// was reading a number that could not tell those two apart.
///
/// The order is the one the question gets asked in. How many classes
/// does this month hold — that comes off the timetable and is the same
/// for everybody. How many of those have actually been held. How many
/// this student attended, and what fraction that is. Then the weighted
/// overall, which is the figure eligibility is judged on.
///
/// Percentages are over classes **held**, never over the plan. Only a
/// fraction of a live month has been registered at any moment, and
/// dividing by the plan would tell a student with perfect attendance
/// that they are on 12%.
class MonthTotalsCard extends StatelessWidget {
  final String label;
  final AttendanceTotals totals;
  final MonthPlan plan;

  /// Shown under the card when an admin has corrected days by hand.
  final String? footnote;

  const MonthTotalsCard({
    super.key,
    required this.label,
    required this.totals,
    this.plan = const MonthPlan(),
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    final short = totals.isShortOverall;

    return Container(
      padding: Responsive.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: short
              ? AppColors.danger.withValues(alpha: .4)
              : AppColors.divider,
        ),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: AppTextStyles.title
                            .copyWith(fontSize: Responsive.sp(14))),
                    SizedBox(height: Responsive.h(2)),
                    Text(
                      plan.isEmpty
                          ? 'Nothing on the timetable this month.'
                          : 'On the timetable: ${plan.theory} theory'
                              '${plan.lab > 0 ? ' · ${plan.lab} lab' : ''}'
                              ' — ${totals.held} held so far.',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: Responsive.h(14)),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ClassBlock(
                  icon: Icons.menu_book_rounded,
                  label: 'Theory',
                  planned: plan.theory,
                  held: totals.theoryHeld,
                  attended: totals.theoryAttended,
                  percent: totals.theoryPercent,
                  short: totals.isShortTheory,
                ),
              ),
              Container(
                width: 1,
                height: Responsive.h(72),
                color: AppColors.divider,
                margin: Responsive.symmetric(horizontal: 12),
              ),
              Expanded(
                child: _ClassBlock(
                  icon: Icons.science_rounded,
                  label: 'Lab',
                  planned: plan.lab,
                  held: totals.labHeld,
                  attended: totals.labAttended,
                  percent: totals.labPercent,
                  short: totals.isShortLab,
                ),
              ),
            ],
          ),

          SizedBox(height: Responsive.h(14)),
          Container(
            padding: Responsive.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: (short ? AppColors.danger : AppColors.success)
                  .withValues(alpha: .08),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Overall',
                          style: AppTextStyles.caption.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      SizedBox(height: Responsive.h(1)),
                      Text(
                        totals.heldPoints == 0
                            ? 'Nothing held yet this month'
                            : '${totals.attendedPoints} of '
                                '${totals.heldPoints} points · a lab counts '
                                '${ClassWeight.lab}, theory '
                                '${ClassWeight.theory}',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: Responsive.w(8)),
                Text(
                  totals.heldPoints == 0
                      ? '--'
                      : '${totals.overallPercent.toStringAsFixed(1)}%',
                  style: AppTextStyles.headline.copyWith(
                    fontSize: Responsive.sp(22),
                    color: short ? AppColors.danger : AppColors.success,
                  ),
                ),
              ],
            ),
          ),

          if (footnote != null) ...[
            SizedBox(height: Responsive.h(10)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.edit_note_rounded,
                    size: Responsive.sp(15), color: AppColors.primary),
                SizedBox(width: Responsive.w(6)),
                Expanded(
                  child: Text(footnote!, style: AppTextStyles.caption),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One of the two class types.
///
/// The plan sits above the percentage and the fraction below it, so the
/// eye lands on the figure that decides anything while the counts that
/// produced it stay within reach. A type with nothing on the timetable
/// reads "none this month" rather than 0%, because a year with no labs
/// yet is not a year failing its labs.
class _ClassBlock extends StatelessWidget {
  final IconData icon;
  final String label;
  final int planned;
  final int held;
  final int attended;
  final double percent;
  final bool short;

  const _ClassBlock({
    required this.icon,
    required this.label,
    required this.planned,
    required this.held,
    required this.attended,
    required this.percent,
    required this.short,
  });

  @override
  Widget build(BuildContext context) {
    final none = planned == 0 && held == 0;
    final colour = short ? AppColors.danger : AppColors.textPrimary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon,
                size: Responsive.sp(14), color: AppColors.textSecondary),
            SizedBox(width: Responsive.w(5)),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: Responsive.sp(10),
                fontWeight: FontWeight.w800,
                letterSpacing: .6,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        SizedBox(height: Responsive.h(4)),
        Text(
          none
              ? 'None this month'
              : '$planned on the timetable',
          style: AppTextStyles.caption,
        ),
        SizedBox(height: Responsive.h(6)),
        Text(
          held == 0 ? '--' : '${percent.toStringAsFixed(0)}%',
          style: AppTextStyles.headline.copyWith(
            fontSize: Responsive.sp(24),
            color: held == 0 ? AppColors.textSecondary : colour,
          ),
        ),
        SizedBox(height: Responsive.h(2)),
        Text(
          held == 0
              ? 'None held yet'
              : '$attended attended of $held held',
          style: AppTextStyles.caption,
        ),
      ],
    );
  }
}
