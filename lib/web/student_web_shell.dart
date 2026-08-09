import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_config.dart';
import '../core/responsive/responsive.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radius.dart';
import '../core/theme/app_text_styles.dart';
import '../notifications/notification_screen.dart';
import '../screens/attendance/attendance_screen.dart';
import '../screens/full_timetable_screen.dart';

/// The student web app's frame.
///
/// Four destinations, all read-only. It reuses the phone app's
/// attendance and timetable screens unchanged — those were already free
/// of the camera and `dart:io`, which is what made a web build possible
/// at all without forking half the app.
class StudentWebShell extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> student;

  const StudentWebShell({
    super.key,
    required this.uid,
    required this.student,
  });

  @override
  State<StudentWebShell> createState() => _StudentWebShellState();
}

class _StudentWebShellState extends State<StudentWebShell> {
  int _index = 0;

  late final List<_Destination> _destinations = [
    _Destination(
      label: 'Attendance',
      icon: Icons.fact_check_outlined,
      selected: Icons.fact_check_rounded,
      builder: (_) => const AttendanceScreen(),
    ),
    _Destination(
      label: 'Timetable',
      icon: Icons.calendar_view_week_outlined,
      selected: Icons.calendar_view_week_rounded,
      builder: (_) => FullTimetableScreen(studentData: widget.student),
    ),
    _Destination(
      label: 'Alerts',
      icon: Icons.notifications_none_rounded,
      selected: Icons.notifications_rounded,
      builder: (_) => const NotificationScreen(),
    ),
    _Destination(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      selected: Icons.person_rounded,
      builder: (_) => _ProfileTab(student: widget.student),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    // A phone gets a bottom bar, a laptop a side rail. Same screens
    // either way — the web app is mostly opened on an iPhone, but a
    // student checking from a library desktop shouldn't get a tall thin
    // column down the middle of a wide monitor.
    final wide = Responsive.screenWidth >= 720;

    final body = IndexedStack(
      index: _index,
      children: [
        for (final d in _destinations) Builder(builder: d.builder),
      ],
    );

    if (wide) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              backgroundColor: AppColors.surface,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.teal],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 22),
                    ),
                  ],
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: IconButton(
                      tooltip: 'Sign out',
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      icon: const Icon(Icons.logout_rounded,
                          color: AppColors.danger),
                    ),
                  ),
                ),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1, color: AppColors.divider),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: .12),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selected, color: AppColors.primary),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _Destination {
  final String label;
  final IconData icon;
  final IconData selected;
  final WidgetBuilder builder;

  const _Destination({
    required this.label,
    required this.icon,
    required this.selected,
    required this.builder,
  });
}

/// Read-only profile.
///
/// No photo picker and no "edit details" — both need a file picker and
/// an approval round-trip that belongs in the Android app. Changes go
/// through the office, which is also where the account was made.
class _ProfileTab extends StatelessWidget {
  final Map<String, dynamic> student;

  const _ProfileTab({required this.student});

  String _get(String key, [String fallback = '--']) {
    final v = (student[key] ?? '').toString().trim();
    return v.isEmpty ? fallback : v;
  }

  @override
  Widget build(BuildContext context) {
    final name = _get('name', 'Student');
    final photo = (student['profileImageUrl'] ?? '').toString();
    final faceEnrolled = student['faceEnrolled'] == true;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 8),
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: AppColors.primary.withValues(alpha: .1),
              child: ClipOval(
                child: photo.isNotEmpty
                    ? Image.network(photo,
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _initial(name))
                    : _initial(name),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(name,
              textAlign: TextAlign.center, style: AppTextStyles.headline),
          const SizedBox(height: 4),
          Text(
            '${_get('regNo')}  •  Year ${AppConfig.yearOf(student)}  •  '
            '${AppConfig.departmentOf(student)}',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 22),

          _card([
            _row(Icons.mail_outline_rounded, 'Email', _get('email')),
            _row(Icons.phone_outlined, 'Mobile', _get('mobile')),
            _row(Icons.school_outlined, 'Semester', _get('semester')),
            if (_get('batch', '') .isNotEmpty)
              _row(Icons.science_outlined, 'Lab batch', _get('batch')),
          ]),

          const SizedBox(height: 16),

          // Says plainly whether the gate can recognise them. A student
          // whose face was never enrolled will otherwise sit watching
          // their attendance not move and assume the app is broken.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (faceEnrolled ? AppColors.success : AppColors.warning)
                  .withValues(alpha: .10),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: (faceEnrolled ? AppColors.success : AppColors.warning)
                    .withValues(alpha: .35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  faceEnrolled
                      ? Icons.verified_user_rounded
                      : Icons.error_outline_rounded,
                  color:
                      faceEnrolled ? AppColors.success : AppColors.warning,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    faceEnrolled
                        ? 'Your face is enrolled — the gate scanner can '
                            'recognise you.'
                        : 'Your face is not enrolled yet, so the scanner '
                            'cannot mark you present. Visit the '
                            'department office to complete it.',
                    style: AppTextStyles.caption,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Web version',
                    style: AppTextStyles.caption
                        .copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  'This is the browser version of AttendX, for iPhone and '
                  'anyone who would rather not install an app. It shows '
                  'everything but cannot edit your details or enroll your '
                  'face — those need the Android app or the office.',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(
                  color: AppColors.danger.withValues(alpha: .4)),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _initial(String name) => Container(
        width: 88,
        height: 88,
        alignment: Alignment.center,
        color: AppColors.primary.withValues(alpha: .1),
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
      );

  Widget _card(List<Widget> rows) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(children: rows),
      );

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Text(label, style: AppTextStyles.caption),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      );
}
