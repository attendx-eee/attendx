import 'package:flutter/material.dart';

import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_colors.dart';

class AttendanceHistoryCard extends StatelessWidget {
  /// Real history built from Raspberry Pi check-in events.
  final List<AttendanceHistory> entries;

  const AttendanceHistoryCard({super.key, this.entries = const []});

  @override
  Widget build(BuildContext context) {
    final history = entries;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Row(
            children: [

              Text(
                "Attendance History",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: Responsive.sp(18),
                ),
              ),

              const Spacer(),

              Icon(
                Icons.history,
                color: AppColors.primary,
                size: Responsive.sp(22),
              ),
            ],
          ),

          SizedBox(height: Responsive.h(20)),

          if (history.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text("No attendance records yet"),
              ),
            )
          else
            ...history.map(
              (record) => Padding(
                padding: EdgeInsets.only(
                  bottom: Responsive.h(14),
                ),
                child: _HistoryTile(record),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final AttendanceHistory record;

  const _HistoryTile(this.record);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: Responsive.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(
          Responsive.radius(14),
        ),
      ),
      child: Row(
        children: [

          CircleAvatar(
            radius: Responsive.w(22),
            backgroundColor: record.color.withValues(alpha: .12),
            child: Icon(
              Icons.calendar_today_rounded,
              color: record.color,
              size: Responsive.sp(18),
            ),
          ),

          SizedBox(width: Responsive.w(14)),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Text(
                  record.date,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: Responsive.sp(14),
                  ),
                ),

                SizedBox(height: Responsive.h(4)),

                Text(
                  "IN : ${record.checkIn}",
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: Responsive.sp(12),
                  ),
                ),

                SizedBox(height: Responsive.h(2)),

                Text(
                  "OUT : ${record.checkOut}",
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: Responsive.sp(12),
                  ),
                ),
              ],
            ),
          ),

          Container(
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.w(12),
              vertical: Responsive.h(6),
            ),
            decoration: BoxDecoration(
              color: record.color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(
                Responsive.radius(30),
              ),
            ),
            child: Text(
              record.status,
              style: TextStyle(
                color: record.color,
                fontWeight: FontWeight.bold,
                fontSize: Responsive.sp(11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AttendanceHistory {
  final String date;
  final String checkIn;
  final String checkOut;
  final String status;
  final Color color;

  AttendanceHistory(
    this.date,
    this.checkIn,
    this.checkOut,
    this.status,
    this.color,
  );
}