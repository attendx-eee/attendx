import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/primary_card.dart';

class AttendanceAlertCard extends StatelessWidget {
  final double attendancePercentage;

  const AttendanceAlertCard({
    super.key,
    required this.attendancePercentage,
  });

  @override
  Widget build(BuildContext context) {
    if (attendancePercentage >= 75) {
      return const SizedBox.shrink();
    }

    return PrimaryCard(
      color: const Color(0xffFFF4F4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Container(
            width: Responsive.w(46),
            height: Responsive.w(46),
            decoration: const BoxDecoration(
              color: Color(0xffFEE2E2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              color: AppColors.danger,
              size: Responsive.sp(24),
            ),
          ),

          SizedBox(width: Responsive.w(16)),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Text(
                  "Attendance Alert",
                  style: AppTextStyles.title.copyWith(
                    color: AppColors.danger,
                  ),
                ),

                SizedBox(height: Responsive.h(6)),

                Text(
                  "Your overall attendance is ${attendancePercentage.toStringAsFixed(1)}%. "
                  "Maintain at least 75% attendance to remain eligible.",
                  style: AppTextStyles.body.copyWith(
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}