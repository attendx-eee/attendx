import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_config.dart';
import '../core/responsive/responsive.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radius.dart';
import '../core/theme/app_text_styles.dart';

/// Sign-in for the web admin console.
///
/// A deliberately separate, cut-down screen rather than a reuse of the
/// mobile login. That one offers student registration and face sign-in,
/// which drag in the camera, ML Kit and `dart:io` — none of which build
/// for web — and none of which an admin at a desktop would use anyway.
/// The admin account is a fixed address whose password is the secret
/// key, so there is only one field to fill in.
class AdminWebLogin extends StatefulWidget {
  final VoidCallback onSignedIn;

  const AdminWebLogin({super.key, required this.onSignedIn});

  @override
  State<AdminWebLogin> createState() => _AdminWebLoginState();
}

class _AdminWebLoginState extends State<AdminWebLogin> {
  final TextEditingController _keyController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = "Enter the admin secret key.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: AppConfig.adminEmail,
        password: key,
      );
      if (mounted) widget.onSignedIn();
    } on FirebaseAuthException catch (e) {
      // Firebase distinguishes "no such user" from "wrong password", but
      // surfacing that on a public console just tells an attacker which
      // half they got right.
      setState(() {
        _error = switch (e.code) {
          'network-request-failed' =>
            "Can't reach the server. Check your connection.",
          'too-many-requests' =>
            "Too many attempts. Wait a moment and try again.",
          _ => "That secret key wasn't accepted.",
        };
      });
    } catch (e) {
      setState(() => _error = "Sign-in failed: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.xxl),
                boxShadow: const [
                  BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 32,
                      offset: Offset(0, 12)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: const BoxDecoration(
                        gradient: AppColors.brandGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.admin_panel_settings_rounded,
                          color: Colors.white, size: 34),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Center(
                    child: Text("AttendX Admin",
                        style: AppTextStyles.headline),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      "${AppConfig.department} • ${AppConfig.academicYear}",
                      style: AppTextStyles.caption,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _keyController,
                    obscureText: _obscure,
                    autofocus: true,
                    onSubmitted: (_) => _loading ? null : _signIn(),
                    decoration: InputDecoration(
                      labelText: "Admin secret key",
                      prefixIcon: const Icon(Icons.key_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: AppColors.danger, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: AppTextStyles.caption
                                  .copyWith(color: AppColors.danger)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _signIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text("Sign in",
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    "Students and CRs use the mobile app. This console is "
                    "for department admins only.",
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
