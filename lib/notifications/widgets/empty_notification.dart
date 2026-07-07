import 'package:flutter/material.dart';

import '../../core/responsive/responsive.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_colors.dart';

class EmptyNotification extends StatelessWidget {
  const EmptyNotification({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: Responsive.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            Container(
              width: Responsive.w(120),
              height: Responsive.w(120),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                color: AppColors.primary,
                size: Responsive.sp(60),
              ),
            ),

            SizedBox(height: Responsive.h(28)),

            Text(
              "No Notifications",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: Responsive.sp(22),
                fontWeight: FontWeight.bold,
              ),
            ),

            SizedBox(height: Responsive.h(12)),

            Text(
              "You're all caught up.\nAttendance updates, announcements,\nexam alerts and biometric notifications\nwill appear here.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: Responsive.sp(14),
                color: Colors.grey.shade600,
                height: 1.6,
              ),
            ),

            SizedBox(height: Responsive.h(32)),

            Container(
              padding: Responsive.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(
                  Responsive.radius(16),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [

                  Icon(
                    Icons.info_outline,
                    color: AppColors.primary,
                    size: Responsive.sp(18),
                  ),

                  SizedBox(width: Responsive.w(10)),

                  Flexible(
                    child: Text(
                      "New notifications appear instantly.",
                      style: TextStyle(
                        fontSize: Responsive.sp(13),
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
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