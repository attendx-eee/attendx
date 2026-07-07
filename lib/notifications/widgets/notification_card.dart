import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/notification_model.dart';
import '../../core/theme/app_colors.dart';

class NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback? onTap;
  final VoidCallback? onMarkRead;
  final VoidCallback? onDelete;

  const NotificationCard({
    super.key,
    required this.notification,
    this.onTap,
    this.onMarkRead,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(notification.category);
    final icon = _categoryIcon(notification.category);

    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: Responsive.w(24)),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(
            Responsive.radius(18),
          ),
        ),
        child: Icon(
          Icons.delete_outline,
          color: Colors.white,
          size: Responsive.sp(28),
        ),
      ),
      onDismissed: (_) {
        onDelete?.call();
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(
          Responsive.radius(18),
        ),
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.only(
            bottom: Responsive.h(14),
          ),
          padding: Responsive.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: notification.read
                ? Colors.white
                : color.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(
              Responsive.radius(18),
            ),
            border: Border.all(
              color: notification.read
                  ? Colors.grey.shade200
                  : color.withValues(alpha: .30),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .04),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              Container(
                width: Responsive.w(52),
                height: Responsive.w(52),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: Responsive.sp(26),
                ),
              ),

              SizedBox(width: Responsive.w(16)),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    Row(
                      children: [

                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: Responsive.sp(16),
                            ),
                          ),
                        ),

                        if (!notification.read)
                          Container(
                            width: Responsive.w(10),
                            height: Responsive.w(10),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),

                    SizedBox(height: Responsive.h(8)),

                    Text(
                      notification.body,
                      style: TextStyle(
                        fontSize: Responsive.sp(13),
                        color: Colors.grey.shade700,
                        height: 1.5,
                      ),
                    ),

                    SizedBox(height: Responsive.h(14)),

                    Row(
                      children: [

                        _CategoryChip(
                          title: notification.category.toUpperCase(),
                          color: color,
                        ),

                        SizedBox(width: Responsive.w(8)),

                        if (notification.priority != "normal")
                          _PriorityChip(
                            priority: notification.priority,
                          ),

                        const Spacer(),

                        Text(
                          DateFormat("dd MMM • hh:mm a")
                              .format(notification.createdAt.toDate()),
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: Responsive.sp(11),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String title;
  final Color color;

  const _CategoryChip({
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.w(10),
        vertical: Responsive.h(4),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(
          Responsive.radius(30),
        ),
      ),
      child: Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: Responsive.sp(10),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  final String priority;

  const _PriorityChip({
    required this.priority,
  });

  @override
  Widget build(BuildContext context) {
    Color color;

    switch (priority) {
      case "critical":
        color = Colors.red;
        break;

      case "high":
        color = Colors.orange;

        break;

      case "low":
        color = Colors.grey;

        break;

      default:
        color = Colors.blue;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.w(10),
        vertical: Responsive.h(4),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(
          Responsive.radius(30),
        ),
      ),
      child: Text(
        priority.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: Responsive.sp(10),
        ),
      ),
    );
  }
}

IconData _categoryIcon(String category) {
  switch (category) {
    case "attendance":
      return Icons.fact_check_rounded;

    case "exam":
      return Icons.school_rounded;

    case "leave":
      return Icons.event_available_rounded;

    case "announcement":
      return Icons.campaign_rounded;

    case "security":
      return Icons.security_rounded;

    case "biometric":
      return Icons.face_retouching_natural;

    case "timetable":
      return Icons.schedule_rounded;

    default:
      return Icons.notifications_rounded;
  }
}

Color _categoryColor(String category) {
  switch (category) {
    case "attendance":
      return Colors.green;

    case "exam":
      return Colors.deepPurple;

    case "leave":
      return Colors.orange;

    case "announcement":
      return AppColors.primary;

    case "security":
      return Colors.red;

    case "biometric":
      return Colors.teal;

    case "timetable":
      return Colors.blue;

    default:
      return Colors.grey;
  }
}