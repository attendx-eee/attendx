import 'package:flutter/material.dart';

import '../screens/faculty_screen.dart';
import '../screens/room_screen.dart';
import '../screens/lab_screen.dart';
import '../screens/subject_screen.dart';
import '../screens/time_slot_screen.dart';
import '../screens/timetable_management_screen.dart';
import '../screens/cr_approval_screen.dart';
import '../screens/attendance_insights_screen.dart';
import '../screens/batch_screen.dart';
import '../widgets/master_tile.dart';
import '../../screens/role_router.dart';

class MasterHome extends StatelessWidget {
  const MasterHome({super.key});

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
      await signOutToLogin(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Master Data"),
        actions: [
          // Logout is shown only when this is the admin's root screen.
          if (!Navigator.of(context).canPop())
            IconButton(
              tooltip: "Logout",
              icon: const Icon(Icons.logout_rounded),
              onPressed: () => _confirmLogout(context),
            ),
        ],
      ),

      body: ListView(
        padding: const EdgeInsets.all(18),

        children: [

          const SizedBox(height: 8),

          const Text(
            "Maintain academic resources",
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey,
            ),
          ),

          const SizedBox(height: 25),

          MasterTile(
            icon: Icons.insights,
            title: "Attendance Insights",
            subtitle: "Check-ins, late arrivals & 7-day trend",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AttendanceInsightsScreen(),
                ),
              );
            },
          ),

          MasterTile(
            icon: Icons.how_to_reg,
            title: "CR Approvals",
            subtitle: "Approve Class Representative requests",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CrApprovalScreen(),
                ),
              );
            },
          ),

          MasterTile(
            icon: Icons.people_alt,
            title: "Faculty Management",
            subtitle: "Manage teaching staff",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FacultyScreen(),
                ),
              );
            },
          ),

          MasterTile(
            icon: Icons.menu_book,
            title: "Subject Management",
            subtitle: "Manage all subjects",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SubjectScreen(),
                ),
              );
            },
          ),

          MasterTile(
            icon: Icons.science,
            title: "Lab Management",
            subtitle: "Manage all labs",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LabScreen(),
                ),
              );
            },
          ),

          MasterTile(
            icon: Icons.meeting_room,
            title: "Room Management",
            subtitle: "Manage classrooms & laboratories",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RoomScreen(),
                ),
              );
            },
          ),

          MasterTile(
            icon: Icons.groups,
            title: "Batch Management",
            subtitle: "Lab batches per year (Batch A, B, ...)",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BatchScreen(),
                ),
              );
            },
          ),

          MasterTile(
            icon: Icons.schedule,
            title: "Time Slot Management",
            subtitle: "Manage college timings",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const TimeSlotScreen(),
                ),
              );
            },
          ),

          MasterTile(
            icon: Icons.calendar_today,
            title: "Timetable Management",
            subtitle: "Create & manage timetables",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const TimetableManagementScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
