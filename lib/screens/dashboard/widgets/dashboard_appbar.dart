import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class DashboardAppBar extends StatelessWidget
    implements PreferredSizeWidget {

  final Map<String, dynamic> student;

  final VoidCallback onProfileTap;

  final VoidCallback onLogoutTap;

  final VoidCallback? onNotificationsTap;

  const DashboardAppBar({
    super.key,
    required this.student,
    required this.onProfileTap,
    required this.onLogoutTap,
    this.onNotificationsTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);



  @override
  Widget build(BuildContext context) {

    return AppBar(

      automaticallyImplyLeading: false,

      elevation: 0,

      scrolledUnderElevation: 0,

      backgroundColor: Colors.white,

      surfaceTintColor: Colors.white,

      toolbarHeight: Responsive.h(72),

      titleSpacing: Responsive.w(20),

      title: Row(

        children: [

          Container(

            width: Responsive.w(46),

            height: Responsive.w(46),

            decoration: BoxDecoration(

              color: AppColors.primary.withValues(alpha: .1),

              borderRadius: BorderRadius.circular(
                Responsive.radius(14),
              ),
            ),

            child: Icon(
              Icons.school_rounded,
              color: AppColors.primary,
              size: Responsive.sp(24),
            ),
          ),

          SizedBox(width: Responsive.w(14)),

          Expanded(

            child: Column(

              crossAxisAlignment: CrossAxisAlignment.start,

              mainAxisAlignment: MainAxisAlignment.center,

              children: [

                Text(
                  "AttendX",
                  style: AppTextStyles.title,
                ),

                SizedBox(height: Responsive.h(2)),

                Text(
                  (student["regNo"] ?? "").toString(),
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),

          if (onNotificationsTap != null)
            IconButton(
              onPressed: onNotificationsTap,
              splashRadius: Responsive.w(22),
              icon: Icon(
                Icons.notifications_outlined,
                color: AppColors.primary,
                size: Responsive.sp(22),
              ),
            ),

          IconButton(

            onPressed: onProfileTap,

            splashRadius: Responsive.w(22),

            icon: CircleAvatar(

              radius: Responsive.w(18),

              backgroundColor:
                  AppColors.primary.withValues(alpha: .08),

              child: Icon(
                Icons.person_rounded,
                color: AppColors.primary,
                size: Responsive.sp(20),
              ),
            ),
          ),

          IconButton(

            onPressed: onLogoutTap,

            splashRadius: Responsive.w(22),

            icon: Icon(
              Icons.logout_rounded,
              color: Colors.red,
              size: Responsive.sp(22),
            ),
          ),
        ],
      ),
    );
  }
}