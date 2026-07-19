import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../services/attendance_service.dart';
import '../core/responsive/responsive.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radius.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/primary_card.dart';
import '../core/widgets/section_header.dart';
import '../core/widgets/status_chip.dart';

class ProfileScreen extends StatefulWidget {
  final Map<String, dynamic> studentRawData;
  const ProfileScreen({super.key, required this.studentRawData});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();

  File? _profileImage;
  bool _isUploading = false;
  late Map<String, dynamic> data;

  /// Real attendance from Raspberry Pi events, loaded in [_loadAttendance].
  Map<String, Map<String, int>> attendanceStats = {
    for (final m in [
      "July", "August", "September", "October", "November", "December"
    ])
      m: {"present": 0, "absent": 0, "total": 0, "late": 0},
  };

  @override
  void initState() {
    super.initState();
    data = widget.studentRawData;
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final stats = await AttendanceService.instance.semesterStats(
      uid: uid,
      studentData: data,
      months: attendanceStats.keys.toList(),
    );

    if (mounted) setState(() => attendanceStats = stats);
  }

  Future<void> loadStudent() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final snapshot = await FirebaseFirestore.instance
        .collection('students')
        .doc(uid)
        .get();

    if (!snapshot.exists) return;

    setState(() {
      data = snapshot.data()!;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 400,
      );
      if (pickedFile == null) return;

      setState(() {
        _profileImage = File(pickedFile.path);
        _isUploading = true;
      });

      String uid = FirebaseAuth.instance.currentUser!.uid;

      await FirebaseFirestore.instance.collection('students').doc(uid).update({
        'profileImageUrl': pickedFile.path,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Profile display picture updated successfully."),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint("Media capture selection error: $e");
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showImageSourceOptions() {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Profile photo updates are available on the mobile app."),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: Responsive.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.only(bottom: Responsive.h(16)),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              Text("Update Profile Photo", style: AppTextStyles.title),
              SizedBox(height: Responsive.h(12)),
              _sheetOption(
                icon: Icons.photo_camera_rounded,
                label: "Capture from Camera",
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              _sheetOption(
                icon: Icons.photo_library_rounded,
                label: "Choose from Gallery",
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      leading: Container(
        padding: Responsive.all(10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(label, style: AppTextStyles.body.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      )),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: AppColors.textSecondary),
      onTap: onTap,
    );
  }

  Map<String, dynamic> _calculateAttendanceProjections() {
    int totalPresent = 0;
    int totalClasses = 0;

    attendanceStats.forEach((_, value) {
      totalPresent += value["present"]!;
      totalClasses += value["total"]!;
    });

    double currentPercentage =
        totalClasses > 0 ? (totalPresent / totalClasses) * 100 : 0.0;
    int targetDeltaClasses = 0;
    bool isAboveThreshold = currentPercentage >= 75.0;

    if (!isAboveThreshold) {
      targetDeltaClasses =
          ((0.75 * totalClasses - totalPresent) / 0.25).ceil().clamp(0, 100);
    } else {
      targetDeltaClasses =
          ((totalPresent - 0.75 * totalClasses) / 0.75).floor().clamp(0, 100);
    }

    return {
      "percentage": currentPercentage,
      "isAboveThreshold": isAboveThreshold,
      "classCount": targetDeltaClasses,
      "present": totalPresent,
      "total": totalClasses
    };
  }

  @override
  Widget build(BuildContext context) {
    final projection = _calculateAttendanceProjections();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: Responsive.h(280),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            title: const Text("My Profile",
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
            flexibleSpace: FlexibleSpaceBar(background: _buildHeader()),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: Responsive.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAttendanceCard(projection),
                  SizedBox(height: Responsive.h(24)),
                  const SectionHeader(
                    title: "Student Information",
                    subtitle: "Your registered academic identity",
                  ),
                  SizedBox(height: Responsive.h(18)),
                  PrimaryCard(
                    padding: Responsive.symmetric(horizontal: 8, vertical: 6),
                    child: Column(
                      children: [
                        _buildDetailRow(Icons.badge_outlined,
                            "Registration No", data['regNo'] ?? 'N/A'),
                        const Divider(
                            height: 1,
                            indent: 60,
                            color: AppColors.divider),
                        _buildDetailRow(Icons.mail_outline_rounded,
                            "Email Account", data['email'] ?? 'N/A'),
                      ],
                    ),
                  ),
                  SizedBox(height: Responsive.h(24)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        // Logo-matching blue -> teal sweep.
        gradient: AppColors.brandGradient,
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Stack(
              children: [
                Container(
                  width: Responsive.w(108),
                  height: Responsive.w(108),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: _isUploading
                        ? Container(
                            color: Colors.white,
                            child: const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.primary, strokeWidth: 2.5),
                            ),
                          )
                        // Local file images are device-only; web shows
                        // the placeholder avatar.
                        : (!kIsWeb && _profileImage != null
                            ? Image.file(_profileImage!, fit: BoxFit.cover)
                            : (!kIsWeb && data['profileImageUrl'] != null
                                ? Image.file(File(data['profileImageUrl']),
                                    fit: BoxFit.cover)
                                : Container(
                                    color: Colors.white,
                                    child: Icon(Icons.person_rounded,
                                        size: 56,
                                        color: AppColors.secondary),
                                  ))),
                  ),
                ),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: _showImageSourceOptions,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(color: Color(0x22000000), blurRadius: 6),
                        ],
                      ),
                      child: const Icon(Icons.camera_alt_rounded,
                          size: 16, color: AppColors.primary),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: Responsive.h(14)),
            Text(
              data['name'] ?? 'Student Name',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: Responsive.sp(20),
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            SizedBox(height: Responsive.h(8)),
            Container(
              padding: Responsive.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                "Electrical Eng.  •  Semester ${data['semester']}",
                style: TextStyle(
                  fontSize: Responsive.sp(12),
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(height: Responsive.h(24)),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceCard(Map<String, dynamic> projection) {
    final double percentage = projection["percentage"];
    final bool isSafe = projection["isAboveThreshold"];
    final int dynamicCount = projection["classCount"];
    final Color accent = isSafe ? AppColors.success : AppColors.danger;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: "Attendance Overview",
          subtitle: "Tracked against the 75% threshold",
          trailing: StatusChip(
            text: isSafe ? "ON TRACK" : "AT RISK",
            state: isSafe ? ChipState.success : ChipState.danger,
          ),
        ),
        SizedBox(height: Responsive.h(18)),
        PrimaryCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    percentage.toStringAsFixed(1),
                    style: AppTextStyles.display.copyWith(
                      fontSize: Responsive.sp(40),
                      color: accent,
                    ),
                  ),
                  Text("%",
                      style: AppTextStyles.title.copyWith(color: accent)),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      "${projection['present']}/${projection['total']} sessions",
                      style: AppTextStyles.caption,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              SizedBox(height: Responsive.h(14)),
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: LinearProgressIndicator(
                  value: (percentage / 100).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: AppColors.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
              SizedBox(height: Responsive.h(6)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("0%", style: AppTextStyles.caption),
                  Text("Target 75%",
                      style: AppTextStyles.caption
                          .copyWith(fontWeight: FontWeight.w700)),
                  Text("100%", style: AppTextStyles.caption),
                ],
              ),
              SizedBox(height: Responsive.h(18)),
              Container(
                padding: Responsive.all(14),
                decoration: BoxDecoration(
                  color: (isSafe ? AppColors.success : AppColors.warning)
                      .withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isSafe
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      color: isSafe ? AppColors.success : AppColors.warning,
                      size: 20,
                    ),
                    SizedBox(width: Responsive.w(10)),
                    Expanded(
                      child: Text(
                        isSafe
                            ? "You are safe! You can skip up to $dynamicCount classes this month without falling below 75%."
                            : "Critical level: attend the next $dynamicCount consecutive classes to bring your attendance up to 75%.",
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String description) {
    return Padding(
      padding: Responsive.symmetric(horizontal: 8, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: Responsive.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          SizedBox(width: Responsive.w(14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.caption),
                SizedBox(height: Responsive.h(2)),
                Text(
                  description,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
