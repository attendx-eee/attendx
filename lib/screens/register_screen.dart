import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController regNoController = TextEditingController();
  final TextEditingController mobileController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  final AuthService authService = AuthService();
  final FirestoreService firestoreService = FirestoreService();

  String? selectedDepartment;
  String? selectedSemester;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  /// false = Student, true = Class Representative (needs admin approval).
  bool _requestCrRole = false;

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
  void dispose() {
    nameController.dispose();
    regNoController.dispose();
    mobileController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  /// Returns an error message if regNo, mobile or email already belong
  /// to an existing student — otherwise null.
  Future<String?> _findDuplicate({
    required String regNo,
    required String mobile,
    required String email,
  }) async {
    final students = FirebaseFirestore.instance.collection('students');

    final results = await Future.wait([
      students.where('regNo', isEqualTo: regNo).limit(1).get(),
      students.where('mobile', isEqualTo: mobile).limit(1).get(),
      students.where('email', isEqualTo: email).limit(1).get(),
    ]);

    if (results[0].docs.isNotEmpty) {
      return "This register number is already registered.";
    }
    if (results[1].docs.isNotEmpty) {
      return "This mobile number is already registered.";
    }
    if (results[2].docs.isNotEmpty) {
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

    setState(() => _isLoading = true);

    try {
      final regNo = regNoController.text.trim();
      final mobile = mobileController.text.trim();
      final email = emailController.text.trim().toLowerCase();

      // Block duplicate data BEFORE creating the auth account.
      final duplicate = await _findDuplicate(
        regNo: regNo,
        mobile: mobile,
        email: email,
      );

      if (duplicate != null) {
        if (mounted) _showError(duplicate);
        return;
      }

      String? result = await authService.registerUser(
        email: email,
        password: passwordController.text.trim(),
      );

      if (!mounted) return;

      if (result == null) {
        final uid = FirebaseAuth.instance.currentUser!.uid;

        await firestoreService.saveStudent({
          'uid': uid,
          'name': nameController.text.trim(),
          'regNo': regNo,
          // Stored as the short code ("EEE") so it always matches
          // timetable paths, whatever the dropdown displays.
          'department':
              AppConfig.normalizeDepartment(selectedDepartment ?? ''),
          'semester': selectedSemester,
          'mobile': mobile,
          'email': email,
          'faceEnrolled': false,
          // Everyone starts as a student. A CR request stays pending
          // until the admin approves it from Master Data.
          'role': 'student',
          'crStatus': _requestCrRole ? 'pending' : 'none',
          if (_requestCrRole) 'crRequestedAt': FieldValue.serverTimestamp(),
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Registration successful! Welcome to AttendX."),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // The new account is already signed in — go straight to the
        // dashboard. Face enrollment is prompted there.
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const RoleRouter()),
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
                  "Join AttendX with your official student details. Each register number, mobile and email can be used only once.",
                  style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                      height: 1.4),
                ),
                const SizedBox(height: 18),

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
                      textCapitalization: TextCapitalization.words,
                      decoration: _inputDecoration(
                          label: "Full Name", icon: Icons.person_outline),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                              ? "Enter your name"
                              : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: regNoController,
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
                        return null;
                      },
                    ),
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
                      keyboardType: TextInputType.emailAddress,
                      decoration: _inputDecoration(
                          label: "Email Address", icon: Icons.mail_outline),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Enter email";
                        }
                        if (!RegExp(r'^[\w\-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                            .hasMatch(value.trim())) {
                          return "Enter a valid email address";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: mobileController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      decoration: _inputDecoration(
                          label: "Mobile Number",
                          icon: Icons.phone_android_outlined),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Enter mobile number";
                        }
                        if (value.trim().length != 10) {
                          return "Must be exactly 10 digits";
                        }
                        return null;
                      },
                    ),
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
                        : const Text("Register Account",
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
