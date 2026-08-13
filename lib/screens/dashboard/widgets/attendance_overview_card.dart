import 'package:flutter/material.dart';

import '../../../attendance/models/day_summary.dart';
import '../../../attendance/services/semester_totals_service.dart';
import '../../../attendance/widgets/month_totals_card.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/widgets/section_header.dart';
import 'month_selector.dart';

/// Month-by-month attendance, counted in classes.
///
/// This used to show days present, days absent and late for the chosen
/// month, on a gradient card. Two problems with that. Days had stopped
/// being the unit attendance is actually kept in — a student who made
/// one of three classes counted as a present day, same as one who made
/// all three. And it was the last screen still computing its own
/// figures, so it could and did disagree with the percentage at the top
/// of the same page.
///
/// It now renders exactly the card the office sees, from exactly the
/// same service, so "my app says 57%" and "the console says 57%" are
/// the same sentence.
class AttendanceOverviewCard extends StatelessWidget {
  /// Month labels, in semester order.
  final List<String> months;

  final int selectedIndex;

  final ValueChanged<int> onMonthChanged;

  /// Label -> that month's totals.
  final Map<String, AttendanceTotals> totals;

  /// Label -> what that month's timetable holds.
  final Map<String, MonthPlan> plans;

  const AttendanceOverviewCard({
    super.key,
    required this.months,
    required this.selectedIndex,
    required this.onMonthChanged,
    required this.totals,
    this.plans = const {},
  });

  @override
  Widget build(BuildContext context) {
    final label = months.isEmpty
        ? ''
        : months[selectedIndex.clamp(0, months.length - 1)];

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
          onChanged: onMonthChanged,
        ),
        SizedBox(height: Responsive.h(18)),
        MonthTotalsCard(
          label: label,
          totals: totals[label] ?? AttendanceTotals(),
          plan: plans[label] ?? const MonthPlan(),
        ),
      ],
    );
  }
}
