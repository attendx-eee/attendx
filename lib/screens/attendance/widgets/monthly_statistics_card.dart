import 'package:flutter/material.dart';

import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_colors.dart';

/// This month's statistics: presence-rate bar + a 2x2 grid of
/// soft-tinted stat tiles.
class MonthlyStatisticsCard extends StatelessWidget {
  final int present;
  final int absent;
  final int late;
  final int leave;

  const MonthlyStatisticsCard({
    super.key,
    this.present = 0,
    this.absent = 0,
    this.late = 0,
    this.leave = 0,
  });

  @override
  Widget build(BuildContext context) {
    final total = present + absent;
    final ratio = total == 0 ? 0.0 : present / total;
    final percentage = (ratio * 100).round();

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
          // -------------------------------------------------- header
          Row(
            children: [
              Container(
                padding: Responsive.all(8),
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius:
                      BorderRadius.circular(Responsive.radius(10)),
                ),
                child: Icon(Icons.insights_rounded,
                    color: Colors.white, size: Responsive.sp(16)),
              ),
              SizedBox(width: Responsive.w(10)),
              Text(
                "Monthly Statistics",
                style: TextStyle(
                  fontSize: Responsive.sp(18),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    Responsive.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (percentage >= 75
                          ? AppColors.success
                          : AppColors.warning)
                      .withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  "$percentage%",
                  style: TextStyle(
                    color: percentage >= 75
                        ? AppColors.success
                        : AppColors.warning,
                    fontWeight: FontWeight.w800,
                    fontSize: Responsive.sp(12),
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: Responsive.h(16)),

          // -------------------------------------- presence-rate bar
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: SizedBox(
              height: Responsive.h(9),
              child: Stack(
                children: [
                  Container(color: AppColors.divider),
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    tween: Tween(begin: 0, end: ratio),
                    builder: (context, value, _) => FractionallySizedBox(
                      widthFactor: value.clamp(0.0, 1.0),
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: AppColors.brandGradient,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: Responsive.h(18)),

          // ------------------------------------------- 2x2 stat grid
          Row(
            children: [
              _StatTile(
                title: "Present",
                value: "$present",
                icon: Icons.check_circle_rounded,
                color: AppColors.success,
              ),
              SizedBox(width: Responsive.w(12)),
              _StatTile(
                title: "Absent",
                value: "$absent",
                icon: Icons.cancel_rounded,
                color: AppColors.danger,
              ),
            ],
          ),
          SizedBox(height: Responsive.h(12)),
          Row(
            children: [
              _StatTile(
                title: "Late Check-ins",
                value: "$late",
                icon: Icons.schedule_rounded,
                color: AppColors.warning,
              ),
              SizedBox(width: Responsive.w(12)),
              _StatTile(
                title: "Leave",
                value: "$leave",
                icon: Icons.beach_access_rounded,
                color: AppColors.teal,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: Responsive.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(Responsive.radius(14)),
          border: Border.all(color: color.withValues(alpha: .18)),
        ),
        child: Row(
          children: [
            Container(
              padding: Responsive.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: Responsive.sp(16)),
            ),
            SizedBox(width: Responsive.w(10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: Responsive.sp(18),
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: Responsive.sp(10.5),
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
