import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';

class MonthSelector extends StatelessWidget {
  final List<String> months;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const MonthSelector({
    super.key,
    required this.months,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Responsive.h(42),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: months.length,
        separatorBuilder: (_, _) =>
            SizedBox(width: Responsive.w(10)),
        itemBuilder: (_, index) {
          final selected = index == selectedIndex;

          return GestureDetector(
            onTap: () => onChanged(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: Responsive.symmetric(
                horizontal: 18,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                gradient: selected ? AppColors.brandGradient : null,
                color: selected ? null : Colors.white,
                borderRadius: BorderRadius.circular(
                  Responsive.radius(20),
                ),
                border: selected
                    ? null
                    : Border.all(color: AppColors.divider),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color:
                              AppColors.primary.withValues(alpha: .30),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  months[index],
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: Responsive.sp(13),
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