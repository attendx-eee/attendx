import 'package:flutter/material.dart';

import '../admin/models/period_model.dart';
import '../admin/services/timetable_service.dart';
import '../core/constants/app_config.dart';
import '../core/responsive/responsive.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radius.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/primary_card.dart';

/// Read-only full week timetable for the student's year (Mon-Sat).
class FullTimetableScreen extends StatefulWidget {
  final Map<String, dynamic> studentData;

  const FullTimetableScreen({super.key, required this.studentData});

  @override
  State<FullTimetableScreen> createState() => _FullTimetableScreenState();
}

class _FullTimetableScreenState extends State<FullTimetableScreen> {
  late final String _department = AppConfig.departmentOf(widget.studentData);
  late final int _year = AppConfig.yearOf(widget.studentData);

  final Map<String, List<PeriodModel>> _week = {};
  bool _loading = true;
  late String _selectedDay;

  @override
  void initState() {
    super.initState();
    // Open on today's weekday (Sunday falls back to Monday).
    final today = AppConfig.dayName(DateTime.now());
    _selectedDay = today == 'Sunday' ? 'Monday' : today;
    _loadWeek();
  }

  Future<void> _loadWeek() async {
    try {
      for (final day in AppConfig.weekDays) {
        final periods = await TimetableService.instance.getDaySchedule(
          department: _department,
          academicYear: AppConfig.academicYear,
          year: _year,
          day: day,
        );
        _week[day] =
            periods.where((p) => !p.isFree && p.subject.isNotEmpty).toList();
      }
    } catch (e) {
      debugPrint('Full timetable load failed: $e');
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final periods = _week[_selectedDay] ?? const <PeriodModel>[];
    final todayName = AppConfig.dayName(DateTime.now());

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Full Timetable",
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ------------------------------------------- day selector
          Container(
            color: AppColors.primary,
            padding: EdgeInsets.only(bottom: Responsive.h(14)),
            child: SizedBox(
              height: Responsive.h(44),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: Responsive.symmetric(horizontal: 16),
                itemCount: AppConfig.weekDays.length,
                separatorBuilder: (_, _) => SizedBox(width: Responsive.w(8)),
                itemBuilder: (context, index) {
                  final day = AppConfig.weekDays[index];
                  final selected = day == _selectedDay;
                  final isToday = day == todayName;

                  return GestureDetector(
                    onTap: () => setState(() => _selectedDay = day),
                    child: Container(
                      padding: Responsive.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white
                            : Colors.white.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Row(
                        children: [
                          Text(
                            day.substring(0, 3).toUpperCase(),
                            style: TextStyle(
                              fontSize: Responsive.sp(12),
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? AppColors.primary
                                  : Colors.white.withValues(alpha: .9),
                            ),
                          ),
                          if (isToday) ...[
                            SizedBox(width: Responsive.w(6)),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.teal
                                    : Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // --------------------------------------------- day schedule
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : periods.isEmpty
                    ? Center(
                        child: Text(
                          "No classes scheduled for $_selectedDay",
                          style: AppTextStyles.body,
                        ),
                      )
                    : ListView.separated(
                        padding: Responsive.all(20),
                        itemCount: periods.length,
                        separatorBuilder: (_, _) =>
                            SizedBox(height: Responsive.h(14)),
                        itemBuilder: (context, index) {
                          final p = periods[index];

                          return PrimaryCard(
                            child: Row(
                              children: [
                                Column(
                                  children: [
                                    Text(p.startTime,
                                        style: AppTextStyles.body),
                                    SizedBox(height: Responsive.h(4)),
                                    Text(p.endTime,
                                        style: AppTextStyles.caption),
                                  ],
                                ),
                                SizedBox(width: Responsive.w(16)),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(p.subject,
                                          style: AppTextStyles.title),
                                      SizedBox(height: Responsive.h(4)),
                                      Text(p.facultyName,
                                          style: AppTextStyles.body),
                                      Text(
                                        "${p.room}${p.batch.isEmpty ? '' : '  •  Batch ${p.batch}'}",
                                        style: AppTextStyles.caption,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: Responsive.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: (p.classType == 'Lab'
                                            ? AppColors.teal
                                            : AppColors.primary)
                                        .withValues(alpha: .1),
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.xs),
                                  ),
                                  child: Text(
                                    p.classType,
                                    style: TextStyle(
                                      fontSize: Responsive.sp(11),
                                      fontWeight: FontWeight.w700,
                                      color: p.classType == 'Lab'
                                          ? AppColors.tealDark
                                          : AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
