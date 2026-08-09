import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// MasterHome is deliberately not imported. Admin is a web-only role
// now, so nothing in the phone build should be able to reach the
// console — and not importing it keeps the whole admin tree out of the
// student APK rather than merely hiding the button.
import '../core/auth/account_lookup.dart';
import '../faculty/models/faculty_account.dart';
import '../notifications/services/push_service.dart';
import '../faculty/screens/faculty_home.dart';
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

    // Admins and faculty live in their own collections now, so a
    // missing `students` doc no longer means "incomplete registration"
    // on its own — it's the normal state for both of them.
    final account = await AccountLookup.find(uid);
    if (account.isAdmin) return account.role;
    if (account.isFaculty) return 'faculty';

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
          // The console is a desktop tool, run from the department PC.
          // An admin account signing in here gets pointed at it rather
          // than a phone-sized copy of it — one place to administer
          // from, and one door to secure.
          return const _AdminOnWeb();
        }

        if (snapshot.data == 'faculty') {
          return _FacultyGate(
            uid: overrideUid ?? FirebaseAuth.instance.currentUser!.uid,
          );
        }

        return DashboardScreen(overrideUid: overrideUid);
      },
    );
  }
}

/// Shown when an admin account signs in on a phone.
class _AdminOnWeb extends StatelessWidget {
  const _AdminOnWeb();

  static const String consoleUrl =
      'https://attendx-eee.github.io/attendx/admin/';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.desktop_windows_rounded,
                  size: 46, color: Colors.blueGrey),
              const SizedBox(height: 18),
              const Text(
                'Admin runs on the web',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const SizedBox(height: 10),
              const Text(
                'Open the console on your computer to manage attendance, '
                'timetables and approvals.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 14),
              const SelectableText(
                consoleUrl,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue),
              ),
              const SizedBox(height: 26),
              OutlinedButton.icon(
                onPressed: () => signOutToLogin(context),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loads the faculty profile before showing their home.
///
/// FacultyHome needs the whole account — chiefly `facultyId`, which is
/// what matches them to periods on the timetable — and RoleRouter only
/// resolved the role string. One extra read, on a screen that is then
/// stable for the rest of the session.
class _FacultyGate extends StatelessWidget {
  final String uid;

  const _FacultyGate({required this.uid});

  @override
  Widget build(BuildContext context) {
    // Goes through AccountLookup rather than straight to a collection,
    // so a faculty member whose record hasn't been migrated out of
    // `students` yet still reaches their dashboard.
    return FutureBuilder<Account>(
      future: AccountLookup.find(uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final account = snapshot.data!;
        if (!account.exists) {
          return const Scaffold(
            body: Center(child: Text('Staff record not found.')),
          );
        }

        return FacultyHome(
          account: FacultyAccount.fromMap(uid, account.data),
          onLogout: signOutToLogin,
        );
      },
    );
  }
}

/// Shared logout helper for root-level screens.
Future<void> signOutToLogin(BuildContext context) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid != null) await PushService.instance.stop(uid);

  await FirebaseAuth.instance.signOut();
  if (!context.mounted) return;

  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (_) => false,
  );
}
