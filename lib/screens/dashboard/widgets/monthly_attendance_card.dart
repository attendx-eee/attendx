import 'package:flutter/material.dart';

import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';

/// Month summary: brand-gradient hero card with an animated progress
/// ring and glassy stat chips.
class MonthlyAttendanceCard extends StatelessWidget {
  final String month;
  final int present;
  final int absent;
  final int total;
  final int late;

  const MonthlyAttendanceCard({
    super.key,
    required this.month,
    required this.present,
    required this.absent,
    required this.total,
    this.late = 0,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : present / total;
    final percentage = (ratio * 100).round();
    final onTrack = percentage >= 75;

    return Container(
      margin: Responsive.symmetric(horizontal: 4),
      padding: Responsive.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(Responsive.radius(24)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: .30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ------------------------------------ month + status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      month,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: Responsive.sp(20),
                        letterSpacing: .2,
                      ),
                    ),
                    SizedBox(height: Responsive.h(4)),
                    Text(
                      total == 0
                          ? "No college days recorded"
                          : "$present of $total days attended",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .85),
                        fontSize: Responsive.sp(12),
                      ),
                    ),
                    SizedBox(height: Responsive.h(12)),
                    Container(
                      padding: Responsive.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            onTrack
                                ? Icons.verified_rounded
                                : Icons.warning_amber_rounded,
                            color: Colors.white,
                            size: Responsive.sp(14),
                          ),
                          SizedBox(width: Responsive.w(6)),
                          Text(
                            onTrack ? "ON TRACK" : "BELOW 75%",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: Responsive.sp(10.5),
                              letterSpacing: .8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ---------------------------------------- progress ring
              SizedBox(
                width: Responsive.w(84),
                height: Responsive.w(84),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: 1,
                      strokeWidth: 8,
                      color: Colors.white.withValues(alpha: .18),
                    ),
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      tween: Tween(begin: 0, end: ratio),
                      builder: (context, value, _) =>
                          CircularProgressIndicator(
                        value: value,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        color: Colors.white,
                      ),
                    ),
                    Center(
                      child: Text(
                        "$percentage%",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: Responsive.sp(17),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Spacer(),

          // ------------------------------------------- stat chips
          Row(
            children: [
              _chip(Icons.check_circle_rounded, "Present", present),
              SizedBox(width: Responsive.w(8)),
              _chip(Icons.cancel_rounded, "Absent", absent),
              SizedBox(width: Responsive.w(8)),
              _chip(Icons.schedule_rounded, "Late", late),
              SizedBox(width: Responsive.w(8)),
              _chip(Icons.calendar_month_rounded, "Days", total),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, int value) {
    return Expanded(
      child: Container(
        padding: Responsive.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(Responsive.radius(12)),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: Responsive.sp(15)),
            SizedBox(height: Responsive.h(3)),
            Text(
              "$value",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: Responsive.sp(14),
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .8),
                fontSize: Responsive.sp(9.5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
