import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/auth/account_lookup.dart';
import '../../core/constants/app_config.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';
import '../../screens/face_enrollment_screen.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/enrollment/scan_harvester.dart';
import '../../services/update_service.dart';
import '../models/faculty_account.dart';

/// Settings for a staff account.
///
/// Separate from the student version because almost none of it applies:
/// staff have no attendance of their own to look at, no roll number, and
/// no CR requests. What they do share is the face template, the
/// fingerprint shortcut, and wanting to know whether the app is current.
class FacultySettingsScreen extends StatefulWidget {
  final FacultyAccount account;

  const FacultySettingsScreen({super.key, required this.account});

  @override
  State<FacultySettingsScreen> createState() =>
      _FacultySettingsScreenState();
}

class _FacultySettingsScreenState extends State<FacultySettingsScreen> {
  bool _faceEnrolled = false;
  bool _biometricSupported = false;
  bool _biometricEnabled = false;
  bool _loading = true;

  UpdateStatus? _update;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final supported = await BiometricAuthService.instance.isDeviceSupported();
    final enabled = await BiometricAuthService.instance.isEnabled();

    final me = await FirebaseFirestore.instance
        .collection(AccountLookup.facultyAccounts)
        .doc(widget.account.uid)
        .get();

    if (!mounted) return;
    setState(() {
      _biometricSupported = supported;
      _biometricEnabled = enabled;
      _faceEnrolled = me.data()?['faceEnrolled'] == true;
      _loading = false;
    });
  }

  Future<void> _openFaceEnrollment() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        // Frontal-only: staff are matched close up and on purpose, never
        // across a room, so the wide sweep buys nothing.
        builder: (_) => const FaceEnrollmentScreen(
          mandatory: false,
          scanProfile: ScanProfile.frontalOnly,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _toggleBiometric(bool on) async {
    if (!on) {
      await BiometricAuthService.instance.disable();
      if (mounted) setState(() => _biometricEnabled = false);
      return;
    }

    // Enabling stores the credentials behind the fingerprint, so it
    // needs the password once to have something to store.
    final passwordController = TextEditingController();

    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('Enable fingerprint sign-in', style: AppTextStyles.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Confirm your password once. After that your fingerprint '
              'signs you in on this device.',
              style: AppTextStyles.caption,
            ),
            SizedBox(height: Responsive.h(14)),
            TextField(
              controller: passwordController,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            onPressed: () =>
                Navigator.pop(dialogContext, passwordController.text),
            child: const Text('Enable'),
          ),
        ],
      ),
    );

    if (password == null || password.isEmpty) return;

    try {
      await BiometricAuthService.instance.enable(
        email: widget.account.email,
        password: password,
      );

      if (!mounted) return;
      setState(() => _biometricEnabled = true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fingerprint sign-in enabled on this device.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _biometricEnabled = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Couldn't enable fingerprint sign-in: $e"),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _checkUpdate() async {
    setState(() => _checkingUpdate = true);
    final status = await UpdateService.instance.checkStatus();
    if (mounted) {
      setState(() {
        _update = status;
        _checkingUpdate = false;
      });
    }
  }

  Future<void> _editDetails() async {
    final name = TextEditingController(text: widget.account.name);
    final shortName = TextEditingController(text: widget.account.shortName);
    final mobile = TextEditingController(text: widget.account.mobile);
    final experience =
        TextEditingController(text: '${widget.account.experienceYears}');

    var designation =
        FacultyAccount.designations.contains(widget.account.designation)
            ? widget.account.designation
            : FacultyAccount.designations[2];
    var qualification =
        FacultyAccount.qualifications.contains(widget.account.qualification)
            ? widget.account.qualification
            : FacultyAccount.qualifications.first;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg)),
          title: Text('My details', style: AppTextStyles.title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(name, 'Full name'),
                _field(shortName, 'Initials on the timetable'),
                _field(mobile, 'Mobile', keyboard: TextInputType.phone),
                _field(experience, 'Years of experience',
                    keyboard: TextInputType.number),
                _dropdown(
                  label: 'Designation',
                  value: designation,
                  items: FacultyAccount.designations,
                  onChanged: (v) => setDialogState(() => designation = v!),
                ),
                _dropdown(
                  label: 'Qualification',
                  value: qualification,
                  items: FacultyAccount.qualifications,
                  onChanged: (v) => setDialogState(() => qualification = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;

    try {
      // Deliberately not touching facultyId, facultyStatus or role —
      // those are the admin's to set, and the security rules refuse a
      // self-update that changes them anyway.
      await FirebaseFirestore.instance
          .collection(AccountLookup.facultyAccounts)
          .doc(widget.account.uid)
          .update({
        'name': name.text.trim(),
        'shortName': shortName.text.trim().toUpperCase(),
        'mobile': mobile.text.trim(),
        'experienceYears': int.tryParse(experience.text.trim()) ?? 0,
        'designation': designation,
        'qualification': qualification,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Details saved.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Couldn't save: $e"),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _field(TextEditingController c, String label,
          {TextInputType? keyboard}) =>
      Padding(
        padding: EdgeInsets.only(bottom: Responsive.h(12)),
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm)),
          ),
        ),
      );

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) =>
      Padding(
        padding: EdgeInsets.only(bottom: Responsive.h(12)),
        child: DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm)),
          ),
          items: items
              .map((i) => DropdownMenuItem(value: i, child: Text(i)))
              .toList(),
          onChanged: onChanged,
        ),
      );

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : MaxWidthBody(
              maxWidth: 640,
              child: ListView(
                padding: Responsive.all(18),
                children: [
                  _card(
                    title: 'My details',
                    subtitle:
                        '${widget.account.designation} • ${widget.account.qualification}',
                    icon: Icons.badge_outlined,
                    actionLabel: 'Edit',
                    onAction: _editDetails,
                  ),
                  SizedBox(height: Responsive.h(14)),
                  _card(
                    title: _faceEnrolled ? 'Update my face' : 'Enroll my face',
                    subtitle: _faceEnrolled
                        ? 'Re-scan if face sign-in has been failing'
                        : 'Not set up yet — confirm your identity without '
                            'a password',
                    icon: _faceEnrolled
                        ? Icons.face_retouching_natural_rounded
                        : Icons.face_rounded,
                    actionLabel: _faceEnrolled ? 'Re-scan' : 'Set up',
                    onAction: _openFaceEnrollment,
                  ),
                  SizedBox(height: Responsive.h(14)),
                  _biometricCard(),
                  SizedBox(height: Responsive.h(14)),
                  _updateCard(),
                ],
              ),
            ),
    );
  }

  Widget _card({
    required String title,
    required String subtitle,
    required IconData icon,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      padding: Responsive.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: Responsive.sp(22)),
          SizedBox(width: Responsive.w(14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTextStyles.title
                        .copyWith(fontSize: Responsive.sp(14))),
                SizedBox(height: Responsive.h(3)),
                Text(subtitle, style: AppTextStyles.caption),
              ],
            ),
          ),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }

  Widget _biometricCard() {
    return Container(
      padding: Responsive.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.fingerprint_rounded,
              color: AppColors.primary, size: Responsive.sp(22)),
          SizedBox(width: Responsive.w(14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fingerprint sign-in',
                    style: AppTextStyles.title
                        .copyWith(fontSize: Responsive.sp(14))),
                SizedBox(height: Responsive.h(3)),
                Text(
                  _biometricSupported
                      ? 'Sign in on this device without typing a password'
                      : 'This device has no fingerprint sensor set up',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          Switch(
            value: _biometricEnabled,
            onChanged: _biometricSupported ? _toggleBiometric : null,
          ),
        ],
      ),
    );
  }

  Widget _updateCard() {
    final status = _update;
    final available = status?.available ?? false;

    return Container(
      padding: Responsive.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: available
              ? AppColors.primary.withValues(alpha: .35)
              : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                available
                    ? Icons.system_update_rounded
                    : Icons.verified_rounded,
                color: available ? AppColors.primary : AppColors.success,
                size: Responsive.sp(22),
              ),
              SizedBox(width: Responsive.w(14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('App version',
                        style: AppTextStyles.title
                            .copyWith(fontSize: Responsive.sp(14))),
                    SizedBox(height: Responsive.h(3)),
                    Text('You have v${AppConfig.appVersion}',
                        style: AppTextStyles.caption),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: Responsive.h(12)),
          if (_checkingUpdate)
            Text('Checking…', style: AppTextStyles.caption)
          else if (status == null)
            Text('Check whether a newer version has been released.',
                style: AppTextStyles.caption)
          else if (status.error != null)
            Text(status.error!,
                style:
                    AppTextStyles.caption.copyWith(color: AppColors.danger))
          else if (available)
            Text('Version ${status.latest} is available.',
                style: AppTextStyles.caption.copyWith(
                    color: AppColors.primary, fontWeight: FontWeight.w700))
          else
            Text("You're up to date.",
                style: AppTextStyles.caption.copyWith(
                    color: AppColors.success, fontWeight: FontWeight.w600)),
          SizedBox(height: Responsive.h(12)),
          SizedBox(
            width: double.infinity,
            child: available
                ? ElevatedButton.icon(
                    onPressed: () =>
                        UpdateService.instance.downloadUpdate(status!.apkUrl),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text('Update to v${status!.latest}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: _checkingUpdate ? null : _checkUpdate,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Check for updates'),
                  ),
          ),
        ],
      ),
    );
  }
}
