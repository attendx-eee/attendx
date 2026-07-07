import 'package:flutter/material.dart';

import '../../core/responsive/responsive.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_colors.dart';

class MoreProfileCard extends StatelessWidget {
  final Map<String, dynamic> student;
  final VoidCallback onTap;

  const MoreProfileCard({
    super.key,
    required this.student,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final String name = student["name"] ?? "Student";
    final String regNo = student["regNo"] ?? "--";
    final String branch = student["branch"] ?? "Department";
    final String semester = student["semester"]?.toString() ?? "";

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [
                Color(0xff3949AB),
                Color(0xff5C6BC0),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: .18),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: Responsive.all(AppSpacing.lg),
            child: Row(
              children: [

                Hero(
                  tag: "student_avatar",
                  child: CircleAvatar(
                    radius: Responsive.w(34),
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.person,
                      size: Responsive.sp(34),
                      color: AppColors.primary,
                    ),
                  ),
                ),

                SizedBox(width: Responsive.w(18)),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [

                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: Responsive.sp(18),
                        ),
                      ),

                      SizedBox(height: Responsive.h(4)),

                      Text(
                        branch,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: Responsive.sp(13),
                        ),
                      ),

                      SizedBox(height: Responsive.h(8)),

                      Wrap(
                        spacing: Responsive.w(10),
                        runSpacing: Responsive.h(6),
                        children: [

                          _chip(Icons.badge_outlined, regNo),

                          if (semester.isNotEmpty)
                            _chip(
                              Icons.school_outlined,
                              "Semester $semester",
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white70,
                  size: Responsive.sp(18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [

          Icon(
            icon,
            color: Colors.white,
            size: 14,
          ),

          const SizedBox(width: 5),

          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}