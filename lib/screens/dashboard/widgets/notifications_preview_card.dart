import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/primary_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/theme/app_colors.dart';

class NotificationsPreviewCard extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> notifications;
  final VoidCallback onViewAll;

  const NotificationsPreviewCard({
    super.key,
    required this.notifications,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        SectionHeader(
          title: "Notifications",
          subtitle: "Latest updates",
          trailing: TextButton(
            onPressed: onViewAll,
            child: const Text("View All"),
          ),
        ),

        SizedBox(height: Responsive.h(18)),

        PrimaryCard(
          child: notifications.isEmpty
              ? Padding(
                  padding: EdgeInsets.all(Responsive.w(24)),
                  child: Column(
                    children: [

                      Icon(
                        Icons.notifications_none_rounded,
                        size: Responsive.w(42),
                        color: Colors.grey,
                      ),

                      SizedBox(height: Responsive.h(12)),

                      Text(
                        "You're all caught up",
                        style: AppTextStyles.title,
                      ),

                      SizedBox(height: Responsive.h(6)),

                      Text(
                        "No new notifications.",
                        style: AppTextStyles.body,
                      ),
                    ],
                  ),
                )
              : Column(
                  children: List.generate(
                    notifications.length.clamp(0, 3),
                    (index) {
                      final item = notifications[index].data();

                      return _NotificationTile(item);
                    },
                  ),
                ),
        )
      ],
    );
  }
}

class _NotificationTile extends StatelessWidget {

  final Map<String,dynamic> data;

  const _NotificationTile(this.data);

  IconData _icon() {

    switch(data["type"]) {

      case "attendance":
        return Icons.fact_check_rounded;

      case "warning":
        return Icons.warning_amber_rounded;

      case "exam":
        return Icons.assignment_rounded;

      case "holiday":
        return Icons.beach_access_rounded;

      case "announcement":
        return Icons.campaign_rounded;

      default:
        return Icons.notifications;
    }

  }

  @override
  Widget build(BuildContext context) {

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: Responsive.h(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: .08),
            child: Icon(
              _icon(),
              color: AppColors.primary,
            ),
          ),

          SizedBox(width: Responsive.w(14)),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [

                Text(
                  data["title"] ?? "",
                  style: AppTextStyles.title,
                ),

                SizedBox(height: Responsive.h(4)),

                Text(
                  data["body"] ?? "",
                  style: AppTextStyles.body,
                ),
              ],
            ),
          ),

          if(!(data["read"] ?? false))
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            )
        ],
      ),
    );
  }
}