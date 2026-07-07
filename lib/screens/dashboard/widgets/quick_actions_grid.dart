import 'package:flutter/material.dart';

import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/primary_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/theme/app_colors.dart';

class QuickActionsGrid extends StatelessWidget {

  final VoidCallback onAttendance;

  final VoidCallback onSettings;

  final VoidCallback onLeave;

  final VoidCallback onReports;

  const QuickActionsGrid({
    super.key,
    required this.onAttendance,
    required this.onSettings,
    required this.onLeave,
    required this.onReports,
  });

  @override
  Widget build(BuildContext context) {

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        const SectionHeader(
          title: "Quick Actions",
          subtitle: "Frequently used services",
        ),

        SizedBox(height: Responsive.h(18)),

        GridView.count(

          crossAxisCount: 2,

          shrinkWrap: true,

          physics: const NeverScrollableScrollPhysics(),

          crossAxisSpacing: Responsive.w(16),

          mainAxisSpacing: Responsive.h(16),

          childAspectRatio: 1.25,

          children: [

            _ActionCard(
              icon: Icons.calendar_month_rounded,
              title: "Attendance",
              subtitle: "Calendar & history",
              onTap: onAttendance,
            ),

            _ActionCard(
              icon: Icons.assignment_outlined,
              title: "Leave",
              subtitle: "Request leave",
              onTap: onLeave,
            ),

            _ActionCard(
              icon: Icons.bar_chart_rounded,
              title: "Reports",
              subtitle: "Semester analytics",
              onTap: onReports,
            ),

            _ActionCard(
              icon: Icons.settings_outlined,
              title: "Settings",
              subtitle: "Preferences",
              onTap: onSettings,
            ),
          ],
        )
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {

  final IconData icon;

  final String title;

  final String subtitle;

  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {

    return InkWell(

      borderRadius: BorderRadius.circular(20),

      onTap: onTap,

      child: PrimaryCard(

        child: Column(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            Container(

              padding: EdgeInsets.all(
                Responsive.w(12),
              ),

              decoration: BoxDecoration(

                color: AppColors.primary.withValues(alpha: .08),

                borderRadius:
                    BorderRadius.circular(14),
              ),

              child: Icon(
                icon,
                color: AppColors.primary,
                size: Responsive.sp(24),
              ),
            ),

            const Spacer(),

            Text(
              title,
              style: AppTextStyles.title,
            ),

            SizedBox(
              height: Responsive.h(4),
            ),

            Text(
              subtitle,
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
    );
  }
}