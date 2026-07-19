import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'role_router.dart';
import 'register_screen.dart';
import '../admin/master_data/master_home.dart';
import '../core/constants/app_config.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radius.dart';
import '../services/auth_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/update_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final secretKeyController = TextEditingController();
  final AuthService authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureSecretKey = true;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    // Prompt to update before anyone signs in, if a newer APK exists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.instance.checkForUpdate(context);
    });
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    if (kIsWeb) return;
    final enabled = await BiometricAuthService.instance.isEnabled();
    final supported =
        enabled && await BiometricAuthService.instance.isDeviceSupported();
    if (!mounted) return;
    setState(() => _biometricAvailable = enabled && supported);

    // PhonePe-style: fingerprint prompt appears by itself when enabled —
    // no tap needed. Cancelling falls back to the normal login form.
    if (_biometricAvailable && !_isLoading) {
      await Future.delayed(const Duration(milliseconds: 450));
      if (mounted && !_isLoading) _handleBiometricLogin();
    }
  }

  /// Fingerprint releases the securely-stored credentials, then a normal
  /// Firebase sign-in runs with them.
  Future<void> _handleBiometricLogin() async {
    final creds = await BiometricAuthService.instance.authenticate();
    if (creds == null) {
      final err = BiometricAuthService.instance.lastError;
      if (err != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fingerprint error: $err'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
      return; // cancelled (no error) or failed (shown above)
    }

    setState(() => _isLoading = true);
    try {
      final result = await authService.loginUser(
        email: creds.$1,
        password: creds.$2,
      );
      if (!mounted) return;

      if (result == null) {
        _goHome();
      } else {
        // Stored password no longer valid (changed elsewhere) — clean up.
        await BiometricAuthService.instance.disable();
        if (!mounted) return;
        setState(() => _biometricAvailable = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Fingerprint login expired (password changed). Login with your credentials and enable it again in Account Settings.'),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    secretKeyController.dispose();
    super.dispose();
  }

  void _goHome({String? overrideUid}) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => RoleRouter(overrideUid: overrideUid),
      ),
    );
  }

  /// Credentials alone are enough — no face verification afterwards.
  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = await authService.loginUser(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      if (!mounted) return;

      if (result == null) {
        // Tell Android the login succeeded so Google Password Manager
        // offers to save (and later autofill) these credentials.
        TextInput.finishAutofillContext();
        _goHome();
      } else {
        // Wrong credentials — offer the reset-link flow right away.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Forgot password?',
              textColor: Colors.white,
              onPressed: _forgotPassword,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("An error occurred: $e"),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Admin logs in with just the secret key — it is the password of the
  /// fixed admin account, so this is a real authenticated session.
  Future<void> _handleAdminLogin() async {
    final key = secretKeyController.text.trim();

    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Enter the admin secret key"),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await authService.loginUser(
        email: AppConfig.adminEmail,
        password: key,
      );

      if (!mounted) return;

      if (result == null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MasterHome()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Invalid admin secret key."),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Invalid admin secret key."),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Forgot password: sends Firebase's reset email. If the mail isn't
  /// registered (or never arrives) the user is told to contact the
  /// administration office.
  Future<void> _forgotPassword() async {
    final resetEmailController =
        TextEditingController(text: emailController.text.trim());

    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: const Text('Reset Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your registered email. We will send a secure link to set a new password.',
              style:
                  TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: resetEmailController,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: _inputDecoration(
                label: 'Email Address',
                icon: Icons.mail_outline_rounded,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(context, resetEmailController.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Send Reset Link'),
          ),
        ],
      ),
    );

    if (email == null || email.isEmpty || !email.contains('@')) return;

    final code = await authService.sendPasswordReset(email: email);
    if (!mounted) return;

    String title;
    String message;
    IconData icon;
    Color iconColor;

    if (code == null) {
      title = 'Reset Link Sent';
      message =
          'A password reset link was sent to\n$email\n\nCheck your inbox and spam folder, set a new password from the link, then log in.\n\nIf the email does not arrive within a few minutes, please contact the administration office.';
      icon = Icons.mark_email_read_rounded;
      iconColor = AppColors.success;
    } else if (code == 'user-not-found') {
      title = 'Email Not Registered';
      message =
          'This email is not registered with AttendX.\n\nPlease check the address, or contact the administration office to get your account created.';
      icon = Icons.error_outline_rounded;
      iconColor = AppColors.danger;
    } else if (code == 'invalid-email') {
      title = 'Invalid Email';
      message = 'That does not look like a valid email address.';
      icon = Icons.error_outline_rounded;
      iconColor = AppColors.warning;
    } else {
      title = 'Something Went Wrong';
      message =
          'The reset email could not be sent right now. Try again in a moment, or contact the administration office.';
      icon = Icons.error_outline_rounded;
      iconColor = AppColors.danger;
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        icon: Icon(icon, color: iconColor, size: 44),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 13.5, color: AppColors.textSecondary, height: 1.45),
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    );
  }

  /// Admin login now lives behind the small icon in the top-right corner.
  void _showAdminSheet() {
    secretKeyController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.admin_panel_settings_rounded,
                  size: 40, color: AppColors.primary),
              const SizedBox(height: 10),
              const Text(
                'Admin Access',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Enter the department secret key',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: secretKeyController,
                obscureText: _obscureSecretKey,
                autofocus: true,
                onSubmitted: (_) {
                  Navigator.pop(context);
                  _handleAdminLogin();
                },
                decoration: _inputDecoration(
                  label: 'Admin Secret Key',
                  icon: Icons.vpn_key_rounded,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureSecretKey
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    onPressed: () => setSheetState(
                        () => _obscureSecretKey = !_obscureSecretKey),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _handleAdminLogin();
                  },
                  icon: const Icon(Icons.admin_panel_settings_rounded),
                  label: const Text('Enter Master Data',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Only department admins hold this key. All access is logged.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 21, color: AppColors.primary),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.background,
      labelStyle:
          const TextStyle(color: AppColors.textSecondary, fontSize: 14),
      contentPadding:
          const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.divider, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.danger, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Stack(
            children: [
              // Small admin entry — tucked in the top-right corner.
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  tooltip: 'Admin login',
                  onPressed: _isLoading ? null : _showAdminSheet,
                  icon: const Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 22,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ---------------------------------------------- header
                    Center(
                      child: Container(
                        height: 132,
                        width: 132,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surface,
                          border:
                              Border.all(color: AppColors.divider, width: 1),
                          boxShadow: const [
                            BoxShadow(
                              color: AppColors.shadow,
                              blurRadius: 14,
                              offset: Offset(0, 6),
                            )
                          ],
                        ),
                        padding: const EdgeInsets.all(18),
                        // ClipOval keeps the square image edges from ever
                        // peeking out of the circle.
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/attendx_logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.school_rounded,
                                    size: 50, color: AppColors.primary),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Wordmark in the logo's blue -> teal gradient.
                    ShaderMask(
                      shaderCallback: (bounds) =>
                          AppColors.brandGradient.createShader(bounds),
                      child: const Text(
                        "AttendX",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Department of Electrical Engineering",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Sign in with your credentials to continue",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 24),

                    // ---------------------------------------- input card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          boxShadow: const [
                            BoxShadow(
                              color: AppColors.shadow,
                              blurRadius: 16,
                              offset: Offset(0, 6),
                            )
                          ],
                        ),
                        child: AutofillGroup(
                          child: Column(
                          children: [
                            TextFormField(
                              controller: emailController,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.username,
                                  AutofillHints.email],
                              decoration: _inputDecoration(
                                label: "Email Address",
                                icon: Icons.mail_outline_rounded,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return "Enter your email";
                                }
                                if (!value.contains('@')) {
                                  return "Enter a valid email address";
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: passwordController,
                              obscureText: _obscurePassword,
                              autofillHints: const [AutofillHints.password],
                              onEditingComplete: () =>
                                  TextInput.finishAutofillContext(),
                              decoration: _inputDecoration(
                                label: "Password",
                                icon: Icons.lock_outline_rounded,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: AppColors.textSecondary,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(() =>
                                      _obscurePassword = !_obscurePassword),
                                ),
                              ),
                              validator: (value) =>
                                  (value == null || value.isEmpty)
                                      ? "Enter your password"
                                      : null,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed:
                                    _isLoading ? null : _forgotPassword,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                ),
                                child: const Text(
                                  "Forgot password?",
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      AppColors.secondary,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.sm),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.5),
                                      )
                                    : const Text("Login",
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ],
                        ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Fingerprint login (only when enabled on a capable
                      // device) — hidden on the web app.
                      if (!kIsWeb) ...[
                        if (_biometricAvailable) ...[
                          // --------------------------------------- divider
                          const Row(
                            children: [
                              Expanded(
                                  child: Divider(color: AppColors.divider)),
                              Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: 12),
                                child: Text("OR",
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textSecondary)),
                              ),
                              Expanded(
                                  child: Divider(color: AppColors.divider)),
                            ],
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 52,
                            child: OutlinedButton.icon(
                              onPressed:
                                  _isLoading ? null : _handleBiometricLogin,
                              icon: const Icon(Icons.fingerprint_rounded),
                              label: const Text("Login with Fingerprint",
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                backgroundColor: AppColors.surface,
                                side: const BorderSide(
                                    color: AppColors.primary, width: 1.2),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.sm),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 28),

                      // -------------------------------------- register link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "Don't have an account? ",
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 14),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        const RegisterScreen()),
                              );
                            },
                            child: const Text(
                              "Register here",
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
            ],
          ),
        ),
      ),
    );
  }
}
