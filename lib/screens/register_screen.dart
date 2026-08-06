import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'face_enrollment_screen.dart';
import 'role_router.dart';
import '../core/constants/app_config.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radius.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

/// Outcome of an inline field-availability check.
enum _CheckStatus { idle, checking, ok, warning, error }

class _CheckState {
  _CheckStatus status = _CheckStatus.idle;
  String message = '';
  String? lastChecked;
  int token = 0;
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const String _emailDomain = '@andhrauniversity.edu.in';

  final TextEditingController nameController = TextEditingController();
  final TextEditingController regNoController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController mobileController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  final AuthService authService = AuthService();
  final FirestoreService firestoreService = FirestoreService();
  final ImagePicker _picker = ImagePicker();

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _regNoFocus = FocusNode();
  final FocusNode _mobileFocus = FocusNode();

  final _CheckState _nameCheck = _CheckState();
  final _CheckState _regNoCheck = _CheckState();
  final _CheckState _mobileCheck = _CheckState();

  /// True once anonymous sign-in succeeds — Firestore rules require
  /// signedIn() for any read, and no real account exists yet while the
  /// form is still being filled out. If this stays false (Anonymous
  /// provider not enabled in Firebase Console, or offline), the inline
  /// checks quietly do nothing; registration itself still works exactly
  /// as before, with the duplicate check happening at submit time.
  bool _precheckReady = false;

  String? selectedDepartment;
  String? selectedSemester;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  /// false = Student, true = Class Representative (needs admin approval).
  bool _requestCrRole = false;

  /// Held in memory only — never uploaded until face enrollment succeeds,
  /// same reasoning as the rest of the profile (see _handleRegistration).
  /// Mandatory for CR requests, optional for regular students. Photo
  /// picking is mobile-only (dart:io File), matching profile.dart's
  /// existing convention, so CR registration isn't offered on web.
  File? _pickedPhoto;

  final List<String> departments = [
    "Electrical Engineering",
    "Mechanical Engineering",
    "Civil Engineering",
    "ECE",
    "CSE",
    "Chemical Engineering"
  ];

  final List<String> semesters = ["1", "2", "3", "4", "5", "6", "7", "8"];
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Email is fully derived from the register number — keep it in sync
    // as the user types instead of asking them to enter it separately.
    regNoController.addListener(_syncEmailFromRegNo);

    // Reset a field's stale "available"/"taken" status the moment its
    // text changes to something other than what was last verified —
    // otherwise an outdated verdict could linger after an edit. If they
    // edit back to the exact value already checked (e.g. typed extra
    // digits then backspaced), leave the cached verdict showing instead
    // of blanking it for no reason.
    nameController.addListener(() => _resetCheck(_nameCheck, nameController));
    regNoController
        .addListener(() => _resetCheck(_regNoCheck, regNoController));
    mobileController
        .addListener(() => _resetCheck(_mobileCheck, mobileController));

    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) _checkNameAvailability();
    });
    _regNoFocus.addListener(() {
      if (!_regNoFocus.hasFocus) _checkRegNoAvailability();
    });
    _mobileFocus.addListener(() {
      if (!_mobileFocus.hasFocus) _checkMobileAvailability();
    });

    _preparePrecheckSession();
  }

  Future<void> _preparePrecheckSession() async {
    final error = await authService.signInAnonymouslyForPreCheck();
    if (mounted) setState(() => _precheckReady = error == null);
  }

  void _syncEmailFromRegNo() {
    final regNo = regNoController.text.trim();
    final derived = regNo.isEmpty ? '' : '$regNo$_emailDomain';
    if (emailController.text != derived) {
      emailController.text = derived;
    }
  }

  void _resetCheck(_CheckState check, TextEditingController controller) {
    if (check.status == _CheckStatus.idle) return;
    if (controller.text.trim() == check.lastChecked) return;
    check.token++; // invalidate any in-flight check for the old value
    setState(() {
      check.status = _CheckStatus.idle;
      check.message = '';
    });
  }

  Future<void> _checkNameAvailability() async {
    final value = nameController.text.trim();
    if (!_precheckReady || value.isEmpty) return;
    if (value == _nameCheck.lastChecked) return;

    final token = ++_nameCheck.token;
    setState(() {
      _nameCheck.status = _CheckStatus.checking;
      _nameCheck.message = 'Checking...';
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('students')
          .where('name', isEqualTo: value)
          .limit(1)
          .get();

      if (!mounted || token != _nameCheck.token) return;
      _nameCheck.lastChecked = value;
      setState(() {
        if (snap.docs.isNotEmpty) {
          _nameCheck.status = _CheckStatus.warning;
          _nameCheck.message =
              'A student named "$value" is already registered — make sure this isn\'t a duplicate account.';
        } else {
          _nameCheck.status = _CheckStatus.idle;
          _nameCheck.message = '';
        }
      });
    } catch (_) {
      if (!mounted || token != _nameCheck.token) return;
      setState(() {
        _nameCheck.status = _CheckStatus.idle;
        _nameCheck.message = '';
      });
    }
  }

  Future<void> _checkRegNoAvailability() async {
    final value = regNoController.text.trim();
    if (!_precheckReady || value.isEmpty) return;
    // Only bother once it's a plausible register number — matches the
    // field's own validator, so we're not firing a query on every
    // half-typed digit as focus bounces around.
    if (!RegExp(r'^\d{6,15}$').hasMatch(value)) return;
    if (value == _regNoCheck.lastChecked) return;

    final token = ++_regNoCheck.token;
    setState(() {
      _regNoCheck.status = _CheckStatus.checking;
      _regNoCheck.message = 'Checking availability...';
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('students')
          .where('regNo', isEqualTo: value)
          .limit(1)
          .get();

      if (!mounted || token != _regNoCheck.token) return;
      _regNoCheck.lastChecked = value;
      setState(() {
        if (snap.docs.isNotEmpty) {
          _regNoCheck.status = _CheckStatus.error;
          _regNoCheck.message = 'This register number is already registered.';
        } else {
          _regNoCheck.status = _CheckStatus.ok;
          _regNoCheck.message = 'Available';
        }
      });
    } catch (_) {
      if (!mounted || token != _regNoCheck.token) return;
      setState(() {
        _regNoCheck.status = _CheckStatus.idle;
        _regNoCheck.message = '';
      });
    }
  }

  Future<void> _checkMobileAvailability() async {
    final value = mobileController.text.trim();
    if (!_precheckReady || value.length != 10) return;
    if (value == _mobileCheck.lastChecked) return;

    final token = ++_mobileCheck.token;
    setState(() {
      _mobileCheck.status = _CheckStatus.checking;
      _mobileCheck.message = 'Checking...';
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('students')
          .where('mobile', isEqualTo: value)
          .limit(1)
          .get();

      if (!mounted || token != _mobileCheck.token) return;
      _mobileCheck.lastChecked = value;
      setState(() {
        if (snap.docs.isNotEmpty) {
          _mobileCheck.status = _CheckStatus.warning;
          _mobileCheck.message =
              'This mobile number is already on file for another account.';
        } else {
          _mobileCheck.status = _CheckStatus.idle;
          _mobileCheck.message = '';
        }
      });
    } catch (_) {
      if (!mounted || token != _mobileCheck.token) return;
      setState(() {
        _mobileCheck.status = _CheckStatus.idle;
        _mobileCheck.message = '';
      });
    }
  }

  /// Small status line shown under a field: a spinner while checking, or
  /// a colored message once we know more. Empty/idle renders nothing.
  Widget _fieldStatus(_CheckState check) {
    if (check.status == _CheckStatus.idle) return const SizedBox.shrink();

    final Color color;
    final IconData? icon;
    switch (check.status) {
      case _CheckStatus.checking:
        color = AppColors.textSecondary;
        icon = null;
        break;
      case _CheckStatus.ok:
        color = AppColors.success;
        icon = Icons.check_circle_outline_rounded;
        break;
      case _CheckStatus.warning:
        color = AppColors.warning;
        icon = Icons.info_outline_rounded;
        break;
      case _CheckStatus.error:
        color = AppColors.danger;
        icon = Icons.error_outline_rounded;
        break;
      case _CheckStatus.idle:
        color = AppColors.textSecondary;
        icon = null;
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (check.status == _CheckStatus.checking)
            const SizedBox(
              height: 12,
              width: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.textSecondary),
            )
          else if (icon != null)
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              check.message,
              style: TextStyle(fontSize: 11.5, color: color, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    regNoController.removeListener(_syncEmailFromRegNo);
    // If registration was abandoned mid-form, the anonymous session was
    // never upgraded (registerUser links it into the real account on
    // success) — clean it up rather than leaving throwaway anonymous
    // Auth users behind. Fire-and-forget: dispose() can't be awaited.
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.isAnonymous) {
      user.delete().catchError((_) {});
    }
    _nameFocus.dispose();
    _regNoFocus.dispose();
    _mobileFocus.dispose();
    nameController.dispose();
    regNoController.dispose();
    emailController.dispose();
    mobileController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 600,
      );
      if (picked == null) return;
      setState(() => _pickedPhoto = File(picked.path));
    } catch (e) {
      if (mounted) _showError("Could not access $source: $e");
    }
  }

  void _showPhotoSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppColors.primary),
              title: const Text("Take a photo"),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.primary),
              title: const Text("Choose from gallery"),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            if (_pickedPhoto != null)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text("Remove photo",
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _pickedPhoto = null);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Returns an error message if regNo or email already belong
  /// to an existing student — otherwise null.
  Future<String?> _findDuplicate({
    required String regNo,
    required String email,
  }) async {
    final students = FirebaseFirestore.instance.collection('students');

    final results = await Future.wait([
      students.where('regNo', isEqualTo: regNo).limit(1).get(),
      students.where('email', isEqualTo: email).limit(1).get(),
    ]);

    if (results[0].docs.isNotEmpty) {
      return "This register number is already registered.";
    }
    if (results[1].docs.isNotEmpty) {
      return "This email address is already registered.";
    }

    return null;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    if (selectedDepartment == null || selectedSemester == null) {
      _showError("Please select your Department and Semester");
      return;
    }

    // CR requests need a way for the admin to reach this person and a
    // photo for the CR directory — both mandatory only for CR, and both
    // checked here (before creating anything) so a validation failure
    // never leaves a half-created account behind.
    if (_requestCrRole) {
      if (kIsWeb) {
        _showError(
            "CR registration needs a photo, which isn't available on web — please register as a CR from the mobile app.");
        return;
      }
      if (mobileController.text.trim().length < 10) {
        _showError("Enter a valid mobile number for CR registration");
        return;
      }
      if (_pickedPhoto == null) {
        _showError("A profile photo is required for CR registration");
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final regNo = regNoController.text.trim();
      final email = emailController.text.trim().toLowerCase();

      // The duplicate check reads the `students` collection, which
      // Firestore rules only allow for signed-in callers — so the auth
      // account must be created (and the user signed in) first. Email
      // uniqueness is already enforced by Firebase Auth itself; this
      // catches duplicate register numbers, and rolls the just-created
      // auth account back if one is found.
      String? result = await authService.registerUser(
        email: email,
        password: passwordController.text.trim(),
      );

      if (!mounted) return;

      if (result == null) {
        final uid = FirebaseAuth.instance.currentUser!.uid;

        final duplicate = await _findDuplicate(
          regNo: regNo,
          email: email,
        );

        if (duplicate != null) {
          try {
            await FirebaseAuth.instance.currentUser?.delete();
          } catch (_) {
            await FirebaseAuth.instance.signOut();
          }
          if (mounted) _showError(duplicate);
          return;
        }

        // The profile is deliberately NOT saved yet. Face enrollment is a
        // required step of registration, and until it succeeds there's no
        // point creating a student record — if enrollment is abandoned or
        // fails for good, the whole signup (including this Firebase Auth
        // account) gets rolled back instead of leaving an incomplete
        // profile behind. FaceEnrollmentScreen writes this map to
        // Firestore itself, atomically with the face data, only once
        // enrollment actually succeeds (see FirestoreService
        // .completeRegistrationWithFace).
        final pendingProfile = {
          'uid': uid,
          'name': nameController.text.trim(),
          'regNo': regNo,
          // Stored as the short code ("EEE") so it always matches
          // timetable paths, whatever the dropdown displays.
          'department':
              AppConfig.normalizeDepartment(selectedDepartment ?? ''),
          'semester': selectedSemester,
          'email': email,
          'mobile': mobileController.text.trim(),
          // Everyone starts as a student. A CR request stays pending
          // until the admin approves it from Master Data.
          'role': 'student',
          'crStatus': _requestCrRole ? 'pending' : 'none',
          if (_requestCrRole) 'crRequestedAt': FieldValue.serverTimestamp(),
        };

        if (!mounted) return;

        if (kIsWeb) {
          // Web has no camera-based enrollment screen at all, so there's
          // nothing to defer to — save immediately, same as before, and
          // let the student enroll their face later from a mobile device.
          await firestoreService.saveStudent({
            ...pendingProfile,
            'faceEnrolled': false,
          });

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Registration successful! Welcome to AttendX."),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const RoleRouter()),
            (_) => false,
          );
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Account created — enroll your face to finish registration."),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Face enrollment is required to complete registration — send
        // them straight into it with the profile data it needs to save
        // on success. Only on successful enrollment do they reach the
        // dashboard.
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => FaceEnrollmentScreen(
              mandatory: true,
              pendingProfile: pendingProfile,
              pendingPhoto: _pickedPhoto,
            ),
          ),
          (_) => false,
        );
      } else {
        _showError(result);
      }
    } catch (e) {
      if (mounted) _showError("An error occurred: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: AppColors.primary),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.background,
      labelStyle:
          const TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
      contentPadding:
          const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
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
      appBar: AppBar(
        title: const Text("Create Account",
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        elevation: 0,
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "Join AttendX with your official student details. Each register number can be used only once — your college email is generated from it automatically.",
                  style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                      height: 1.4),
                ),
                const SizedBox(height: 18),

                // ---------------------------------------- photo (top)
                if (!kIsWeb) _buildPhotoPicker(),
                if (!kIsWeb) const SizedBox(height: 16),

                // ------------------------------------ role selector (top)
                _buildSectionCard(
                  title: "Registering as",
                  icon: Icons.how_to_reg_rounded,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _roleOption(
                            label: "Student",
                            icon: Icons.person_rounded,
                            selected: !_requestCrRole,
                            onTap: () =>
                                setState(() => _requestCrRole = false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _roleOption(
                            label: "Class Rep (CR)",
                            icon: Icons.record_voice_over_rounded,
                            selected: _requestCrRole,
                            onTap: () =>
                                setState(() => _requestCrRole = true),
                          ),
                        ),
                      ],
                    ),
                    if (_requestCrRole) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: .08),
                          borderRadius:
                              BorderRadius.circular(AppRadius.xs),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 16, color: AppColors.warning),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "CR access needs admin approval. Until approved, you'll have a regular student dashboard.",
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textPrimary,
                                    height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                _buildSectionCard(
                  title: "Academic Info",
                  icon: Icons.school_rounded,
                  children: [
                    TextFormField(
                      controller: nameController,
                      focusNode: _nameFocus,
                      textCapitalization: TextCapitalization.words,
                      decoration: _inputDecoration(
                          label: "Full Name", icon: Icons.person_outline),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                              ? "Enter your name"
                              : null,
                    ),
                    _fieldStatus(_nameCheck),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: regNoController,
                      focusNode: _regNoFocus,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(15),
                      ],
                      decoration: _inputDecoration(
                          label: "Register Number (digits only)",
                          icon: Icons.badge_outlined),
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return "Enter register number";
                        if (!RegExp(r'^\d+$').hasMatch(v)) {
                          return "Register number must contain digits only";
                        }
                        if (v.length < 6) return "Register number is too short";
                        if (_regNoCheck.status == _CheckStatus.error &&
                            _regNoCheck.lastChecked == v) {
                          return "This register number is already registered";
                        }
                        return null;
                      },
                    ),
                    _fieldStatus(_regNoCheck),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: selectedDepartment,
                      decoration: _inputDecoration(
                          label: "Department",
                          icon: Icons.account_tree_outlined),
                      items: departments
                          .map((dept) => DropdownMenuItem(
                              value: dept,
                              child: Text(dept,
                                  style: const TextStyle(fontSize: 14))))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => selectedDepartment = value),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: selectedSemester,
                      decoration: _inputDecoration(
                          label: "Semester", icon: Icons.school_outlined),
                      items: semesters
                          .map((sem) => DropdownMenuItem(
                              value: sem,
                              child: Text("Semester $sem",
                                  style: const TextStyle(fontSize: 14))))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => selectedSemester = value),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                _buildSectionCard(
                  title: "Contact Info",
                  icon: Icons.contact_mail_rounded,
                  children: [
                    TextFormField(
                      controller: emailController,
                      readOnly: true,
                      style: const TextStyle(color: AppColors.textSecondary),
                      decoration: _inputDecoration(
                        label: "Email Address (auto-generated)",
                        icon: Icons.mail_outline,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Enter your register number above to generate your email";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Generated from your register number as regno@andhrauniversity.edu.in",
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: mobileController,
                      focusNode: _mobileFocus,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      decoration: _inputDecoration(
                        label: _requestCrRole
                            ? "Mobile Number (required for CR)"
                            : "Mobile Number (optional)",
                        icon: Icons.phone_iphone_rounded,
                      ),
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (!_requestCrRole) return null;
                        if (v.length < 10) {
                          return "Enter a valid 10-digit mobile number";
                        }
                        return null;
                      },
                    ),
                    _fieldStatus(_mobileCheck),
                    if (_requestCrRole) ...[
                      const SizedBox(height: 6),
                      const Text(
                        "The admin uses this to reach CRs directly from the CR directory.",
                        style: TextStyle(
                            fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                _buildSectionCard(
                  title: "Security",
                  icon: Icons.shield_rounded,
                  children: [
                    TextFormField(
                      controller: passwordController,
                      obscureText: _obscurePassword,
                      decoration: _inputDecoration(
                        label: "Password",
                        icon: Icons.lock_open_outlined,
                        suffixIcon: IconButton(
                          icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: AppColors.textSecondary,
                              size: 20),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (value) =>
                          (value == null || value.length < 6)
                              ? "Must be at least 6 characters"
                              : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      decoration: _inputDecoration(
                        label: "Confirm Password",
                        icon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: AppColors.textSecondary,
                              size: 20),
                          onPressed: () => setState(() =>
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Confirm your password";
                        }
                        if (value != passwordController.text) {
                          return "Passwords do not match";
                        }
                        return null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleRegistration,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.secondary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.sm)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Text("Enroll Face",
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 10),

                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Already have an account? Login",
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoPicker() {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: _showPhotoSourceSheet,
            child: Stack(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.background,
                    border: Border.all(
                      color: _requestCrRole && _pickedPhoto == null
                          ? AppColors.warning
                          : AppColors.divider,
                      width: 1.4,
                    ),
                  ),
                  child: ClipOval(
                    child: _pickedPhoto != null
                        ? Image.file(_pickedPhoto!, fit: BoxFit.cover)
                        : Icon(Icons.person_rounded,
                            size: 44, color: AppColors.secondary),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt_rounded,
                        size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _requestCrRole ? "Profile photo (required for CR)" : "Profile photo (optional)",
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: _requestCrRole && _pickedPhoto == null
                  ? AppColors.warning
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleOption({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: .1)
              : AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 22,
                color: selected
                    ? AppColors.primary
                    : AppColors.textSecondary),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Icon(icon, size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
