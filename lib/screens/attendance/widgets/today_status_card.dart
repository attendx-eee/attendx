import 'package:flutter/material.dart';

import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_colors.dart';

class TodayStatusCard extends StatelessWidget {
  final bool checkedIn;
  final bool checkedOut;

  final String checkInTime;
  final String checkOutTime;

  final int attendedClasses;
  final int totalClasses;

  const TodayStatusCard({
    super.key,
    this.checkedIn = true,
    this.checkedOut = false,
    this.checkInTime = "09:02 AM",
    this.checkOutTime = "--",
    this.attendedClasses = 2,
    this.totalClasses = 4,
  });

  @override
  Widget build(BuildContext context) {
    final Color statusColor;

    final String status;

    if (!checkedIn) {
      status = "Absent";
      statusColor = Colors.red;
    } else if (checkedOut) {
      status = "Completed";
      statusColor = Colors.green;
    } else {
      status = "In Progress";
      statusColor = Colors.orange;
    }

    return Container(
      padding: Responsive.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          Responsive.radius(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          )
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Row(
            children: [

              Text(
                "Today's Attendance",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: Responsive.sp(18),
                ),
              ),

              const Spacer(),

              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: Responsive.w(12),
                  vertical: Responsive.h(6),
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(
                    Responsive.radius(30),
                  ),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: Responsive.sp(11),
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: Responsive.h(22)),

          Row(
            children: [

              Expanded(
                child: _tile(
                  Icons.login_rounded,
                  Colors.green,
                  "Check In",
                  checkInTime,
                ),
              ),

              SizedBox(width: Responsive.w(12)),

              Expanded(
                child: _tile(
                  Icons.logout_rounded,
                  Colors.red,
                  "Check Out",
                  checkOutTime,
                ),
              ),
            ],
          ),

          SizedBox(height: Responsive.h(20)),

          Text(
            "Today's Progress",
            style: TextStyle(
              fontSize: Responsive.sp(13),
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),

          SizedBox(height: Responsive.h(10)),

          ClipRRect(
            borderRadius: BorderRadius.circular(
              Responsive.radius(20),
            ),
            child: LinearProgressIndicator(
              value: totalClasses == 0
                  ? 0
                  : attendedClasses / totalClasses,
              minHeight: Responsive.h(8),
              backgroundColor: Colors.grey.shade200,
              color: AppColors.primary,
            ),
          ),

          SizedBox(height: Responsive.h(10)),

          Row(
            children: [

              Icon(
                Icons.menu_book_rounded,
                color: AppColors.primary,
                size: Responsive.sp(18),
              ),

              SizedBox(width: Responsive.w(8)),

              Text(
                "$attendedClasses of $totalClasses classes attended",
                style: TextStyle(
                  fontSize: Responsive.sp(13),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(
      IconData icon,
      Color color,
      String title,
      String value,
      ) {
    return Container(
      padding: EdgeInsets.all(
        Responsive.w(14),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(
          Responsive.radius(16),
        ),
      ),
      child: Column(
        children: [

          Icon(
            icon,
            color: color,
            size: Responsive.sp(24),
          ),

          SizedBox(height: Responsive.h(10)),

          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: Responsive.sp(12),
            ),
          ),

          SizedBox(height: Responsive.h(6)),

          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: Responsive.sp(18),
            ),
          ),
        ],
      ),
    );
  }
}