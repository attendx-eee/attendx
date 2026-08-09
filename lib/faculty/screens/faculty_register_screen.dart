import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_config.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';
import '../../admin/models/faculty_model.dart';
import '../../admin/services/master_data_service.dart';
import '../../screens/face_enrollment_screen.dart';
import '../../screens/role_router.dart';
import '../../services/enrollment/scan_harvester.dart';
import '../models/faculty_account.dart';

/// Faculty sign-up.
///
/// Shorter than the student flow and quite different in shape: no roll
/// number, no year or semester, and no face enrollment — a faculty
/// member signs in with a password to mark other people's attendance,
/// they don't check in through the gate themselves.
///
/// Anyone can sign up; the account is created pending. An admin then
/// checks the details, corrects anything wrong, and links it to a
/// timetable record — that link is what decides whose classes this
/// person can mark.
class FacultyRegisterScreen extends StatefulWidget {
  const FacultyRegisterScreen({super.key});

  @override
  State<FacultyRegisterScreen> createState() =>
      _FacultyRegisterScreenState();
}

class _FacultyRegisterScreenState extends State<FacultyRegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _shortName = TextEditingController();
  final _email = TextEditingController();
  final _mobile = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _experience = TextEditingController(text: '0');

  /// The Master Data faculty record the applicant picked, if any. Only a
  /// convenience for filling the form — the admin still chooses the real
  /// link when approving.
  String? _pickedFacultyId;

  /// Created once, not per build.
  ///
  /// Calling getFaculty() inside build() makes a fresh Firestore
  /// subscription on every setState — every dropdown change, every
  /// keystroke that triggers a rebuild — and each one restarts the
  /// StreamBuilder in its waiting state, so the list flickers empty.
  late final Stream<List<FacultyModel>> _facultyStream =
      MasterDataService.instance.getFaculty();

  String _designation = FacultyAccount.designations[2];
  String _qualification = FacultyAccount.qualifications.first;

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _name,
      _shortName,
      _email,
      _mobile,
      _password,
      _confirm,
      _experience,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final email = _email.text.trim().toLowerCase();
    final name = _name.text.trim();

    UserCredential? credential;

    try {
      credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: email,
        password: _password.text,
      );

      final uid = credential.user!.uid;

      // Created pending, with no facultyId. The admin supplies that when
      // they approve, by picking which timetable record this person is —
      // which is also what decides whose classes they can mark.
      final account = FacultyAccount(
        uid: uid,
        name: name,
        shortName: _shortName.text.trim(),
        designation: _designation,
        department: AppConfig.department,
        qualification: _qualification,
        experienceYears: int.tryParse(_experience.text.trim()) ?? 0,
        email: email,
        mobile: _mobile.text.trim(),
      );

      await FirebaseFirestore.instance
          .collection('students')
          .doc(uid)
          .set(account.toMap());

      if (!mounted) return;

      // Straight into face enrollment, same as a student registering.
      //
      // Creating the account already signed them in, so there's no
      // reason to bounce them out to the login screen and back. Doing it
      // now also means the duplicate-face check runs while the account
      // is still pending — catching someone enrolling a face already on
      // file *before* an admin approves them, rather than after.
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const FaceEnrollmentScreen(
            mandatory: false,
            scanProfile: ScanProfile.frontalOnly,
          ),
        ),
      );

      if (!mounted) return;

      // Then the dashboard, which shows the waiting-for-approval state
      // until an admin links them to a timetable record.
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const RoleRouter()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _busy = false;
        _error = switch (e.code) {
          'email-already-in-use' =>
            'That email already has an account. Sign in instead.',
          'weak-password' => 'Choose a longer password.',
          'invalid-email' => "That email address doesn't look right.",
          'network-request-failed' =>
            "Can't reach the server. Check your connection.",
          _ => 'Could not create the account: ${e.message}',
        };
      });
    } catch (e) {
      // The auth account may exist while the profile write failed —
      // roll it back so the email isn't left permanently taken by an
      // account that can never sign in to anything.
      try {
        await credential?.user?.delete();
      } catch (_) {
        // Nothing more to do; the office can clear it manually.
      }

      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not finish sign-up: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Faculty Registration'),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: MaxWidthBody(
        maxWidth: 560,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: Responsive.all(20),
            children: [
              Text(
                'Create a staff account',
                style: AppTextStyles.headline,
              ),
              SizedBox(height: Responsive.h(6)),
              Text(
                'Pick your name if it is already on the department list, '
                'or just fill this in. An admin checks the details before '
                'your classes appear.',
                style: AppTextStyles.caption,
              ),
              SizedBox(height: Responsive.h(22)),

              // Optional shortcut: picking a name off the department
              // list pre-fills the fields below. Skipping it is fine —
              // the admin sets the real link at approval either way.
              StreamBuilder<List<FacultyModel>>(
                stream: _facultyStream,
                builder: (context, snapshot) {
                  final faculty = snapshot.data ?? const <FacultyModel>[];
                  final loading =
                      snapshot.connectionState == ConnectionState.waiting;

                  // An empty list and a refused read look identical once
                  // `?? const []` has done its work, and they need
                  // different fixes — so say which it is.
                  final helper = snapshot.hasError
                      ? "Couldn't load the staff list: ${snapshot.error}"
                      : loading
                          ? 'Loading the staff list…'
                          : faculty.isEmpty
                              ? 'No staff on file yet — fill the fields in '
                                  'by hand'
                              : 'Fills your ID and initials automatically';

                  return Padding(
                    padding: EdgeInsets.only(bottom: Responsive.h(14)),
                    child: DropdownButtonFormField<String>(
                      initialValue: _pickedFacultyId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Find your name on the staff list',
                        helperText: helper,
                        helperStyle: snapshot.hasError
                            ? const TextStyle(color: AppColors.danger)
                            : null,
                        helperMaxLines: 3,
                        prefixIcon: const Icon(Icons.person_search_outlined,
                            size: 20),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      items: faculty
                          .map((f) => DropdownMenuItem(
                                value: f.id,
                                child: Text(
                                  f.shortName.isEmpty
                                      ? f.name
                                      : '${f.name} (${f.shortName})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (id) {
                        if (id == null) return;
                        final picked =
                            faculty.firstWhere((f) => f.id == id);
                        setState(() {
                          _pickedFacultyId = id;
                          _name.text = picked.name;
                          _shortName.text = picked.shortName;
                          if (picked.designation.isNotEmpty &&
                              FacultyAccount.designations
                                  .contains(picked.designation)) {
                            _designation = picked.designation;
                          }
                        });
                      },
                    ),
                  );
                },
              ),

              _field(
                controller: _name,
                label: 'Full name *',
                icon: Icons.person_outline,
                validator: (v) => (v == null || v.trim().length < 3)
                    ? 'Enter your full name'
                    : null,
              ),
              _field(
                controller: _shortName,
                label: 'Initials on the timetable (e.g. TRJ)',
                icon: Icons.short_text_rounded,
                textCapitalization: TextCapitalization.characters,
              ),

              _dropdown(
                label: 'Designation *',
                icon: Icons.school_outlined,
                value: _designation,
                items: FacultyAccount.designations,
                onChanged: (v) => setState(() => _designation = v!),
              ),
              _dropdown(
                label: 'Highest qualification *',
                icon: Icons.workspace_premium_outlined,
                value: _qualification,
                items: FacultyAccount.qualifications,
                onChanged: (v) => setState(() => _qualification = v!),
              ),
              _field(
                controller: _experience,
                label: 'Years of teaching experience',
                icon: Icons.timeline_rounded,
                keyboardType: TextInputType.number,
              ),

              _field(
                controller: _email,
                label: 'Official email *',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'Email is required';
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                      .hasMatch(value)) {
                    return "That doesn't look like an email address";
                  }
                  return null;
                },
              ),
              _field(
                controller: _mobile,
                label: 'Mobile number *',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                validator: (v) => (v == null || v.trim().length < 10)
                    ? 'Enter a valid mobile number'
                    : null,
              ),

              _field(
                controller: _password,
                label: 'Password *',
                icon: Icons.lock_outline_rounded,
                obscure: _obscure,
                suffix: IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                validator: (v) => (v == null || v.length < 8)
                    ? 'Use at least 8 characters'
                    : null,
              ),
              _field(
                controller: _confirm,
                label: 'Confirm password *',
                icon: Icons.lock_reset_rounded,
                obscure: _obscure,
                validator: (v) =>
                    v != _password.text ? "Passwords don't match" : null,
              ),

              if (_error != null) ...[
                SizedBox(height: Responsive.h(4)),
                Container(
                  padding: Responsive.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                        color: AppColors.danger.withValues(alpha: .3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.danger, size: 18),
                      SizedBox(width: Responsive.w(8)),
                      Expanded(
                        child: Text(_error!,
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.danger)),
                      ),
                    ],
                  ),
                ),
              ],

              SizedBox(height: Responsive.h(22)),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Create account',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
              SizedBox(height: Responsive.h(24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffix,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: Responsive.h(14)),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        obscureText: obscure,
        textCapitalization: textCapitalization,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          suffixIcon: suffix,
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required IconData icon,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: Responsive.h(14)),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
        items: items
            .map((i) => DropdownMenuItem(value: i, child: Text(i)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}
