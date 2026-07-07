import 'package:flutter/material.dart';

import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_colors.dart';

class SubjectAttendanceCard extends StatelessWidget {
  /// Real per-subject attendance computed from Pi events + timetable.
  final List<SubjectAttendance> subjects;

  const SubjectAttendanceCard({super.key, this.subjects = const []});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: Responsive.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          Responsive.radius(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Row(
            children: [

              Text(
                "Subject Attendance",
                style: TextStyle(
                  fontSize: Responsive.sp(18),
                  fontWeight: FontWeight.bold,
                ),
              ),

              const Spacer(),

              Icon(
                Icons.menu_book_rounded,
                color: AppColors.primary,
                size: Responsive.sp(22),
              ),
            ],
          ),

          SizedBox(height: Responsive.h(20)),

          if (subjects.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text("No subject data yet"),
              ),
            )
          else
            ...subjects.map(
              (subject) => Padding(
                padding: EdgeInsets.only(
                  bottom: Responsive.h(18),
                ),
                child: _SubjectTile(subject: subject),
              ),
            ),
        ],
      ),
    );
  }
}

class _SubjectTile extends StatelessWidget {
  final SubjectAttendance subject;

  const _SubjectTile({
    required this.subject,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [

        Row(
          children: [

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [

                  Text(
                    subject.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: Responsive.sp(14),
                    ),
                  ),

                  SizedBox(height: Responsive.h(2)),

                  Text(
                    subject.code,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: Responsive.sp(11),
                    ),
                  ),
                ],
              ),
            ),

            Text(
              "${subject.percentage}%",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: subject.color,
                fontSize: Responsive.sp(16),
              ),
            ),
          ],
        ),

        SizedBox(height: Responsive.h(10)),

        ClipRRect(
          borderRadius: BorderRadius.circular(
            Responsive.radius(20),
          ),
          child: LinearProgressIndicator(
            value: subject.percentage / 100,
            minHeight: Responsive.h(8),
            backgroundColor: Colors.grey.shade200,
            color: subject.color,
          ),
        ),
      ],
    );
  }
}

class SubjectAttendance {
  final String name;
  final String code;
  final int percentage;
  final Color color;

  SubjectAttendance(
    this.name,
    this.code,
    this.percentage,
    this.color,
  );
}