import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_colors.dart';

class AttendanceSummaryCard extends StatelessWidget {
  final double attendancePercentage;
  final int presentDays;
  final int absentDays;
  final int totalDays;

  const AttendanceSummaryCard({
    super.key,
    this.attendancePercentage = 89.4,
    this.presentDays = 67,
    this.absentDays = 8,
    this.totalDays = 75,
  });

  @override
  Widget build(BuildContext context) {
    final Color progressColor =
        attendancePercentage >= 75
            ? const Color(0xff2563EB)
            : const Color(0xffDC2626);

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
          ),
        ],
      ),
      child: Column(
        children: [

          Row(
            children: [

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    Text(
                      "Overall Attendance",
                      style: TextStyle(
                        fontSize: Responsive.sp(14),
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),

                    SizedBox(height: Responsive.h(10)),

                    Text(
                      "${attendancePercentage.toStringAsFixed(1)}%",
                      style: TextStyle(
                        fontSize: Responsive.sp(34),
                        fontWeight: FontWeight.bold,
                        color: progressColor,
                      ),
                    ),

                    SizedBox(height: Responsive.h(6)),

                    Text(
                      attendancePercentage >= 75
                          ? "Eligible for examinations"
                          : "Attendance below requirement",
                      style: TextStyle(
                        fontSize: Responsive.sp(12),
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(
                width: Responsive.w(110),
                height: Responsive.w(110),
                child: Stack(
                  alignment: Alignment.center,
                  children: [

                    SizedBox(
                      width: Responsive.w(110),
                      height: Responsive.w(110),
                      child: CircularProgressIndicator(
                        value: attendancePercentage / 100,
                        strokeWidth: Responsive.w(9),
                        backgroundColor: Colors.grey.shade200,
                        color: progressColor,
                      ),
                    ),

                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [

                        Icon(
                          Icons.school_rounded,
                          color: progressColor,
                          size: Responsive.sp(26),
                        ),

                        SizedBox(height: Responsive.h(4)),

                        Text(
                          "${attendancePercentage.toStringAsFixed(0)}%",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: Responsive.sp(18),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: Responsive.h(24)),

          Row(
            children: [

              Expanded(
                child: _buildMetric(
                  Icons.check_circle_rounded,
                  Colors.green,
                  "Present",
                  presentDays.toString(),
                ),
              ),

              SizedBox(width: Responsive.w(12)),

              Expanded(
                child: _buildMetric(
                  Icons.cancel_rounded,
                  Colors.red,
                  "Absent",
                  absentDays.toString(),
                ),
              ),

              SizedBox(width: Responsive.w(12)),

              Expanded(
                child: _buildMetric(
                  Icons.calendar_month_rounded,
                  AppColors.primary,
                  "Total",
                  totalDays.toString(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(
      IconData icon,
      Color color,
      String title,
      String value,
      ) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: Responsive.h(12),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(
          Responsive.radius(14),
        ),
      ),
      child: Column(
        children: [

          Icon(
            icon,
            color: color,
            size: Responsive.sp(22),
          ),

          SizedBox(height: Responsive.h(8)),

          Text(
            value,
            style: TextStyle(
              fontSize: Responsive.sp(20),
              fontWeight: FontWeight.bold,
            ),
          ),

          SizedBox(height: Responsive.h(2)),

          Text(
            title,
            style: TextStyle(
              fontSize: Responsive.sp(12),
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}