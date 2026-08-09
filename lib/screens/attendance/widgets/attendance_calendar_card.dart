import 'package:flutter/material.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/attendance_palette.dart';

class AttendanceCalendarCard extends StatelessWidget {
  /// Month being displayed.
  final int year;
  final int month;
  final String monthLabel;

  /// day-of-month -> 'present' | 'partial' | 'absent' | 'late' | 'today'
  final Map<int, String> dayStatuses;

  /// day-of-month -> "1/2", shown under the date.
  ///
  /// A colour alone can't tell you whether a partial day was one class
  /// out of two or five out of six, and that difference is the whole
  /// point of counting periods instead of days.
  final Map<int, String> dayFractions;

  /// day-of-month -> 0..1, how much of the day was attended. Drives the
  /// shade so a 5-of-6 day reads greener than a 1-of-6 one.
  final Map<int, double> dayRatios;

  /// day-of-month -> why the college was closed.
  final Map<int, String> dayHolidays;

  const AttendanceCalendarCard({
    super.key,
    required this.year,
    required this.month,
    required this.monthLabel,
    this.dayStatuses = const {},
    this.dayFractions = const {},
    this.dayRatios = const {},
    this.dayHolidays = const {},
  });

  @override
  Widget build(BuildContext context) {
    // Grid offset so day 1 lands under its weekday (header starts Sunday).
    final firstWeekdayOffset = DateTime(year, month, 1).weekday % 7;
    final daysInMonth = DateTime(year, month + 1, 0).day;

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
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (_, index) {

              if (index < firstWeekdayOffset) {
                return const SizedBox();
              }

              final day = index - firstWeekdayOffset + 1;

              Color color = Colors.transparent;
              Color text = Colors.black87;
              final fraction = dayFractions[day];
              final holiday = dayHolidays[day];

              switch (dayStatuses[day]) {
                case 'present':
                  color = Colors.green;
                  text = Colors.white;
                  break;
                case 'partial':
                  color = attendanceShade(dayRatios[day] ?? .5);
                  text = Colors.white;
                  break;
                case 'absent':
                  color = Colors.red;
                  text = Colors.white;
                  break;
                case 'late':
                  color = Colors.orange;
                  text = Colors.white;
                  break;
                case 'today':
                  color = Colors.blue;
                  text = Colors.white;
                  break;
              }

              // A closed day outranks whatever the gate recorded — the
              // college wasn't open, so there was nothing to attend.
              if (holiday != null) {
                color = holidayFill;
                text = Colors.white;
              }

              return Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(
                    Responsive.radius(10),
                  ),
                  border: Border.all(
                    color: Colors.grey.shade300,
                  ),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "$day",
                      style: TextStyle(
                        color: text,
                        fontWeight: FontWeight.w600,
                        fontSize: Responsive.sp(12),
                      ),
                    ),
                    if (holiday != null)
                      Icon(Icons.beach_access_rounded,
                          size: Responsive.sp(9), color: Colors.white)
                    else if (fraction != null)
                      Text(
                        fraction,
                        maxLines: 1,
                        style: TextStyle(
                          color: color == Colors.transparent
                              ? Colors.grey
                              : Colors.white70,
                          fontWeight: FontWeight.w600,
                          fontSize: Responsive.sp(8),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),

          SizedBox(height: Responsive.h(20)),

          Wrap(
            spacing: Responsive.w(16),
            runSpacing: Responsive.h(12),
            children: [

              const _Legend(
                Colors.green,
                "All classes",
              ),

              _Legend(
                attendanceShade(.5),
                "Part of the day",
              ),

              const _Legend(
                holidayFill,
                "Holiday",
              ),

              const _Legend(
                Colors.red,
                "Absent",
              ),

              const _Legend(
                Colors.orange,
                "Late",
              ),

              const _Legend(
                Colors.blue,
                "Today",
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