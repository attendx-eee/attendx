import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../admin/master_data/master_home.dart';
import '../admin/screens/attendance_analysis_screen.dart';
import '../admin/screens/attendance_insights_screen.dart';
import '../admin/screens/attendance_permission_screen.dart';
import '../admin/screens/cr_approval_screen.dart';
import '../admin/screens/cr_directory_screen.dart';
import '../admin/screens/profile_change_approval_screen.dart';
import '../admin/screens/release_announce_screen.dart';
import '../admin/screens/timetable_management_screen.dart';
import '../attendance/models/attendance_marker.dart';
import '../attendance/screens/student_directory_screen.dart';
import '../attendance/services/attendance_permission_service.dart';
import '../core/constants/app_config.dart';
import '../core/responsive/responsive.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radius.dart';
import '../core/theme/app_text_styles.dart';

class _Destination {
  final IconData icon;
  final String label;
  final Widget Function() build;

  /// Optional live badge (pending approvals).
  final Stream<int>? badge;

  const _Destination({
    required this.icon,
    required this.label,
    required this.build,
    this.badge,
  });
}

/// The admin console frame for wide screens.
///
/// On a browser the phone pattern — one screen at a time, everything
/// behind a back button — wastes the window and buries the screens an
/// admin actually lives in. A persistent side rail puts them one click
/// apart, which is what the Material adaptive guidance recommends once
/// there's room for it. Below the desktop breakpoint (a phone browser,
/// a narrow window) this collapses to the ordinary mobile layout, so
/// there's only one set of screens to maintain either way.
class AdminWebShell extends StatefulWidget {
  final VoidCallback onSignedOut;

  const AdminWebShell({super.key, required this.onSignedOut});

  @override
  State<AdminWebShell> createState() => _AdminWebShellState();
}

class _AdminWebShellState extends State<AdminWebShell> {
  int _index = 0;

  AttendanceMarker get _marker {
    final user = FirebaseAuth.instance.currentUser;
    return AttendanceMarker.admin(
      uid: user?.uid ?? '',
      name: user?.displayName?.trim().isNotEmpty == true
          ? user!.displayName!.trim()
          : 'Admin',
    );
  }

  /// Live count of student docs awaiting an admin decision on [field] —
  /// the same query that drives the badges on the mobile home.
  static Stream<int> _pendingStudents(String field) =>
      FirebaseFirestore.instance
          .collection('students')
          .where(field, isEqualTo: 'pending')
          .snapshots()
          .map((snap) => snap.docs.length);

  late final List<_Destination> _destinations = [
    _Destination(
      icon: Icons.dashboard_rounded,
      label: "Overview",
      // No logout callback: the shell owns sign-out in the rail, so
      // MasterHome shouldn't offer a second one.
      build: () => const MasterHome(),
    ),
    _Destination(
      icon: Icons.query_stats_rounded,
      label: "Analysis",
      build: () => const AttendanceAnalysisScreen(),
    ),
    _Destination(
      icon: Icons.fact_check_outlined,
      label: "Students",
      build: () => StudentDirectoryScreen(marker: _marker),
    ),
    _Destination(
      icon: Icons.insights_rounded,
      label: "Insights",
      build: () => const AttendanceInsightsScreen(),
    ),
    _Destination(
      icon: Icons.event_available_rounded,
      label: "CR Access",
      build: () => const AttendancePermissionScreen(),
      badge: AttendancePermissionService.instance.pendingCount(),
    ),
    _Destination(
      icon: Icons.how_to_reg_rounded,
      label: "CR Requests",
      build: () => const CrApprovalScreen(),
      badge: _pendingStudents('crStatus'),
    ),
    _Destination(
      icon: Icons.badge_outlined,
      label: "Profile Changes",
      build: () => const ProfileChangeApprovalScreen(),
      badge: _pendingStudents('profileChangeStatus'),
    ),
    _Destination(
      icon: Icons.contact_phone_rounded,
      label: "CR Directory",
      build: () => const CrDirectoryScreen(),
    ),
    _Destination(
      icon: Icons.calendar_month_rounded,
      label: "Timetables",
      build: () => const TimetableManagementScreen(),
    ),
    _Destination(
      icon: Icons.system_update_rounded,
      label: "Release",
      build: () => const ReleaseAnnounceScreen(),
    ),
  ];

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md)),
            icon: const Icon(Icons.logout_rounded,
                color: AppColors.danger, size: 34),
            title: const Text("Sign out of the admin console?"),
            content: const Text(
              "You'll need the admin secret key to sign back in.",
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("Stay"),
              ),
              FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text("Sign out"),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    await FirebaseAuth.instance.signOut();
    if (mounted) widget.onSignedOut();
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    // Narrow window (or a phone browser): fall back to the mobile
    // screens rather than squeezing a rail in beside them.
    if (!Responsive.isWide) {
      return MasterHome(onLogout: (_) async => _confirmSignOut());
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          _buildRail(),
          const VerticalDivider(width: 1, color: AppColors.divider),
          Expanded(
            // Keyed so switching destinations rebuilds the screen from
            // scratch instead of Flutter reusing state across two
            // different screens that happen to share a widget type.
            child: KeyedSubtree(
              key: ValueKey(_index),
              child: _destinations[_index].build(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRail() {
    return Container(
      width: 248,
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: const BoxDecoration(
                    gradient: AppColors.brandGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("AttendX",
                          style: AppTextStyles.title
                              .copyWith(fontSize: 17)),
                      Text(
                        "${AppConfig.department} Admin",
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 10),
              itemCount: _destinations.length,
              itemBuilder: (context, i) => _RailItem(
                destination: _destinations[i],
                selected: i == _index,
                onTap: () => setState(() => _index = i),
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Padding(
            padding: const EdgeInsets.all(12),
            child: ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm)),
              leading: const Icon(Icons.logout_rounded,
                  color: AppColors.danger, size: 20),
              title: const Text("Sign out",
                  style: TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
              onTap: _confirmSignOut,
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  const _RailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: .1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  destination.icon,
                  size: 20,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                if (destination.badge != null)
                  StreamBuilder<int>(
                    stream: destination.badge,
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      if (count == 0) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "$count",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
