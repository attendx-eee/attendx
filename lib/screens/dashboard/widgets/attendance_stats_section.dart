import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/stat_card.dart';

class AttendanceStatsSection extends StatelessWidget {
  final int present;
  final int absent;
  final int total;
  

  const AttendanceStatsSection({
    super.key,
    required this.present,
    required this.absent,
    required this.total,

  });

  @override
  Widget build(BuildContext context) {
    final percentage =
        total == 0 ? 0.0 : (present / total) * 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        const SectionHeader(
          title: "Attendance Overview",
          subtitle: "Current semester summary",
        ),

        SizedBox(height: Responsive.h(18)),

        Row(
          children: [

            Expanded(
              child: StatCard(
                icon: Icons.check_circle_outline_rounded,
                title: "Present",
                value: present.toString(),
                color: AppColors.success,
              ),
            ),

            SizedBox(width: Responsive.w(14)),

            Expanded(
              child: StatCard(
                icon: Icons.cancel_outlined,
                title: "Absent",
                value: absent.toString(),
                color: AppColors.warning,
              ),
            ),

            SizedBox(width: Responsive.w(14)),

            Expanded(
              child: StatCard(
                icon: Icons.analytics_outlined,
                title: "Attendance",
                value: "${percentage.toStringAsFixed(0)}%",
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}