import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Admin dashboard masthead — same gradient-card language as the
/// student dashboard's HeroWelcomeCard, so the admin side reads as part
/// of the same app rather than a bolted-on template.
class AdminHeroHeader extends StatelessWidget {
  final String department;

  const AdminHeroHeader({super.key, required this.department});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: Responsive.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Responsive.radius(28)),
        gradient: AppColors.brandGradient,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -40,
            child: Container(
              width: Responsive.w(150),
              height: Responsive.w(150),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -30,
            child: Container(
              width: Responsive.w(120),
              height: Responsive.w(120),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .06),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: Responsive.w(56),
                    height: Responsive.w(56),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.admin_panel_settings_rounded,
                      color: Colors.white,
                      size: Responsive.sp(28),
                    ),
                  ),
                  SizedBox(width: Responsive.w(16)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Admin Control Center",
                          style: AppTextStyles.headline.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: Responsive.h(4)),
                        Text(
                          "Manage academic resources, approvals & CR contacts",
                          style: AppTextStyles.body.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: Responsive.h(20)),
              Wrap(
                spacing: Responsive.w(10),
                runSpacing: Responsive.h(10),
                children: [
                  _InfoChip(
                    icon: Icons.account_tree_outlined,
                    text: department,
                  ),
                  _InfoChip(
                    icon: Icons.calendar_today_outlined,
                    text: DateFormat("dd MMM yyyy").format(DateTime.now()),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: Responsive.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(Responsive.radius(12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: Responsive.sp(16), color: Colors.white),
          SizedBox(width: Responsive.w(6)),
          Text(
            text,
            style: AppTextStyles.caption.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}
