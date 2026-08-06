import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/constants/app_config.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_text_styles.dart';
import 'firebase_options.dart';
import 'web/admin_web_login.dart';
import 'web/admin_web_shell.dart';

/// Entry point for the admin web console.
///
///     flutter run    -d chrome --web-renderer canvaskit -t lib/main_web.dart
///     flutter build  web --release -t lib/main_web.dart
///
/// Separate from `main.dart` on purpose. The mobile app's root pulls in
/// TFLite, ML Kit, the camera and `dart:io` for face enrollment — none
/// of which compile for the web. Rather than stubbing all of that out,
/// the web build starts from a root that only ever reaches the admin
/// screens, which are plain Firestore + Flutter and build for both
/// targets unchanged.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const AdminWebApp());
}

class AdminWebApp extends StatelessWidget {
  const AdminWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AttendX Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const _AuthGate(),
    );
  }
}

/// Shows the console or the login screen depending on the Firebase
/// session, and refuses anyone who isn't the admin account.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        if (user == null) {
          // The gate is driven by authStateChanges, so signing in is
          // enough to swap the screen — the callback is only here so the
          // login screen doesn't have to know that.
          return AdminWebLogin(onSignedIn: () {});
        }

        // A student who somehow reaches this URL and signs in with their
        // own credentials must not land in the console. The Firestore
        // rules would block every write regardless, but failing at the
        // door is clearer than a screen full of permission errors.
        if (user.email?.toLowerCase() != AppConfig.adminEmail.toLowerCase()) {
          return const _NotAnAdmin();
        }

        return AdminWebShell(onSignedOut: () {});
      },
    );
  }
}

class _NotAnAdmin extends StatelessWidget {
  const _NotAnAdmin();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: .1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.no_accounts_rounded,
                      color: AppColors.danger, size: 36),
                ),
                const SizedBox(height: 20),
                Text("This console is admin-only",
                    style: AppTextStyles.title, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  "Students and CRs should use the AttendX mobile app — "
                  "face check-in and CR tools aren't available in a browser.",
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text("Sign out"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
