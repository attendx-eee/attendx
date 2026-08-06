import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Circular gradient-tinted icon badge used as the `leading` widget on
/// every master-data list card (subjects, labs, faculty, rooms, time
/// slots, batches) — a real, relevant icon instead of cramming a code
/// or initials into a plain CircleAvatar, and the same visual language
/// as the dashboard's MasterTile/CR-directory cards.
class ManagementIconAvatar extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const ManagementIconAvatar({
    super.key,
    required this.icon,
    this.color = AppColors.primary,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: .18),
            color.withValues(alpha: .07),
          ],
        ),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}
