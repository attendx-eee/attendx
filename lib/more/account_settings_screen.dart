import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../admin/services/batch_service.dart';
import '../core/constants/app_config.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radius.dart';
import '../screens/face_enrollment_screen.dart';
import '../screens/face_verification_screen.dart';
import '../screens/login.dart';
import '../services/auth_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/firestore_service.dart';
import '../services/profile_photo_service.dart';

/// Account Settings: edit personal details and change the password.
/// Sensitive changes are gated by identity verification — face
/// verification against the account's own enrolled profile where
/// available, falling back to password confirmation only when there's
/// no face on file yet to match against.
class AccountSettingsScreen extends StatefulWidget {
  final Map<String, dynamic> student;

  const AccountSettingsScreen({super.key, required this.student});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  late final TextEditingController _nameController;
  late int _year;
  late int _currentYear;
  String? _batch;
  List<String> _batchOptions = ['A'];
  bool _loadingBatches = true;

  bool _saving = false;
  bool _bioSupported = false;
  bool _bioEnabled = false;
  bool _deletingAccount = false;

  /// True while a name/year change is awaiting an admin decision. While
  /// pending, those two fields are locked so a second request can't be
  /// stacked on top of the first.
  bool get _hasPendingProfileChange =>
      widget.student['profileChangeStatus'] == 'pending';

  Map<String, dynamic> get _pendingProfile =>
      (widget.student['pendingProfile'] as Map?)?.cast<String, dynamic>() ??
      const {};

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
    _nameController =
        TextEditingController(text: widget.student['name']?.toString() ?? '');
    // AppConfig.yearOf falls back to the `semester` field when there's no
    // explicit `year` yet — true for every normally-registered student,
    // since registration only ever saves `semester`. Reading `year`
    // directly (as this used to) meant everyone without a prior
    // year-change approval showed up as "Year 1" here regardless of their
    // real year, which also fed the wrong year into _loadBatchOptions.
    _currentYear = AppConfig.yearOf(widget.student);
    _year = _currentYear;
    _batch = widget.student['batch']?.toString();
    _loadBatchOptions();
  }

  /// Batch options come from what the admin has configured for this
  /// student's (current, approved) department + year — never the
  /// pending/requested year, since that hasn't taken effect yet.
  Future<void> _loadBatchOptions() async {
    try {
      final department = AppConfig.departmentOf(widget.student);
      final count = await BatchService.instance
          .batchCount(department: department, year: _currentYear);
      final labels = BatchService.labels(count);
      if (mounted) {
        setState(() {
          _batchOptions = labels;
          _batch = labels.contains(_batch) ? _batch : labels.first;
          _loadingBatches = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingBatches = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: AppColors.primary),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
      );

  Future<void> _loadBiometricState() async {
    if (kIsWeb) return;
    final supported = await BiometricAuthService.instance.isDeviceSupported();
    final enabled = await BiometricAuthService.instance.isEnabled();
    if (mounted) {
      setState(() {
        _bioSupported = supported;
        _bioEnabled = enabled;
      });
    }
  }

  Future<void> _toggleBiometric(bool turnOn) async {
    if (!turnOn) {
      await BiometricAuthService.instance.disable();
      if (mounted) {
        setState(() => _bioEnabled = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fingerprint login disabled.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final password = await _verifiedPassword(
        'Confirm your password to enable fingerprint login on this device.');
    if (password == null) return;

    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) return;

    await BiometricAuthService.instance
        .enable(email: email, password: password);
    if (mounted) {
      setState(() => _bioEnabled = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fingerprint login enabled for this device.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Asks for the password, verifies it with Firebase, and returns it
  /// (null if cancelled or wrong).
  Future<String?> _verifiedPassword(String reason) async {
    final passController = TextEditingController();
    bool obscure = true;

    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg)),
          icon: const Icon(Icons.lock_person_rounded,
              color: AppColors.primary, size: 40),
          title: const Text('Confirm It\'s You'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                reason,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passController,
                obscureText: obscure,
                autofocus: true,
                decoration: _decoration('Current Password',
                        Icons.lock_outline_rounded)
                    .copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () =>
                        setDialogState(() => obscure = !obscure),
                  ),
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
              onPressed: () => Navigator.pop(context, passController.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              child: const Text('Verify'),
            ),
          ],
        ),
      ),
    );

    if (password == null || password.isEmpty) return null;

    final error = await _authService.reauthenticate(password: password);
    if (error != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return null;
    }
    return password;
  }

  /// Asks the user to confirm their password. Returns true if verified.
  Future<bool> _confirmPassword(String reason) async =>
      (await _verifiedPassword(reason)) != null;

  /// Opens the camera-based face verification screen and matches against
  /// this account's own enrolled face (never other students). Returns
  /// true only on a genuine match.
  Future<bool> _verifyByFace() async {
    final result = await Navigator.push<bool?>(
      context,
      MaterialPageRoute(builder: (_) => const FaceVerificationScreen()),
    );
    return result == true;
  }

  /// Identity check used before sensitive changes. Face verification is
  /// the primary method now — it falls back to password only when there
  /// is no enrolled face to match against yet (new/legacy/web accounts),
  /// since there'd be nothing on file to verify.
  Future<bool> _verifyIdentity(String reason) async {
    final hasFace = widget.student['faceEnrolled'] == true;
    if (!hasFace || kIsWeb) {
      return _confirmPassword(reason);
    }
    return _verifyByFace();
  }

  /// Face-enrollment update flow: verify identity first, show a success
  /// confirmation, and only then let the user proceed into a fresh
  /// enrollment (which overwrites the embeddings used for attendance
  /// marking and Pi kiosk recognition).
  Future<void> _updateBiometrics() async {
    final hasFace = widget.student['faceEnrolled'] == true;

    // Already enrolled -> verify by face before allowing re-enrollment.
    // Nothing enrolled yet -> nothing to match against, so a password
    // confirmation stands in for the identity check.
    final verified = (hasFace && !kIsWeb)
        ? await _verifyByFace()
        : await _confirmPassword(
            'Confirm your password to enroll your face.');
    if (!verified) return;
    if (!mounted) return;

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        icon: const Icon(Icons.verified_rounded,
            color: AppColors.success, size: 44),
        title: const Text('Verification Successful',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: const Text(
          'Your identity is confirmed. You can now enroll a new face profile — this replaces your current one.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Proceed to Enrollment'),
          ),
        ],
      ),
    );

    if (proceed != true || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FaceEnrollmentScreen()),
    );
  }

  Future<void> _saveDetails() async {
    if (!_formKey.currentState!.validate()) return;

    final newName = _nameController.text.trim();
    final currentName = (widget.student['name'] ?? '').toString();
    final nameChanged = newName != currentName;
    final yearChanged = _year != _currentYear;
    final currentBatch = widget.student['batch']?.toString();
    final batchChanged = _batch != null && _batch != currentBatch;

    if (!nameChanged && !yearChanged && !batchChanged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No changes to save.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if ((nameChanged || yearChanged) && _hasPendingProfileChange) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'You already have a name/year change request awaiting admin approval.'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final verified = await _verifyIdentity(
        'Enter your password to save the changes to your details.');
    if (!verified) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification failed or cancelled — no changes were saved.'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final updates = <String, dynamic>{};

      // Batch never needs admin approval — it's just picked from the
      // list the admin already configured, so it writes immediately.
      if (batchChanged) {
        updates['batch'] = _batch;
      }

      // Name and year go through admin approval: stash the requested
      // values separately instead of touching the live fields, so the
      // change only takes effect once an admin approves it.
      if (nameChanged || yearChanged) {
        updates['pendingProfile'] = {
          if (nameChanged) 'name': newName,
          if (yearChanged) 'year': _year,
        };
        updates['profileChangeStatus'] = 'pending';
        updates['profileChangeRequestedAt'] = FieldValue.serverTimestamp();
      }

      await FirebaseFirestore.instance
          .collection('students')
          .doc(uid)
          .set(updates, SetOptions(merge: true));

      // The dashboard/More screen hold this same map in memory — update it
      // in place so the new values show immediately (not after re-login).
      widget.student.addAll(updates);

      if (!mounted) return;

      final parts = <String>[];
      if (batchChanged) parts.add('Batch updated.');
      if (nameChanged || yearChanged) {
        parts.add('Name/Year change submitted for admin approval.');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(parts.join(' ')),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true); // signal the caller to reload
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: const Text('Change Password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: currentController,
                obscureText: true,
                decoration: _decoration(
                    'Current Password', Icons.lock_outline_rounded),
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Enter current password'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: newController,
                obscureText: true,
                decoration:
                    _decoration('New Password', Icons.lock_reset_rounded),
                validator: (v) => (v == null || v.length < 6)
                    ? 'At least 6 characters'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirmController,
                obscureText: true,
                decoration: _decoration(
                    'Confirm New Password', Icons.lock_reset_rounded),
                validator: (v) => v != newController.text
                    ? 'Passwords do not match'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Change'),
          ),
        ],
      ),
    );

    if (submitted != true) return;

    final reauthError =
        await _authService.reauthenticate(password: currentController.text);
    if (reauthError != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(reauthError),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final changeError =
        await _authService.changePassword(newPassword: newController.text);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(changeError ?? 'Password changed successfully.'),
        backgroundColor:
            changeError == null ? AppColors.success : AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Permanently deletes this account and everything tied to it —
  /// profile, enrolled face data, attendance history, notifications,
  /// and the Cloudinary photo reference — then the Firebase Auth
  /// account itself. Identity-verified first (face or password, same
  /// pattern as the rest of this screen), then a clear confirmation
  /// card spells out exactly what's being removed before anything
  /// happens.
  Future<void> _deleteAccount() async {
    final verified = await _verifyIdentity(
        'Confirm your password to delete your account.');
    if (!verified) return;
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        icon: const Icon(Icons.warning_amber_rounded,
            color: AppColors.danger, size: 44),
        title: const Text('Delete Your Account?',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: const Text(
          'This permanently deletes your profile, enrolled face data, '
          'attendance history, and notifications, then signs you out for '
          'good. Your registration number will be free to register again '
          'from scratch, but nothing from this account can be recovered.\n\n'
          'This cannot be undone.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _deletingAccount = true);

    try {
      // Firestore first: these deletes need an authenticated
      // request.auth.uid == uid to pass security rules, so they must
      // happen before the Auth account itself is gone.
      await FirestoreService().deleteStudentAccount(uid);
      await ProfilePhotoService.instance.delete(uid);

      try {
        await FirebaseAuth.instance.currentUser?.delete();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          final password = await _verifiedPassword(
              'Re-enter your password to finish deleting your account.');
          if (password != null) {
            await FirebaseAuth.instance.currentUser?.delete();
          } else {
            // Firestore data is already gone at this point — sign out
            // rather than leave a half-deleted session. RoleRouter
            // auto-cleans an orphaned Auth account with no student doc
            // the next time it's encountered.
            await FirebaseAuth.instance.signOut();
          }
        } else {
          rethrow;
        }
      }

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _deletingAccount = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not fully delete your account: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('Account Settings',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Personal Details',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text(
                      'Name/Year changes need admin approval. Batch updates instantly. Saving requires face verification.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    if (_hasPendingProfileChange) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.hourglass_top_rounded,
                                size: 18, color: AppColors.warning),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Waiting for admin approval'
                                '${_pendingProfile['name'] != null ? '\nName → ${_pendingProfile['name']}' : ''}'
                                '${_pendingProfile['year'] != null ? '\nYear → Year ${_pendingProfile['year']}' : ''}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: AppColors.textPrimary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _nameController,
                      enabled: !_hasPendingProfileChange,
                      decoration:
                          _decoration('Full Name', Icons.person_outline),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter your name'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _year.clamp(1, 4),
                            decoration: _decoration(
                                'Year', Icons.school_outlined),
                            items: [1, 2, 3, 4]
                                .map((y) => DropdownMenuItem(
                                    value: y, child: Text('Year $y')))
                                .toList(),
                            onChanged: _hasPendingProfileChange
                                ? null
                                : (v) => setState(() => _year = v ?? _year),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          // Re-keyed once the batch list finishes loading:
                          // DropdownButtonFormField only reads initialValue
                          // on its first build, so without a fresh key it
                          // would get stuck showing the pre-load state.
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('batch_$_loadingBatches'),
                            initialValue: _batchOptions.contains(_batch)
                                ? _batch
                                : null,
                            decoration: _decoration(
                                'Batch',
                                Icons.groups_rounded),
                            items: _batchOptions
                                .map((b) => DropdownMenuItem(
                                    value: b, child: Text('Batch $b')))
                                .toList(),
                            onChanged: _loadingBatches
                                ? null
                                : (v) => setState(() => _batch = v),
                            validator: (v) =>
                                v == null ? 'Select a batch' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 50,
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _saveDetails,
                        icon: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5),
                              )
                            : const Icon(Icons.save_outlined),
                        label: const Text('Save Changes',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: ListTile(
                  leading: const Icon(Icons.lock_reset_rounded,
                      color: AppColors.primary),
                  title: const Text('Change Password',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Requires your current password',
                      style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textSecondary),
                  onTap: _changePassword,
                ),
              ),
              if (_bioSupported) ...[
                const SizedBox(height: 18),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: SwitchListTile(
                    secondary: const Icon(Icons.fingerprint_rounded,
                        color: AppColors.primary),
                    title: const Text('Fingerprint Login',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text(
                        'Login with your fingerprint on this device',
                        style: TextStyle(fontSize: 12)),
                    value: _bioEnabled,
                    onChanged: _toggleBiometric,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Biometric Enrollment',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text(
                      'Re-enroll your face for attendance marking and kiosk recognition. Requires face verification.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 50,
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _updateBiometrics,
                        icon: const Icon(Icons.face_retouching_natural),
                        label: const Text('Update Biometrics',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Registration number and email cannot be changed. Contact the administration office for those.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                      color: AppColors.danger.withValues(alpha: .25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Danger Zone',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.danger)),
                    const SizedBox(height: 4),
                    const Text(
                      'Permanently deletes your profile, face enrollment, attendance history and notifications. This cannot be undone.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 50,
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _deletingAccount ? null : _deleteAccount,
                        icon: _deletingAccount
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    color: AppColors.danger, strokeWidth: 2.5),
                              )
                            : const Icon(Icons.delete_forever_rounded),
                        label: Text(
                            _deletingAccount
                                ? 'Deleting Account...'
                                : 'Delete Account',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
