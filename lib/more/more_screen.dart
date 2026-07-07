import 'package:flutter/material.dart';

import '../core/responsive/responsive.dart';
import '../core/theme/app_spacing.dart';

import '../screens/profile.dart';
import '../screens/attendance/attendance_screen.dart';
import '../screens/face_enrollment_screen.dart';
import '../notifications/notification_screen.dart';
import '../screens/login.dart';

import '../services/auth_service.dart';

import 'models/more_item.dart';
import 'widgets/more_profile_card.dart';
import 'widgets/more_section.dart';
import 'widgets/storage_card.dart';
import '../core/theme/app_colors.dart';

class MoreScreen extends StatelessWidget {
  final Map<String, dynamic> student;

  const MoreScreen({
    super.key,
    required this.student,
  });

  Future<bool> _logoutDialog(BuildContext context) async {
    return await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Text("Logout"),
            content: const Text(
              "Are you sure you want to logout from AttendX?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Logout"),
              )
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final AuthService authService = AuthService();

    final accountItems = <MoreItem>[
      MoreItem(
        title: "Profile",
        subtitle: "View and edit profile",
        icon: Icons.person_outline,
        iconColor: AppColors.primary,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileScreen(
                studentRawData: student,
              ),
            ),
          );
        },
      ),
      MoreItem(
        title: "Notifications",
        subtitle: "Recent alerts",
        icon: Icons.notifications_outlined,
        iconColor: Colors.orange,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const NotificationScreen(),
            ),
          );
        },
      ),
      MoreItem(
        title: "Face Enrollment",
        subtitle: "Update biometric profile",
        icon: Icons.face_retouching_natural,
        iconColor: Colors.green,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const FaceEnrollmentScreen(),
            ),
          );
        },
      ),
    ];

    final academicItems = <MoreItem>[
      MoreItem(
        title: "Attendance",
        subtitle: "View attendance history",
        icon: Icons.fact_check_outlined,
        iconColor: Colors.blue,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AttendanceScreen(),
            ),
          );
        },
      ),
      const MoreItem(
        title: "Timetable",
        subtitle: "Coming soon",
        icon: Icons.calendar_month_outlined,
        iconColor: Colors.deepPurple,
      ),
      const MoreItem(
        title: "Leave Requests",
        subtitle: "Coming soon",
        icon: Icons.assignment_outlined,
        iconColor: Colors.teal,
      ),
      const MoreItem(
        title: "Subjects",
        subtitle: "Coming soon",
        icon: Icons.menu_book_outlined,
        iconColor: Colors.brown,
      ),
    ];

    final applicationItems = <MoreItem>[
      const MoreItem(
        title: "Appearance",
        subtitle: "Theme & personalization",
        icon: Icons.palette_outlined,
        iconColor: Colors.purple,
      ),
      const MoreItem(
        title: "Language",
        subtitle: "English",
        icon: Icons.language,
        iconColor: Colors.blueAccent,
      ),
      const MoreItem(
        title: "About AttendX",
        subtitle: "Version information",
        icon: Icons.info_outline,
        iconColor: AppColors.primary,
      ),
    ];

    final supportItems = <MoreItem>[
      const MoreItem(
        title: "Help Center",
        subtitle: "FAQs & Support",
        icon: Icons.help_outline,
        iconColor: Colors.orange,
      ),
      const MoreItem(
        title: "Privacy Policy",
        subtitle: "Terms & Privacy",
        icon: Icons.privacy_tip_outlined,
        iconColor: Colors.green,
      ),
      MoreItem(
        title: "Logout",
        subtitle: "End current session",
        icon: Icons.logout_rounded,
        iconColor: Colors.red,
        isDestructive: true,
        onTap: () async {
          if (await _logoutDialog(context)) {
            await authService.logoutUser();

            if (!context.mounted) return;

            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (_) => const LoginScreen(),
              ),
              (route) => false,
            );
          }
        },
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          "More",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: Responsive.sp(20),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: Responsive.all(AppSpacing.md),
          child: Column(
            children: [

              MoreProfileCard(
                student: student,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(
                        studentRawData: student,
                      ),
                    ),
                  );
                },
              ),

              SizedBox(height: Responsive.h(24)),

              MoreSection(
                title: "Account",
                items: accountItems,
              ),

              MoreSection(
                title: "Academics",
                items: academicItems,
              ),

              MoreSection(
                title: "Application",
                items: applicationItems,
              ),

              StorageCard(
                cacheSizeMB: 12.4,
                databaseSizeMB: 6.8,
                imagesSizeMB: 18.2,
                onClearCache: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Cache clearing will be implemented.",
                      ),
                    ),
                  );
                },
              ),

              SizedBox(height: Responsive.h(28)),

              MoreSection(
                title: "Support",
                items: supportItems,
              ),

              SizedBox(height: Responsive.h(20)),

              Text(
                "AttendX v1.0.0",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: Responsive.sp(12),
                ),
              ),

              SizedBox(height: Responsive.h(30)),
            ],
          ),
        ),
      ),
    );
  }
}