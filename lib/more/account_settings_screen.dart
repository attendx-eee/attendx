import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_radius.dart';
import '../services/auth_service.dart';
import '../services/biometric_auth_service.dart';

/// Account Settings: edit personal details and change the password.
/// Every save is protected by password re-authentication, so only the
/// account owner can make changes.
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
  late final TextEditingController _phoneController;
  late final TextEditingController _sectionController;
  late int _year;

  bool _saving = false;
  bool _bioSupported = false;
  bool _bioEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
    _nameController =
        TextEditingController(text: widget.student['name']?.toString() ?? '');
    _phoneController =
        TextEditingController(text: widget.student['phone']?.toString() ?? '');
    _sectionController = TextEditingController(
        text: widget.student['section']?.toString() ?? 'A');
    _year = int.tryParse(widget.student['year']?.toString() ?? '') ?? 1;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _sectionController.dispose();
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

  Future<void> _saveDetails() async {
    if (!_formKey.currentState!.validate()) return;

    final verified = await _confirmPassword(
        'Enter your password to save the changes to your details.');
    if (!verified) return;

    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final updated = {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'section': _sectionController.text.trim().toUpperCase(),
        'year': _year,
      };
      await FirebaseFirestore.instance
          .collection('students')
          .doc(uid)
          .set(updated, SetOptions(merge: true));

      // The dashboard/More screen hold this same map in memory — update it
      // in place so the new values show immediately (not after re-login).
      widget.student.addAll(updated);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Details updated successfully.'),
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
                      'Saving requires your password.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _nameController,
                      decoration:
                          _decoration('Full Name', Icons.person_outline),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter your name'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration:
                          _decoration('Phone', Icons.phone_outlined),
                      validator: (v) => (v == null ||
                              v.trim().length < 10)
                          ? 'Enter a valid phone number'
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
                            onChanged: (v) =>
                                setState(() => _year = v ?? _year),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _sectionController,
                            textCapitalization:
                                TextCapitalization.characters,
                            decoration: _decoration(
                                'Section', Icons.group_outlined),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Section'
                                    : null,
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
              const SizedBox(height: 10),
              const Text(
                'Registration number and email cannot be changed. Contact the administration office for those.',
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
}
