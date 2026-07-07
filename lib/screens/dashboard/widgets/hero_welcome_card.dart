import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class HeroWelcomeCard extends StatelessWidget {
  final Map<String, dynamic> student;

  const HeroWelcomeCard({
    super.key,
    required this.student,
  });

  String _greeting() {
    final hour = DateTime.now().hour;

    if (hour < 12) return "Good Morning";
    if (hour < 17) return "Good Afternoon";
    return "Good Evening";
  }

  String _initials(String name) {
    if (name.trim().isEmpty) return "S";

    final parts = name.trim().split(" ");

    if (parts.length == 1) {
      return parts.first[0].toUpperCase();
    }

    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final name = student["name"] ?? "Student";
    final regNo = student["regNo"] ?? "";
    final branch = student["branch"] ?? "";
    final year = student["year"] ?? "";
    final enrolled = student["faceEnrolled"] ?? false;

    return Container(
      width: double.infinity,
      padding: Responsive.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(
          Responsive.radius(28),
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xff2563EB),
            Color(0xff1D4ED8),
          ],
        ),
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
                color: Colors.white.withValues(alpha: .05),
                shape: BoxShape.circle,
              ),
            ),
          ),

          Positioned(
            bottom: -50,
            left: -40,
            child: Container(
              width: Responsive.w(120),
              height: Responsive.w(120),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .04),
                shape: BoxShape.circle,
              ),
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              Row(
                children: [

                  CircleAvatar(
                    radius: Responsive.w(28),
                    backgroundColor: Colors.white,
                    child: Text(
                      _initials(name),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: Responsive.sp(18),
                        color: AppColors.primary,
                      ),
                    ),
                  ),

                  SizedBox(width: Responsive.w(16)),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        Text(
                          _greeting(),
                          style: AppTextStyles.body.copyWith(
                            color: Colors.white70,
                          ),
                        ),

                        SizedBox(height: Responsive.h(4)),

                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.headline.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              SizedBox(height: Responsive.h(24)),

              Wrap(
                spacing: Responsive.w(10),
                runSpacing: Responsive.h(10),
                children: [

                  _InfoChip(
                    icon: Icons.badge_outlined,
                    text: regNo,
                  ),

                  _InfoChip(
                    icon: Icons.school_outlined,
                    text: branch.isEmpty
                        ? year
                        : "$branch • $year",
                  ),

                  _InfoChip(
                    icon: Icons.calendar_today_outlined,
                    text: DateFormat("dd MMM yyyy")
                        .format(DateTime.now()),
                  ),
                ],
              ),

              SizedBox(height: Responsive.h(24)),

              Container(
                padding: Responsive.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(
                    Responsive.radius(14),
                  ),
                ),
                child: Row(
                  children: [

                    Icon(
                      enrolled
                          ? Icons.verified_rounded
                          : Icons.warning_amber_rounded,
                      color: enrolled
                          ? Colors.greenAccent
                          : Colors.amberAccent,
                      size: Responsive.sp(20),
                    ),

                    SizedBox(width: Responsive.w(10)),

                    Expanded(
                      child: Text(
                        enrolled
                            ? "Biometric authentication is active."
                            : "Biometric enrollment required.",
                        style: AppTextStyles.body.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
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

  const _InfoChip({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: Responsive.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(
          Responsive.radius(12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [

          Icon(
            icon,
            size: Responsive.sp(16),
            color: Colors.white,
          ),

          SizedBox(width: Responsive.w(6)),

          Text(
            text,
            style: AppTextStyles.caption.copyWith(
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}