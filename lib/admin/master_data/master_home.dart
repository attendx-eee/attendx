import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../attendance/models/attendance_marker.dart';
import '../../attendance/screens/student_directory_screen.dart';
import '../../attendance/services/attendance_permission_service.dart';
import '../../core/auth/account_lookup.dart';
import '../../core/constants/app_config.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/section_header.dart';
import '../screens/faculty_screen.dart';
import '../screens/room_screen.dart';
import '../screens/lab_screen.dart';
import '../screens/subject_screen.dart';
import '../screens/time_slot_screen.dart';
import '../screens/timetable_management_screen.dart';
import '../screens/cr_approval_screen.dart';
import '../screens/cr_directory_screen.dart';
import '../screens/profile_change_approval_screen.dart';
import '../screens/attendance_analysis_screen.dart';
import '../screens/attendance_insights_screen.dart';
import '../screens/attendance_permission_screen.dart';
import '../screens/batch_screen.dart';
import '../screens/faculty_approval_screen.dart';
import '../screens/holiday_screen.dart';
import '../widgets/admin_hero_header.dart';
import '../widgets/master_tile.dart';

/// Admin home.
///
/// Deliberately knows nothing about how the app signs someone out. The
/// mobile app routes back through RoleRouter's login screen, which drags
/// in the whole student tree — face enrollment, the camera, `dart:io` —
/// none of which compiles for the web. Taking the logout as a callback
/// keeps this screen (and every admin screen under it) buildable on both
/// targets from one codebase.
class MasterHome extends StatelessWidget {
  /// Invoked when the admin confirms logout. When null, the logout
  /// action is hidden entirely.
  final Future<void> Function(BuildContext context)? onLogout;

  const MasterHome({super.key, this.onLogout});

  /// Live count of `students` docs where [field] == 'pending' — powers
  /// the quick-stat cards and the red badges on the Approvals tiles, so
  /// nothing waiting on the admin ever goes unnoticed.
  Stream<int> _pendingCount(String field) => FirebaseFirestore.instance
      .collection(AccountLookup.students)
      .where(field, isEqualTo: 'pending')
      .snapshots()
      .map((snap) => snap.docs.length);

  /// Staff who have signed up but aren't approved yet.
  ///
  /// Filtered client-side rather than with a `where`: faculty_accounts
  /// holds only faculty, so the whole collection is the candidate set
  /// and it's a handful of documents.
  Stream<int> _pendingFacultyCount() => FirebaseFirestore.instance
      .collection(AccountLookup.facultyAccounts)
      .snapshots()
      .map((snap) => snap.docs
          .where((d) => (d.data()['facultyStatus'] ?? 'pending') == 'pending')
          .length);

  /// Guard against accidental logout — always confirm first.
  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            icon: const Icon(Icons.logout_rounded,
                color: Colors.redAccent, size: 36),
            title: const Text("Logout of Admin?",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text("Logout"),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmed && context.mounted) {
      await onLogout!(context);
    }
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  /// The admin browsing the student directory — full access to all four
  /// years and no per-month gate.
  AttendanceMarker get _adminMarker {
    final user = FirebaseAuth.instance.currentUser;
    return AttendanceMarker.admin(
      uid: user?.uid ?? '',
      name: user?.displayName?.trim().isNotEmpty == true
          ? user!.displayName!.trim()
          : 'Admin',
    );
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Master Data"),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          // Logout is shown only when this is the admin's root screen.
          if (onLogout != null && !Navigator.of(context).canPop())
            IconButton(
              tooltip: "Logout",
              icon: const Icon(Icons.logout_rounded),
              onPressed: () => _confirmLogout(context),
            ),
        ],
      ),
      body: MaxWidthBody(
        child: ListView(
        padding: EdgeInsets.fromLTRB(
          Responsive.w(18),
          Responsive.h(8),
          Responsive.w(18),
          Responsive.h(32),
        ),
        children: [
          AdminHeroHeader(department: AppConfig.department),

          SizedBox(height: Responsive.h(20)),

          Row(
            children: [
              Expanded(
                child: _LiveStatCard(
                  stream: _pendingCount('crStatus'),
                  icon: Icons.how_to_reg_rounded,
                  label: "CR Requests",
                  color: AppColors.warning,
                  onTap: () => _open(context, const CrApprovalScreen()),
                ),
              ),
              SizedBox(width: Responsive.w(14)),
              Expanded(
                child: _LiveStatCard(
                  stream: _pendingCount('profileChangeStatus'),
                  icon: Icons.badge_outlined,
                  label: "Profile Changes",
                  color: AppColors.primary,
                  onTap: () =>
                      _open(context, const ProfileChangeApprovalScreen()),
                ),
              ),
            ],
          ),

          SizedBox(height: Responsive.h(28)),

          const SectionHeader(
            title: "Overview",
            subtitle: "Attendance trends at a glance",
          ),
          SizedBox(height: Responsive.h(14)),

          MasterTile(
            icon: Icons.insights_rounded,
            title: "Attendance Insights",
            subtitle: "Check-ins, late arrivals & 7-day trend",
            color: AppColors.success,
            onTap: () => _open(context, const AttendanceInsightsScreen()),
          ),

          MasterTile(
            icon: Icons.query_stats_rounded,
            title: "Attendance Analysis",
            subtitle: "Month & year breakdown, ranked and exportable",
            color: AppColors.teal,
            onTap: () => _open(context, const AttendanceAnalysisScreen()),
          ),

          MasterTile(
            icon: Icons.fact_check_outlined,
            title: "Students & Attendance",
            subtitle: "Browse by year, search, and mark attendance",
            color: AppColors.primary,
            onTap: () => _open(
              context,
              StudentDirectoryScreen(marker: _adminMarker),
            ),
          ),

          SizedBox(height: Responsive.h(14)),
          const SectionHeader(
            title: "Approvals",
            subtitle: "Requests waiting on a decision",
          ),
          SizedBox(height: Responsive.h(14)),

          StreamBuilder<int>(
            stream: _pendingFacultyCount(),
            builder: (context, snapshot) => MasterTile(
              icon: Icons.school_rounded,
              title: "Faculty Approvals",
              subtitle: "Confirm staff sign-ups and link them to the "
                  "timetable",
              color: AppColors.warning,
              badgeCount: snapshot.data,
              onTap: () => _open(context, const FacultyApprovalScreen()),
            ),
          ),

          StreamBuilder<int>(
            stream: AttendancePermissionService.instance.pendingCount(),
            builder: (context, snapshot) => MasterTile(
              icon: Icons.event_available_rounded,
              title: "CR Attendance Access",
              subtitle: "Let a CR mark attendance for a month",
              color: AppColors.warning,
              badgeCount: snapshot.data,
              onTap: () =>
                  _open(context, const AttendancePermissionScreen()),
            ),
          ),

          StreamBuilder<int>(
            stream: _pendingCount('crStatus'),
            builder: (context, snapshot) => MasterTile(
              icon: Icons.how_to_reg_rounded,
              title: "CR Approvals",
              subtitle: "Approve Class Representative requests",
              color: AppColors.warning,
              badgeCount: snapshot.data,
              onTap: () => _open(context, const CrApprovalScreen()),
            ),
          ),

          StreamBuilder<int>(
            stream: _pendingCount('profileChangeStatus'),
            builder: (context, snapshot) => MasterTile(
              icon: Icons.badge_outlined,
              title: "Profile Change Requests",
              subtitle: "Approve student name/year change requests",
              color: AppColors.warning,
              badgeCount: snapshot.data,
              onTap: () =>
                  _open(context, const ProfileChangeApprovalScreen()),
            ),
          ),

          SizedBox(height: Responsive.h(14)),
          const SectionHeader(
            title: "People & Contacts",
            subtitle: "Staff and class representatives",
          ),
          SizedBox(height: Responsive.h(14)),

          MasterTile(
            icon: Icons.contact_phone_rounded,
            title: "CR Directory",
            subtitle: "Contact CRs by year — call directly",
            color: AppColors.teal,
            onTap: () => _open(context, const CrDirectoryScreen()),
          ),

          MasterTile(
            icon: Icons.people_alt_rounded,
            title: "Faculty Management",
            subtitle: "Manage teaching staff",
            color: AppColors.teal,
            onTap: () => _open(context, const FacultyScreen()),
          ),

          SizedBox(height: Responsive.h(14)),
          const SectionHeader(
            title: "Academic Setup",
            subtitle: "Subjects, rooms, batches & timing",
          ),
          SizedBox(height: Responsive.h(14)),

          GridView.count(
            // Two across on a phone, wider on a browser — six launcher
            // tiles stacked 2-wide would leave most of a desktop window
            // empty.
            crossAxisCount:
                Responsive.gridColumns(mobile: 2, tablet: 3, desktop: 3),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: Responsive.w(14),
            mainAxisSpacing: Responsive.h(14),
            childAspectRatio: 1.0,
            children: [
              _GridTile(
                icon: Icons.menu_book_rounded,
                title: "Subjects",
                color: AppColors.primary,
                onTap: () => _open(context, const SubjectScreen()),
              ),
              _GridTile(
                icon: Icons.science_rounded,
                title: "Labs",
                color: AppColors.primary,
                onTap: () => _open(context, const LabScreen()),
              ),
              _GridTile(
                icon: Icons.meeting_room_rounded,
                title: "Rooms",
                color: AppColors.primary,
                onTap: () => _open(context, const RoomScreen()),
              ),
              _GridTile(
                icon: Icons.groups_rounded,
                title: "Batches",
                color: AppColors.primary,
                onTap: () => _open(context, const BatchScreen()),
              ),
              _GridTile(
                icon: Icons.beach_access_rounded,
                title: "Holidays",
                color: AppColors.primary,
                onTap: () => _open(context, const HolidayScreen()),
              ),
              _GridTile(
                icon: Icons.schedule_rounded,
                title: "Time Slots",
                color: AppColors.primary,
                onTap: () => _open(context, const TimeSlotScreen()),
              ),
              _GridTile(
                icon: Icons.calendar_month_rounded,
                title: "Timetables",
                color: AppColors.primary,
                onTap: () =>
                    _open(context, const TimetableManagementScreen()),
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }
}

/// Quick-stat card driven by a live Firestore count — tappable straight
/// into the relevant approval screen.
class _LiveStatCard extends StatelessWidget {
  final Stream<int> stream;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _LiveStatCard({
    required this.stream,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          onTap: onTap,
          child: Padding(
            padding: Responsive.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CircleAvatar(
                      radius: Responsive.w(20),
                      backgroundColor: color.withValues(alpha: .12),
                      child: Icon(icon, color: color, size: Responsive.sp(20)),
                    ),
                    StreamBuilder<int>(
                      stream: stream,
                      builder: (context, snapshot) {
                        final count = snapshot.data;
                        if (count == null) {
                          return SizedBox(
                            height: Responsive.w(16),
                            width: Responsive.w(16),
                            child: const CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.textSecondary),
                          );
                        }
                        if (count == 0) {
                          return Icon(Icons.check_circle_rounded,
                              color: AppColors.success,
                              size: Responsive.sp(20));
                        }
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "$count pending",
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                SizedBox(height: Responsive.h(14)),
                StreamBuilder<int>(
                  stream: stream,
                  builder: (context, snapshot) => Text(
                    (snapshot.data ?? 0).toString(),
                    style: AppTextStyles.headline.copyWith(color: color),
                  ),
                ),
                SizedBox(height: Responsive.h(2)),
                Text(label, style: AppTextStyles.caption),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact icon launcher tile for the lower-priority "Academic Setup"
/// items — a denser, app-launcher-style grid so the six management
/// screens don't dominate the page the way full-width rows would.
class _GridTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _GridTile({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: Padding(
            padding: Responsive.symmetric(horizontal: 10, vertical: 16),
            // Icon-led, centered layout: the icon carries the meaning at
            // a glance, and the label sits underneath with room to wrap
            // to two lines instead of clipping on longer names like
            // "Time Slots" or "Timetables".
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(Responsive.w(14)),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withValues(alpha: .18),
                        color.withValues(alpha: .07),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: Responsive.sp(28)),
                ),
                SizedBox(height: Responsive.h(10)),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title.copyWith(
                    fontSize: Responsive.sp(13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
