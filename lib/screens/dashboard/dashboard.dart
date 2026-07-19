import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../services/attendance_service.dart';
import '../../services/firestore_service.dart';
import '../login.dart';
import '../profile.dart';
import '../face_enrollment_screen.dart';
import '../full_timetable_screen.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_spacing.dart';
import 'widgets/hero_welcome_card.dart';
import 'widgets/dashboard_appbar.dart';
import 'widgets/attendance_alert_card.dart';
import 'widgets/attendance_stats_section.dart';
import 'widgets/attendance_overview_card.dart';
import 'widgets/today_attendance_card.dart';
import 'widgets/today_schedule_card.dart';
import 'widgets/notifications_preview_card.dart';
import 'widgets/quick_actions_grid.dart';
import '../attendance/attendance_screen.dart';
import '../../notifications/notification_screen.dart';
import '../../notifications/services/notification_service.dart';
import '../../notifications/services/local_notification_service.dart';
import '../../admin/master_data/master_home.dart';
import '../../admin/services/timetable_service.dart';
import '../../admin/models/period_model.dart';
import '../../core/constants/app_config.dart';
import '../../more/account_settings_screen.dart';
import '../../cr/cr_timetable_screen.dart';
import '../../timetable/models/timetable_override_model.dart';
import '../../timetable/services/timetable_override_service.dart';
import '../../core/theme/app_colors.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.overrideUid});

  final String? overrideUid;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AuthService authService = AuthService();
  final FirestoreService firestoreService = FirestoreService();
  final PageController _pageController = PageController(initialPage: 0);
  final FirebaseAuth auth = FirebaseAuth.instance;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> notifications = [];
  final NotificationService notificationService = NotificationService.instance;

  DocumentSnapshot<Map<String, dynamic>>? studentData;
  DocumentSnapshot<Map<String, dynamic>>? todayAttendance;

  bool isLoading = true;
  bool _enrollPromptShown = false;
  int _selectedMonthIndex = 0;

  /// 0 = today, 1 = next college day (swipe left/right to switch).
  int _scheduleDayIndex = 0;

  final List<String> semesterMonths = [
    "July",
    "August",
    "September",
    "October",
    "November",
    "December"
  ];

  /// Real attendance derived from Raspberry Pi check-in events,
  /// loaded in [loadStudent]. Keys always match [semesterMonths].
  Map<String, Map<String, int>> attendanceStats = {
    for (final m in [
      "July", "August", "September", "October", "November", "December"
    ])
      m: {"present": 0, "absent": 0, "total": 0, "late": 0},
  };

  @override
  void initState() {
    super.initState();
    loadStudent();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> loadStudent() async {
    try {
      final uid = widget.overrideUid ?? FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        throw Exception('No user context available.');
      }

      studentData = await firestoreService.getStudent(uid);
      final student = studentData?.data();

      // Each section loads independently — one failure (e.g. a missing
      // Firestore index) must not block the others or the enroll prompt.
      try {
        // Raw Pi check-in/check-out event for today.
        todayAttendance = await AttendanceService.instance.todayEvent(uid);
      } catch (e) {
        debugPrint("Today attendance load failed: $e");
      }

      try {
        // Monthly attendance computed from Pi events + timetable.
        if (student != null) {
          attendanceStats = await AttendanceService.instance.semesterStats(
            uid: uid,
            studentData: student,
            months: semesterMonths,
          );
        }
      } catch (e) {
        debugPrint("Attendance stats load failed: $e");
      }

      try {
        // No orderBy -> no composite index needed; sort client-side.
        final notificationSnapshot = await FirebaseFirestore.instance
            .collection("notifications")
            .where("studentUid", isEqualTo: uid)
            .get();

        final docs = notificationSnapshot.docs.toList()
          ..sort((a, b) {
            final ta = a.data()['createdAt'];
            final tb = b.data()['createdAt'];
            if (ta is! Timestamp) return 1;
            if (tb is! Timestamp) return -1;
            return tb.compareTo(ta);
          });

        notifications = docs.take(3).toList();
      } catch (e) {
        debugPrint("Notifications preview load failed: $e");
      }

      // Daily class reminders + realtime device alerts (students & CRs).
      if (student != null) {
        LocalNotificationService.instance.bootstrapForStudent(
          uid: uid,
          studentData: student,
        );
      }
    } catch (e) {
      debugPrint("Error loading dashboard: $e");
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
        // Always evaluated once the dashboard is visible.
        _maybePromptFaceEnrollment();
      }
    }
  }

  /// After login/registration: if the student hasn't enrolled their face
  /// yet, prompt them once so attendance marking works.
  /// (Skipped on web — enrollment needs the device camera + model.)
  void _maybePromptFaceEnrollment() {
    if (kIsWeb) return;
    if (_enrollPromptShown) return;

    final data = studentData?.data();
    if (data == null) return;

    final role = (data['role'] ?? 'student').toString().toLowerCase();
    if (role == 'hod' || role == 'office') return;
    if ((data['faceEnrolled'] ?? false) == true) return;

    _enrollPromptShown = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          icon: const Icon(Icons.face_retouching_natural_rounded,
              color: AppColors.primary, size: 44),
          title: const Text("Enroll Your Face",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: const Text(
            "Face enrollment is required for attendance marking and face login. It takes under a minute.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Later",
                  style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const FaceEnrollmentScreen()),
                );
                loadStudent();
              },
              icon: const Icon(Icons.face, size: 18),
              label: const Text("Enroll Now"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      );
    });
  }

  Future<bool> _showLogoutConfirmation() async {
    return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text("Confirm Logout",
                style: TextStyle(fontWeight: FontWeight.bold)),
            content: const Text(
                "Are you sure you want to end your active session on AttendX portal?"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancel")),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Logout",
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _getDayName(int weekday) {
    const days = [
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday",
      "Sunday"
    ];
    // weekday: 1 = Monday, 7 = Sunday
    return days[weekday - 1];
  }

  /// Today + the next college day (Sundays skipped, next day at midnight).
  List<DateTime> get _scheduleDates {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    var next = todayMidnight.add(const Duration(days: 1));
    while (next.weekday == DateTime.sunday) {
      next = next.add(const Duration(days: 1));
    }
    return [now, next];
  }

  /// Swipeable Today / Tomorrow schedule with a full-timetable shortcut.
  Widget _buildSchedulePager(Map<String, dynamic> data) {
    final dates = _scheduleDates;
    final date = dates[_scheduleDayIndex];
    final isToday = _scheduleDayIndex == 0;

    // "Tomorrow" unless the next college day is further away (Sun skip).
    final todayMidnight =
        DateTime(dates[0].year, dates[0].month, dates[0].day);
    final nextLabel = dates[1].difference(todayMidnight).inDays == 1
        ? "Tomorrow"
        : _getDayName(dates[1].weekday);

    return GestureDetector(
      // Swipe left -> tomorrow, swipe right -> today.
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -200 && _scheduleDayIndex == 0) {
          setState(() => _scheduleDayIndex = 1);
        } else if (velocity > 200 && _scheduleDayIndex == 1) {
          setState(() => _scheduleDayIndex = 0);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _scheduleDayTab("Today", 0),
              const SizedBox(width: 8),
              _scheduleDayTab(nextLabel, 1),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          FullTimetableScreen(studentData: data),
                    ),
                  );
                },
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                label: const Text("Full timetable"),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(
              key: ValueKey(_scheduleDayIndex),
              child: _scheduleForDate(
                data,
                date,
                markCompleted: isToday,
                title: isToday ? "Today's Schedule" : "$nextLabel's Schedule",
                subtitle: isToday
                    ? "Swipe left for $nextLabel"
                    : "Swipe right for today",
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scheduleDayTab(String label, int index) {
    final selected = _scheduleDayIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _scheduleDayIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// Live schedule for one date: base timetable + that date's CR overrides.
  Widget _scheduleForDate(
    Map<String, dynamic> data,
    DateTime date, {
    required bool markCompleted,
    required String title,
    required String subtitle,
  }) {
    return StreamBuilder<List<PeriodModel>>(
      stream: TimetableService.instance.watchDaySchedule(
        department: AppConfig.departmentOf(data),
        academicYear: AppConfig.academicYear,
        year: AppConfig.yearOf(data),
        day: _getDayName(date.weekday),
      ),
      builder: (context, scheduleSnapshot) {
        final periods = scheduleSnapshot.data ?? <PeriodModel>[];

        return StreamBuilder<List<TimetableOverride>>(
          stream: TimetableOverrideService.instance.watchForDate(
            department: AppConfig.departmentOf(data),
            academicYear: AppConfig.academicYear,
            year: AppConfig.yearOf(data),
            date: AppConfig.dateId(date),
          ),
          builder: (context, overrideSnapshot) {
            final overrides = {
              for (final o in overrideSnapshot.data ?? <TimetableOverride>[])
                o.periodNo: o
            };

            final classes = periods.map((period) {
              final override = overrides[period.periodNo];
              final replaced = override?.type == OverrideType.replacement;
              final roomChanged = override?.type == OverrideType.roomChange;

              // Completed only applies to today's schedule.
              final end = AppConfig.timeOn(date, period.endTime);
              final completed = markCompleted &&
                  end != null &&
                  DateTime.now().isAfter(end);

              return <String, dynamic>{
                "completed": completed,
                "start": period.startTime,
                "end": period.endTime,
                "subject": replaced ? override!.newSubject : period.subject,
                "faculty": replaced && override!.newFacultyName.isNotEmpty
                    ? override.newFacultyName
                    : period.facultyName,
                "room":
                    "${(replaced && override!.newRoom.isNotEmpty) || roomChanged ? override!.newRoom : period.room}"
                    "${period.batch.isEmpty ? '' : '  •  Batch ${period.batch}'}",
                "status": override?.type,
                "note": override?.note ?? '',
                "oldSubject": replaced ? period.subject : '',
                "oldRoom": roomChanged ? period.room : '',
              };
            }).toList();

            return TodayScheduleCard(
              classes: classes,
              title: title,
              subtitle: subtitle,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    if (isLoading) {
      return const Scaffold(
        body:
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (studentData == null || !studentData!.exists) {
      return const Scaffold(
        body: Center(
          child: Text("Student data not found"),
        ),
      );
    }

    final data = studentData!.data()!;
    final String role = (data['role'] ?? 'student').toString().toLowerCase();
    final bool isCR = role == 'cr';
    final bool isAdmin = role == 'hod' || role == 'office';

    final totalPresent = attendanceStats.values.fold(
      0,
      (acc, item) => acc + item["present"]!,
    );

    final totalAbsent = attendanceStats.values.fold(
      0,
      (acc, item) => acc + item["absent"]!,
    );

    final totalClasses = attendanceStats.values.fold(
      0,
      (acc, item) => acc + item["total"]!,
    );

    final attendancePercentage =
        totalClasses == 0 ? 0.0 : (totalPresent / totalClasses) * 100;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: DashboardAppBar(
        student: data,
        onProfileTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileScreen(
                studentRawData: data,
              ),
            ),
          ).then((_) => loadStudent());
        },
        onNotificationsTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const NotificationScreen(),
            ),
          );
        },
        onLogoutTap: () async {
          if (await _showLogoutConfirmation()) {
            await authService.logoutUser();
            if (!context.mounted) return;
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (_) => const LoginScreen(),
              ),
              (_) => false,
            );
          }
        },
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: Responsive.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Role-gated tools: Master Data for admins, timetable tools for CRs.
            if (isAdmin) ...[
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.admin_panel_settings,
                      color: AppColors.primary),
                  title: const Text(
                    "Master Data Management",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle:
                      const Text("Manage faculty, subjects, rooms & more"),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MasterHome(),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: Responsive.h(20)),
            ],

            if (!isCR && data['crStatus'] == 'pending') ...[
              Card(
                elevation: 0,
                color: Colors.orange.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.orange.shade200),
                ),
                child: const ListTile(
                  leading: Icon(Icons.hourglass_top_rounded,
                      color: Colors.orange),
                  title: Text(
                    "CR request pending",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                      "Waiting for admin approval. You'll be notified once decided."),
                ),
              ),
              SizedBox(height: Responsive.h(20)),
            ],

            if (isCR) ...[
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.edit_calendar_rounded,
                      color: AppColors.primary),
                  title: const Text(
                    "CR Timetable Tools",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                      "Cancel, replace or move classes — notifies your year instantly"),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CrTimetableScreen(studentData: data),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: Responsive.h(20)),
            ],

            AttendanceAlertCard(
              attendancePercentage: attendancePercentage,
            ),
            SizedBox(height: Responsive.h(20)),
            HeroWelcomeCard(
              student: data,
            ),
            SizedBox(height: Responsive.h(24)),

            NotificationsPreviewCard(
              notifications: notifications,
              onViewAll: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            AttendanceStatsSection(
              present: totalPresent,
              absent: totalAbsent,
              total: totalClasses,
            ),
            SizedBox(height: Responsive.h(24)),
            const SizedBox(height: 32),

            AttendanceOverviewCard(
              months: semesterMonths,
              selectedIndex: _selectedMonthIndex,
              pageController: _pageController,
              attendance: attendanceStats,
              onMonthChanged: (index) {
                setState(() {
                  _selectedMonthIndex = index;
                });
              },
            ),

            SizedBox(height: Responsive.h(24)),

            TodayAttendanceCard(
              attendanceDoc: todayAttendance,
            ),

            SizedBox(height: Responsive.h(24)),

            _buildSchedulePager(data),

            SizedBox(height: Responsive.h(24)),

            QuickActionsGrid(
              onAttendance: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AttendanceScreen(),
                  ),
                );
              },
              onSettings: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AccountSettingsScreen(student: data),
                  ),
                );
              },
              onLeave: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text("coming soon!"),
                      backgroundColor: Colors.orangeAccent),
                );
              },
              onReports: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text("coming soon!"),
                      backgroundColor: Colors.orangeAccent),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
