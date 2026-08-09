import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/constants/app_config.dart';
import 'core/auth/account_lookup.dart';
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

  // Anything thrown while building a widget paints this instead of the
  // red-and-yellow default, which in a release web build is just a grey
  // rectangle with no text at all.
  ErrorWidget.builder = (details) => _BootError(
        title: 'Something failed to render',
        detail: details.exceptionAsString(),
      );

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    runApp(const AdminWebApp());
  } catch (e, stack) {
    // A throw here used to mean runApp never ran, and the page stayed
    // blank grey forever — no error, no spinner, nothing to search for.
    // Whatever went wrong, say so on screen: the console is opened on a
    // department PC by someone who won't be reading DevTools.
    debugPrint('Admin console failed to start: $e\n$stack');

    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: _BootError(
        title: "The console couldn't start",
        detail: '$e',
      ),
    ));
  }
}

/// Last-resort screen. Deliberately plain — it has to render even when
/// the thing that broke is the app itself.
class _BootError extends StatelessWidget {
  final String title;
  final String detail;

  const _BootError({required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppColors.danger, size: 40),
                const SizedBox(height: 16),
                Text(title, style: AppTextStyles.headline),
                const SizedBox(height: 10),
                Text(
                  'Try a hard reload first (Ctrl+Shift+R) — a half-updated '
                  'cache after a new deploy looks exactly like this.',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: SelectableText(
                    detail,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      height: 1.5,
                    ),
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

        return _RoleCheck(uid: user.uid);
      },
    );
  }
}

/// Confirms the signed-in admin actually has an admin *role document*.
///
/// Signing in is not the same as being an admin. The security rules
/// resolve a role by reading `students/{uid}`, falling back to
/// `users/{uid}`; if neither exists, or neither says `hod`/`office`,
/// every admin-only read and write is denied — while anything needing
/// only a signed-in user keeps working.
///
/// That combination is baffling from the outside: the student list
/// loads, the calendar renders, and then saving a mark fails with
/// "Missing or insufficient permissions", which reads like a rules bug
/// rather than a missing document. Checking here turns it into one
/// sentence saying exactly what to create.
class _RoleCheck extends StatelessWidget {
  final String uid;

  const _RoleCheck({required this.uid});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Account>(
      future: AccountLookup.find(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final account = snapshot.data ?? Account.none;

        if (!account.isAdmin) {
          return _MissingRole(
            uid: uid,
            foundRole: account.exists ? account.role : null,
          );
        }

        return AdminWebShell(onSignedOut: () {});
      },
    );
  }
}

/// Shown when the admin account has no usable role document.
class _MissingRole extends StatelessWidget {
  final String uid;
  final String? foundRole;

  const _MissingRole({required this.uid, required this.foundRole});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.rule_folder_outlined,
                    color: AppColors.warning, size: 40),
                const SizedBox(height: 16),
                Text('This account has no admin role',
                    style: AppTextStyles.headline),
                const SizedBox(height: 10),
                Text(
                  foundRole == null
                      ? 'Sign-in worked, but there is no profile document '
                          'for this account, so the security rules can\'t '
                          'tell it\'s an admin. Reads that any signed-in '
                          'user may do will appear to work; everything '
                          'admin-only fails with "insufficient '
                          'permissions".'
                      : 'This account\'s role is "$foundRole". The console '
                          'needs "hod" or "office".',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('To fix it', style: AppTextStyles.title),
                      const SizedBox(height: 10),
                      Text(
                        'In the Firebase console, create this document. '
                        'Admins live in their own collection so they '
                        'never show up in the student lists:',
                        style: AppTextStyles.caption,
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        '${AccountLookup.admins}/$uid\n'
                        '  role: "hod"\n'
                        '  name: "Administrator"',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Then reload this page.',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Sign out'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
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
