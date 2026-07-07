import 'package:flutter/material.dart';

import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';

class NotificationFilterBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const NotificationFilterBar({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  static const filters = [
    "All",
    "Unread",
    "Attendance",
    "Exam",
    "Leave",
    "Timetable",
    "Biometric",
    "Security",
    "Announcement",
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Responsive.h(42),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: filters.length,
        separatorBuilder: (_, _) =>
            SizedBox(width: Responsive.w(8)),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final bool active = filter == selected;

          return InkWell(
            borderRadius: BorderRadius.circular(
              Responsive.radius(25),
            ),
            onTap: () => onChanged(filter),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: EdgeInsets.symmetric(
                horizontal: Responsive.w(16),
                vertical: Responsive.h(8),
              ),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primary
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(
                  Responsive.radius(25),
                ),
                border: Border.all(
                  color: active
                      ? AppColors.primary
                      : Colors.grey.shade300,
                ),
              ),
              child: Center(
                child: Text(
                  filter,
                  style: TextStyle(
                    fontSize: Responsive.sp(12),
                    fontWeight: FontWeight.w600,
                    color: active
                        ? Colors.white
                        : Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}