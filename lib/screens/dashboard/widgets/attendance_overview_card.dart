import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/widgets/section_header.dart';
import 'month_selector.dart';
import 'monthly_attendance_card.dart';

class AttendanceOverviewCard extends StatelessWidget {

  final List<String> months;

  final int selectedIndex;

  final ValueChanged<int> onMonthChanged;

  final PageController pageController;

  final Map<String, Map<String, int>> attendance;



  const AttendanceOverviewCard({
    super.key,
    required this.months,
    required this.selectedIndex,
    required this.onMonthChanged,
    required this.pageController,
    required this.attendance,
  });

  @override
  Widget build(BuildContext context) {

    return Column(

      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        const SectionHeader(
          title: "Monthly Attendance",
          subtitle: "Semester overview",
        ),

        SizedBox(height: Responsive.h(16)),

        MonthSelector(
          months: months,
          selectedIndex: selectedIndex,
          onChanged: (index) {
            onMonthChanged(index);

            pageController.animateToPage(
              index,
              duration:
                  const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          },
        ),

        SizedBox(height: Responsive.h(18)),

        SizedBox(
          height: Responsive.h(232),

          child: PageView.builder(

            controller: pageController,

            onPageChanged: onMonthChanged,

            itemCount: months.length,

            itemBuilder: (_, index) {

              final data =
                  attendance[months[index]]!;

              return MonthlyAttendanceCard(

                month: months[index],

                present: data["present"]!,

                absent: data["absent"]!,

                total: data["total"]!,

                late: data["late"] ?? 0,
              );
            },
          ),
        ),
      ],
    );
  }
}