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

  /// Sentinel returned by [_resolveRole] when a signed-in account has no
  /// `students/{uid}` doc at all — an incomplete registration (see
  /// RegisterScreen/FaceEnrollmentScreen: the profile is only saved once
  /// face enrollment succeeds). This happens if the app was force-closed,
  /// crashed, or otherwise left mid-enrollment without going through the
  /// explicit "Cancel Registration" flow.
  static const String _incompleteRegistration = '__incomplete_registration__';

  Future<String> _resolveRole() async {
    final uid = overrideUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 'student';

    final doc = await FirestoreService().getStudent(uid);
    if (!doc.exists) {
      // Only clean up for the real signed-in session, never for a
      // (currently unused, but defensive) admin-preview overrideUid.
      if (overrideUid == null) {
        try {
          await FirebaseAuth.instance.currentUser?.delete();
        } catch (_) {
          await FirebaseAuth.instance.signOut();
        }
      }
      return _incompleteRegistration;
    }

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

        if (snapshot.data == _incompleteRegistration) {
          return const LoginScreen();
        }

        if (isAdminRole(snapshot.data!)) {
          // MasterHome can't reach the login screen itself without
          // pulling the student tree in behind it, so the mobile app
          // hands it the way back.
          return MasterHome(onLogout: signOutToLogin);
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
