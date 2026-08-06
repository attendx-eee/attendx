import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_config.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';
import '../models/attendance_marker.dart';
import 'student_attendance_screen.dart';

/// Registered students, grouped by B.Tech year, with search.
///
/// The entry point for marking attendance by hand: pick a year, find the
/// student (list or search), tap through to their monthly calendar.
/// Admins get all four year tabs; a CR is pinned to their own year, so
/// the same screen serves both without a second copy of the list UI.
class StudentDirectoryScreen extends StatefulWidget {
  final AttendanceMarker marker;

  const StudentDirectoryScreen({super.key, required this.marker});

  @override
  State<StudentDirectoryScreen> createState() =>
      _StudentDirectoryScreenState();
}

class _StudentDirectoryScreenState extends State<StudentDirectoryScreen> {
  late int _selectedYear = widget.marker.visibleYears.first;

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// All students, filtered client-side.
  ///
  /// Year lives in the docs inconsistently (some have `year`, older ones
  /// only `semester`), so it can't be a Firestore `where` — AppConfig
  /// .yearOf resolves both and the filtering happens here. Department is
  /// matched after normalization for the same reason: legacy docs say
  /// "Electrical Engineering" where new ones say "EEE".
  Stream<QuerySnapshot<Map<String, dynamic>>> get _students =>
      FirebaseFirestore.instance.collection('students').snapshots();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesQuery(Map<String, dynamic> data) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();

    bool has(String field) =>
        (data[field] ?? '').toString().toLowerCase().contains(q);

    return has('name') || has('regNo') || has('email') || has('mobile');
  }

  void _openStudent(
    String uid,
    Map<String, dynamic> data,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentAttendanceScreen(
          studentUid: uid,
          studentData: data,
          marker: widget.marker,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    final years = widget.marker.visibleYears;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Students"),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: MaxWidthBody(
        child: Column(
        children: [
          if (years.length > 1) _buildYearStrip(years),
          _buildSearchField(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _students,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: Responsive.all(24),
                      child: Text(
                        "Couldn't load students: ${snapshot.error}",
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body,
                      ),
                    ),
                  );
                }

                final all = snapshot.data?.docs ?? [];

                final students = all.where((doc) {
                  final data = doc.data();
                  return AppConfig.departmentOf(data) ==
                          AppConfig.department &&
                      AppConfig.yearOf(data) == _selectedYear &&
                      _matchesQuery(data);
                }).toList()
                  ..sort((a, b) => (a.data()['name'] ?? '')
                      .toString()
                      .toLowerCase()
                      .compareTo(
                          (b.data()['name'] ?? '').toString().toLowerCase()));

                if (students.isEmpty) return _buildEmpty();

                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    Responsive.w(18),
                    Responsive.h(4),
                    Responsive.w(18),
                    Responsive.h(24),
                  ),
                  itemCount: students.length + 1,
                  separatorBuilder: (_, _) =>
                      SizedBox(height: Responsive.h(10)),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: EdgeInsets.only(bottom: Responsive.h(4)),
                        child: Text(
                          "${students.length} student"
                          "${students.length == 1 ? '' : 's'} in Year "
                          "$_selectedYear",
                          style: AppTextStyles.caption,
                        ),
                      );
                    }

                    final doc = students[index - 1];
                    final data = doc.data();

                    return _StudentTile(
                      name: (data['name'] ?? 'Unknown').toString(),
                      regNo: (data['regNo'] ?? '--').toString(),
                      photoUrl: data['profileImageUrl'] as String?,
                      isCr: (data['role'] ?? '')
                              .toString()
                              .toLowerCase() ==
                          'cr',
                      onTap: () => _openStudent(doc.id, data),
                    );
                  },
                );
              },
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildYearStrip(List<int> years) {
    return Padding(
      padding: Responsive.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: List.generate(years.length, (index) {
          final year = years[index];
          final selected = _selectedYear == year;

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                  right: index == years.length - 1 ? 0 : Responsive.w(8)),
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
                      color:
                          selected ? Colors.transparent : AppColors.divider,
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
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Responsive.w(18),
        widget.marker.visibleYears.length > 1 ? 0 : Responsive.h(14),
        Responsive.w(18),
        Responsive.h(14),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _query = value.trim()),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: "Search by name, reg no, email or mobile",
          hintStyle: AppTextStyles.caption,
          prefixIcon: const Icon(Icons.search_rounded,
              color: AppColors.textSecondary),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textSecondary),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: Responsive.symmetric(horizontal: 8, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.primary),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final searching = _query.isNotEmpty;

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
              child: Icon(
                searching
                    ? Icons.search_off_rounded
                    : Icons.people_outline_rounded,
                size: Responsive.sp(40),
                color: AppColors.primary,
              ),
            ),
            SizedBox(height: Responsive.h(16)),
            Text(
              searching
                  ? "No student matches \"$_query\""
                  : "No students registered in Year $_selectedYear",
              textAlign: TextAlign.center,
              style: AppTextStyles.title,
            ),
            SizedBox(height: Responsive.h(6)),
            Text(
              searching
                  ? "Try a different name or registration number."
                  : "Students appear here once they finish registration.",
              textAlign: TextAlign.center,
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
    );
  }
}

/// One student row — photo, name, reg no, and a CR badge where it
/// applies, so the class rep is recognisable in a long list.
class _StudentTile extends StatelessWidget {
  final String name;
  final String regNo;
  final String? photoUrl;
  final bool isCr;
  final VoidCallback onTap;

  const _StudentTile({
    required this.name,
    required this.regNo,
    required this.photoUrl,
    required this.isCr,
    required this.onTap,
  });

  String get _initial => name.isNotEmpty ? name[0].toUpperCase() : '?';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: Padding(
            padding: Responsive.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: Responsive.w(24),
                  backgroundColor: AppColors.primary.withValues(alpha: .1),
                  child: ClipOval(
                    child: photoUrl != null && photoUrl!.isNotEmpty
                        ? Image.network(
                            photoUrl!,
                            width: Responsive.w(48),
                            height: Responsive.w(48),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                _Initial(initial: _initial),
                          )
                        : _Initial(initial: _initial),
                  ),
                ),
                SizedBox(width: Responsive.w(14)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.title
                                  .copyWith(fontSize: Responsive.sp(15)),
                            ),
                          ),
                          if (isCr) ...[
                            SizedBox(width: Responsive.w(6)),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.teal.withValues(alpha: .14),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                "CR",
                                style: TextStyle(
                                  color: AppColors.tealDark,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: Responsive.h(3)),
                      Text("Reg $regNo", style: AppTextStyles.caption),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: AppColors.background,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_forward_ios_rounded,
                      size: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  final String initial;

  const _Initial({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: Responsive.w(48),
      height: Responsive.w(48),
      alignment: Alignment.center,
      color: AppColors.primary.withValues(alpha: .1),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: Responsive.sp(17),
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
