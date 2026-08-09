import 'package:flutter/material.dart';
import '../../../attendance/models/day_summary.dart';
import '../../../attendance/widgets/attendance_day_tile.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/attendance_palette.dart';

class AttendanceCalendarCard extends StatelessWidget {
  /// Month being displayed.
  final int year;
  final int month;
  final String monthLabel;

  /// day-of-month -> 'present' | 'absent' | 'late' | 'today'
  ///
  /// The gate verdict. Used only where there are no class registers to
  /// be more specific with.
  final Map<int, String> dayStatuses;

  /// day-of-month -> per-class counts. Drives the theory/lab split.
  final Map<int, DaySummary> daySummaries;

  /// day-of-month -> why the college was closed.
  final Map<int, String> dayHolidays;

  const AttendanceCalendarCard({
    super.key,
    required this.year,
    required this.month,
    required this.monthLabel,
    this.dayStatuses = const {},
    this.daySummaries = const {},
    this.dayHolidays = const {},
  });

  @override
  Widget build(BuildContext context) {
    // Grid offset so day 1 lands under its weekday (header starts Sunday).
    final firstWeekdayOffset = DateTime(year, month, 1).weekday % 7;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final today = DateTime.now();

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
                "Attendance Calendar",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: Responsive.sp(18),
                ),
              ),

              const Spacer(),

              Text(
                monthLabel,
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: Responsive.sp(13),
                ),
              ),
            ],
          ),

          SizedBox(height: Responsive.h(20)),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              _WeekDay("S"),
              _WeekDay("M"),
              _WeekDay("T"),
              _WeekDay("W"),
              _WeekDay("T"),
              _WeekDay("F"),
              _WeekDay("S"),
            ],
          ),

          SizedBox(height: Responsive.h(14)),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: firstWeekdayOffset + daysInMonth,
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              // Slightly taller than wide: the split tile stacks an icon
              // over a fraction, and a square leaves no room for either.
              childAspectRatio: .82,
            ),
            itemBuilder: (_, index) {

              if (index < firstWeekdayOffset) {
                return const SizedBox();
              }

              final day = index - firstWeekdayOffset + 1;

              final (Color fill, Color text) = switch (dayStatuses[day]) {
                'present' => (AppColors.success, Colors.white),
                'absent' => (AppColors.danger, Colors.white),
                'late' => (AppColors.warning, Colors.white),
                'today' => (AppColors.primary, Colors.white),
                _ => (Colors.transparent, AppColors.textPrimary),
              };

              return AttendanceDayTile(
                day: day,
                summary: daySummaries[day],
                holidayName: dayHolidays[day],
                fallbackFill: fill,
                fallbackText: text,
                isToday: day == today.day &&
                    month == today.month &&
                    year == today.year,
              );
            },
          ),

          SizedBox(height: Responsive.h(20)),

          Wrap(
            spacing: Responsive.w(16),
            runSpacing: Responsive.h(12),
            children: [

              const _Legend(AppColors.success, "All attended"),

              _Legend(attendanceShade(.5), "Part attended"),

              const _Legend(AppColors.danger, "None attended"),

              const _Legend(Colors.white, "Not registered yet"),

              const _Legend(holidayFill, "Holiday"),

              const _Legend(AppColors.warning, "Late"),
            ],
          ),

          SizedBox(height: Responsive.h(12)),

          Row(
            children: [
              Icon(Icons.menu_book_rounded,
                  size: Responsive.sp(13), color: AppColors.textSecondary),
              SizedBox(width: Responsive.w(4)),
              Text("Theory", style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: Responsive.sp(11),
                fontWeight: FontWeight.w500,
              )),
              SizedBox(width: Responsive.w(14)),
              Icon(Icons.science_rounded,
                  size: Responsive.sp(13), color: AppColors.textSecondary),
              SizedBox(width: Responsive.w(4)),
              Text("Lab", style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: Responsive.sp(11),
                fontWeight: FontWeight.w500,
              )),
              SizedBox(width: Responsive.w(10)),
              Expanded(
                child: Text(
                  "A day with both is split down the middle.",
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: Responsive.sp(10.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeekDay extends StatelessWidget {

  final String day;

  const _WeekDay(this.day);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          day,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            fontSize: Responsive.sp(12),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {

  final Color color;
  final String label;

  const _Legend(this.color, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [

        Container(
          width: Responsive.w(14),
          height: Responsive.w(14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(
              Responsive.radius(4),
            ),
            border: Border.all(color: Colors.grey.shade300),
          ),
        ),

        SizedBox(width: Responsive.w(8)),

        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w500,
            fontSize: Responsive.sp(12),
          ),
        ),
      ],
    );
  }
}
