import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/auth/account_lookup.dart';
import 'core/responsive/responsive.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_text_styles.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'web/student_web_login.dart';
import 'web/student_web_shell.dart';

/// Entry point for the student web app — the iPhone answer.
///
/// There is no iOS build. Publishing one needs a paid Apple developer
/// account, and the department hasn't funded that, so iPhone students
/// would otherwise have no way in at all.
///
/// This is deliberately **view-only**: attendance, timetable, subject
/// percentages, notifications. It cannot enroll a face and does not
/// pretend to. Face recognition needs the TFLite model, ML Kit and a
/// camera pipeline, none of which exist in a browser — so an account is
/// created and its face enrolled once, at the office, on a department
/// Android device. After that the student can follow everything from
/// their phone.
///
/// Kept as a third entry point rather than a flag on `main.dart`,
/// because the mobile root reaches the camera, TFLite and `dart:io`
/// through registration and account settings. None of that compiles for
/// the web, and a flag wouldn't stop the compiler from following the
/// import.
///
///     flutter build web --release -t lib/main_student_web.dart \
///       --base-href /attendx/app/
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ErrorWidget.builder = (details) => _StartupError(
        title: 'Something failed to load',
        detail: details.exceptionAsString(),
      );

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    runApp(const StudentWebApp());
  } catch (e, stack) {
    debugPrint('Student web app failed to start: $e\n$stack');

    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: _StartupError(
        title: "AttendX couldn't start",
        detail: '$e',
      ),
    ));
  }
}

class StudentWebApp extends StatelessWidget {
  const StudentWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AttendX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) {
        Responsive.init(context);
        return child ?? const SizedBox.shrink();
      },
      home: const _Gate(),
    );
  }
}

/// Login, or the app, or a polite refusal.
class _Gate extends StatelessWidget {
  const _Gate();

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
        if (user == null) return const StudentWebLogin();

        return _AccountGate(uid: user.uid);
      },
    );
  }
}

/// Resolves who signed in and routes accordingly.
///
/// Staff are turned away rather than shown a half-working student view:
/// the admin console is a separate site, and a faculty member's whole
/// job in this app — scanning a room — is the one thing a browser can't
/// do.
class _AccountGate extends StatelessWidget {
  final String uid;

  const _AccountGate({required this.uid});

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

        if (account.isAdmin) {
          return const _WrongApp(
            title: 'This is the student app',
            body: 'Admin accounts use the console, which runs on a '
                'computer rather than a phone.',
            link: 'https://ganga2006.github.io/attendx/admin/',
          );
        }

        if (account.isFaculty) {
          return const _WrongApp(
            title: 'Faculty need the Android app',
            body: 'Capturing attendance means scanning a room with the '
                'camera, which a browser cannot do. Install the Android '
                'app to mark classes.',
            link: 'https://ganga2006.github.io/attendx/',
          );
        }

        if (!account.exists) {
          return const _WrongApp(
            title: 'No student record for this account',
            body: 'Registration happens once at the department office, '
                'on an Android device — that visit is also when your '
                'face is enrolled. Once it is done you can sign in here '
                'from any phone.',
            link: null,
          );
        }

        return StudentWebShell(uid: uid, student: account.data);
      },
    );
  }
}

/// Signed in, wrong door.
class _WrongApp extends StatelessWidget {
  final String title;
  final String body;
  final String? link;

  const _WrongApp({
    required this.title,
    required this.body,
    required this.link,
  });

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 42, color: AppColors.primary),
                const SizedBox(height: 16),
                Text(title,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headline),
                const SizedBox(height: 10),
                Text(body,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption),
                if (link != null) ...[
                  const SizedBox(height: 14),
                  SelectableText(
                    link!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Last resort, same reasoning as the console's: a blank page tells
/// nobody anything.
class _StartupError extends StatelessWidget {
  final String title;
  final String detail;

  const _StartupError({required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppColors.danger, size: 38),
                const SizedBox(height: 14),
                Text(title, style: AppTextStyles.headline),
                const SizedBox(height: 8),
                Text(
                  'Pull down to refresh, or reload the page. If it keeps '
                  'happening, show this to the department office.',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: SelectableText(
                    detail,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12, height: 1.5),
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
