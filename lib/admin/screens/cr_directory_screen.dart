import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_config.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';

/// Admin-only: browse approved Class Representatives by year, with a
/// one-tap call button — the reason CRs are asked for a mobile number
/// (and a photo) at registration in the first place.
class CrDirectoryScreen extends StatefulWidget {
  const CrDirectoryScreen({super.key});

  @override
  State<CrDirectoryScreen> createState() => _CrDirectoryScreenState();
}

class _CrDirectoryScreenState extends State<CrDirectoryScreen> {
  int _selectedYear = 1;

  Stream<QuerySnapshot<Map<String, dynamic>>> get _crs =>
      FirebaseFirestore.instance
          .collection('students')
          .where('role', isEqualTo: 'cr')
          .snapshots();

  /// Opens the phone dialer pre-filled with [mobile] — placing the actual
  /// call still needs one tap on the phone's own Call button, which is
  /// the standard, permission-free way to do this on both platforms.
  Future<void> _call(BuildContext context, String mobile) async {
    final uri = Uri(scheme: 'tel', path: mobile);
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not start a call to $mobile")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("CR Directory"),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: Responsive.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: List.generate(4, (index) {
                final year = index + 1;
                final selected = _selectedYear == year;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                        right: index == 3 ? 0 : Responsive.w(8)),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedYear = year),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: Responsive.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: selected ? AppColors.brandGradient : null,
                          color: selected ? null : AppColors.surface,
                          borderRadius:
                              BorderRadius.circular(Responsive.radius(14)),
                          border: Border.all(
                            color: selected
                                ? Colors.transparent
                                : AppColors.divider,
                          ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color:
                                        AppColors.primary.withValues(alpha: .28),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          "Year $year",
                          style: TextStyle(
                            fontSize: Responsive.sp(13),
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _crs,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final allCrs = snapshot.data?.docs ?? [];
                final crs = allCrs
                    .where((doc) =>
                        AppConfig.yearOf(doc.data()) == _selectedYear)
                    .toList()
                  ..sort((a, b) => (a.data()['name'] ?? '')
                      .toString()
                      .compareTo((b.data()['name'] ?? '').toString()));

                if (crs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: Responsive.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: Responsive.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: .08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.contact_phone_outlined,
                                size: Responsive.sp(40),
                                color: AppColors.primary),
                          ),
                          SizedBox(height: Responsive.h(16)),
                          Text(
                            "No CRs for Year $_selectedYear yet",
                            style: AppTextStyles.title,
                          ),
                          SizedBox(height: Responsive.h(6)),
                          Text(
                            "Approved Class Representatives will show up here.",
                            textAlign: TextAlign.center,
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Exactly one CR this year: give them the whole screen —
                // a compact list row would look lost in all that empty
                // space, so this shows a single, spacious profile-style
                // card instead.
                if (crs.length == 1) {
                  final data = crs.first.data();
                  final name = (data['name'] ?? 'Unknown').toString();
                  final mobile = (data['mobile'] ?? '').toString();
                  final photoUrl = data['profileImageUrl'] as String?;
                  final regNo = (data['regNo'] ?? '--').toString();
                  final department = (data['department'] ?? '').toString();

                  return SingleChildScrollView(
                    padding: Responsive.all(24),
                    child: Center(
                      child: _CrContactCardLarge(
                        name: name,
                        mobile: mobile,
                        photoUrl: photoUrl,
                        regNo: regNo,
                        department: department,
                        year: _selectedYear,
                        onCall: mobile.isNotEmpty
                            ? () => _call(context, mobile)
                            : null,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    Responsive.w(18),
                    Responsive.h(4),
                    Responsive.w(18),
                    Responsive.h(24),
                  ),
                  itemCount: crs.length,
                  separatorBuilder: (_, _) => SizedBox(height: Responsive.h(12)),
                  itemBuilder: (context, index) {
                    final data = crs[index].data();
                    final name = (data['name'] ?? 'Unknown').toString();
                    final mobile = (data['mobile'] ?? '').toString();
                    final photoUrl = data['profileImageUrl'] as String?;
                    final regNo = (data['regNo'] ?? '--').toString();
                    final department = (data['department'] ?? '').toString();

                    return _CrContactCard(
                      name: name,
                      mobile: mobile,
                      photoUrl: photoUrl,
                      regNo: regNo,
                      department: department,
                      year: _selectedYear,
                      onCall: mobile.isNotEmpty
                          ? () => _call(context, mobile)
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Spacious profile-style card shown when a year has exactly one CR —
/// a full-width row would look stranded in an otherwise empty screen,
/// so this fills the space with a bigger photo, centered details, and a
/// full-width call button instead.
class _CrContactCardLarge extends StatelessWidget {
  final String name;
  final String mobile;
  final String? photoUrl;
  final String regNo;
  final String department;
  final int year;
  final VoidCallback? onCall;

  const _CrContactCardLarge({
    required this.name,
    required this.mobile,
    required this.photoUrl,
    required this.regNo,
    required this.department,
    required this.year,
    required this.onCall,
  });

  String get _initial => name.isNotEmpty ? name[0].toUpperCase() : '?';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: Responsive.w(420)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      padding: Responsive.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.brandGradient,
            ),
            child: CircleAvatar(
              radius: Responsive.w(56),
              backgroundColor: AppColors.surface,
              child: ClipOval(
                child: photoUrl != null && photoUrl!.isNotEmpty
                    ? Image.network(
                        photoUrl!,
                        width: Responsive.w(108),
                        height: Responsive.w(108),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _InitialAvatar(
                            initial: _initial, size: Responsive.w(108)),
                      )
                    : _InitialAvatar(
                        initial: _initial, size: Responsive.w(108)),
              ),
            ),
          ),
          SizedBox(height: Responsive.h(18)),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "YEAR $year CLASS REPRESENTATIVE",
              style: TextStyle(
                color: AppColors.tealDark,
                fontSize: Responsive.sp(10.5),
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
          SizedBox(height: Responsive.h(12)),
          Text(
            name,
            textAlign: TextAlign.center,
            style: AppTextStyles.headline,
          ),
          SizedBox(height: Responsive.h(12)),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: Responsive.w(8),
            runSpacing: Responsive.h(8),
            children: [
              _Tag(icon: Icons.badge_outlined, text: "Reg $regNo"),
              if (department.isNotEmpty)
                _Tag(icon: Icons.account_tree_outlined, text: department),
            ],
          ),
          SizedBox(height: Responsive.h(28)),
          if (onCall != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onCall,
                icon: const Icon(Icons.call_rounded),
                label: Text("Call $name",
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: Responsive.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Responsive.radius(14)),
                  ),
                ),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.phone_disabled_rounded,
                    size: Responsive.sp(15), color: AppColors.textSecondary),
                SizedBox(width: Responsive.w(6)),
                Text("No mobile number on file",
                    style: AppTextStyles.caption),
              ],
            ),
        ],
      ),
    );
  }
}

/// A CR's contact card — photo-forward since the profile picture is
/// mandatory for CRs, with a prominent one-tap call action.
class _CrContactCard extends StatelessWidget {
  final String name;
  final String mobile;
  final String? photoUrl;
  final String regNo;
  final String department;
  final int year;
  final VoidCallback? onCall;

  const _CrContactCard({
    required this.name,
    required this.mobile,
    required this.photoUrl,
    required this.regNo,
    required this.department,
    required this.year,
    required this.onCall,
  });

  String get _initial => name.isNotEmpty ? name[0].toUpperCase() : '?';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      padding: Responsive.all(16),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.brandGradient,
                ),
                child: CircleAvatar(
                  radius: Responsive.w(30),
                  backgroundColor: AppColors.surface,
                  child: ClipOval(
                    child: photoUrl != null && photoUrl!.isNotEmpty
                        ? Image.network(
                            photoUrl!,
                            width: Responsive.w(58),
                            height: Responsive.w(58),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _InitialAvatar(
                                initial: _initial, size: Responsive.w(58)),
                          )
                        : _InitialAvatar(
                            initial: _initial, size: Responsive.w(58)),
                  ),
                ),
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.teal,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.surface, width: 2),
                  ),
                  child: Text(
                    "Y$year",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(width: Responsive.w(16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title,
                ),
                SizedBox(height: Responsive.h(6)),
                Wrap(
                  spacing: Responsive.w(6),
                  runSpacing: Responsive.h(6),
                  children: [
                    _Tag(icon: Icons.badge_outlined, text: "Reg $regNo"),
                    if (department.isNotEmpty)
                      _Tag(
                          icon: Icons.account_tree_outlined,
                          text: department),
                  ],
                ),
                if (mobile.isEmpty) ...[
                  SizedBox(height: Responsive.h(6)),
                  Row(
                    children: [
                      Icon(Icons.phone_disabled_rounded,
                          size: Responsive.sp(13),
                          color: AppColors.textSecondary),
                      SizedBox(width: Responsive.w(4)),
                      Text("No mobile on file",
                          style: AppTextStyles.caption),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (onCall != null) ...[
            SizedBox(width: Responsive.w(10)),
            _CallButton(onTap: onCall!),
          ],
        ],
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  final String initial;
  final double size;

  const _InitialAvatar({required this.initial, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: .1),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: Responsive.sp(20),
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Tag({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: Responsive.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(Responsive.radius(10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: Responsive.sp(12), color: AppColors.textSecondary),
          SizedBox(width: Responsive.w(4)),
          Text(text, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

/// Circular gradient call button — the primary action on each card.
class _CallButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CallButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.success, Color(0xFF16A34A)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.success.withValues(alpha: .35),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: Responsive.all(12),
            child: Icon(Icons.call_rounded,
                color: Colors.white, size: Responsive.sp(20)),
          ),
        ),
      ),
    );
  }
}
