import 'package:flutter/material.dart';
import '../responsive/responsive.dart';
import '../theme/app_colors.dart';

enum ChipState {
  success,
  warning,
  danger,
  info,
}

class StatusChip extends StatelessWidget {
  final String text;
  final ChipState state;

  const StatusChip({
    super.key,
    required this.text,
    required this.state,
  });

  Color get color {
    switch (state) {
      case ChipState.success:
        return AppColors.success;

      case ChipState.warning:
        return AppColors.warning;

      case ChipState.danger:
        return AppColors.danger;

      case ChipState.info:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: Responsive.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: Responsive.sp(12),
        ),
      ),
    );
  }
}