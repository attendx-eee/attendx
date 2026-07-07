import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../admin/master_data/master_home.dart';
import '../services/firestore_service.dart';
import 'dashboard/dashboard.dart';
import 'login.dart';

/// Routes the signed-in user to the right home based on their role:
///
/// - hod / office (admin)  -> Master Data Management only
/// - cr                    -> student dashboard + CR timetable tools
/// - student               -> student dashboard only
class RoleRouter extends StatelessWidget {
  final String? overrideUid;

  const RoleRouter({super.key, this.overrideUid});

  static bool isAdminRole(String role) => role == 'hod' || role == 'office';

  Future<String> _resolveRole() async {
    final uid = overrideUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 'student';

    final doc = await FirestoreService().getStudent(uid);
    if (!doc.exists) return 'student';

    return (doc.data()?['role'] ?? 'student').toString().toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _resolveRole(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (isAdminRole(snapshot.data!)) {
          return const MasterHome();
        }

        return DashboardScreen(overrideUid: overrideUid);
      },
    );
  }
}

/// Shared logout helper for root-level screens.
Future<void> signOutToLogin(BuildContext context) async {
  await FirebaseAuth.instance.signOut();
  if (!context.mounted) return;

  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (_) => false,
  );
}
