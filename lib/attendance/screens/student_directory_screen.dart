import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/auth/account_lookup.dart';
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

  /// Removes a student record.
  ///
  /// Mostly for the debris a sign-up flow leaves behind — a half-created
  /// document with no name and no register number, which otherwise sits
  /// in the year list forever and skews every count on the Analysis
  /// page. Deliberately admin-only and deliberately noisy: the dialog
  /// names the record and says plainly what survives, because deleting
  /// a real student here would be silent and unrecoverable.
  Future<void> _deleteStudent(
      String uid, Map<String, dynamic> data) async {
    final name = (data['name'] ?? '').toString().trim();
    final regNo = (data['regNo'] ?? '').toString().trim();
    final label = name.isEmpty ? 'this unnamed record' : name;
    final incomplete = name.isEmpty && regNo.isEmpty;

    final go = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg)),
            title: Text('Remove $label?', style: AppTextStyles.title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  incomplete
                      ? 'This record has no name and no register number, '
                          'so it is almost certainly an abandoned sign-up.'
                      : 'This removes $label'
                          '${regNo.isEmpty ? '' : ' (Reg $regNo)'} from the '
                          'directory. Their attendance history stays, but '
                          'nothing will link to it.',
                  style: AppTextStyles.caption,
                ),
                SizedBox(height: Responsive.h(10)),
                Text(
                  'Their login account is not deleted — that is done from '
                  'the Firebase console.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;

    if (!go) return;

    final messenger = ScaffoldMessenger.of(context);

    try {
      await FirebaseFirestore.instance
          .collection('students')
          .doc(uid)
          .delete();

      messenger.showSnackBar(
        SnackBar(
          content: Text('Removed $label from the directory.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text("Couldn't remove it: $e"),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

                // Staff whose records still sit in `students` from
                // before the collection split. An admin account has no
                // year, so AppConfig.yearOf falls back to 1 and it
                // surfaces at the top of Year 1 as "Unknown".
                final strays = all
                    .where((d) => !AccountLookup.isStudentDoc(d.data()))
                    .toList();

                final students = all.where((doc) {
                  final data = doc.data();
                  return AccountLookup.isStudentDoc(data) &&
                      AppConfig.departmentOf(data) ==
                          AppConfig.department &&
                      AppConfig.yearOf(data) == _selectedYear &&
                      _matchesQuery(data);
                }).toList()
                  ..sort((a, b) => (a.data()['name'] ?? '')
                      .toString()
                      .toLowerCase()
                      .compareTo(
                          (b.data()['name'] ?? '').toString().toLowerCase()));

                if (students.isEmpty) {
                  // Column + Expanded, not a ListView. _buildEmpty ends
                  // in a Center wrapping an unbounded Column, which a
                  // ListView child cannot size — it throws rather than
                  // rendering, and the whole list area comes back blank.
                  return Column(
                    children: [
                      if (strays.isNotEmpty && widget.marker.isAdmin)
                        Padding(
                          padding: Responsive.all(18),
                          child: _buildStrayNotice(strays),
                        ),
                      Expanded(child: _buildEmpty()),
                    ],
                  );
                }

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
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (strays.isNotEmpty && widget.marker.isAdmin) ...[
                            _buildStrayNotice(strays),
                            SizedBox(height: Responsive.h(12)),
                          ],
                          Padding(
                            padding:
                                EdgeInsets.only(bottom: Responsive.h(4)),
                            child: Text(
                              "${students.length} student"
                              "${students.length == 1 ? '' : 's'} in Year "
                              "$_selectedYear",
                              style: AppTextStyles.caption,
                            ),
                          ),
                        ],
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
                      onDelete: widget.marker.isAdmin
                          ? () => _deleteStudent(doc.id, data)
                          : null,
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

  /// Banner listing staff records still sitting in `students`.
  ///
  /// They're already hidden from the list, so nothing is broken — but
  /// leaving them there silently means the next person to look at the
  /// database finds an admin filed as a first-year and has no idea why.
  Widget _buildStrayNotice(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> strays) {
    return Container(
      padding: Responsive.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.warning.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.moving_rounded,
                  size: Responsive.sp(18), color: AppColors.warning),
              SizedBox(width: Responsive.w(8)),
              Expanded(
                child: Text(
                  '${strays.length} staff record'
                  '${strays.length == 1 ? '' : 's'} still in "students"',
                  style: AppTextStyles.title
                      .copyWith(fontSize: Responsive.sp(13)),
                ),
              ),
            ],
          ),
          SizedBox(height: Responsive.h(6)),
          Text(
            'Admins belong in "admins" and faculty in "faculty_accounts". '
            'These are hidden from the list and excluded from every '
            'count, but they should be moved.',
            style: AppTextStyles.caption,
          ),
          SizedBox(height: Responsive.h(10)),
          ...strays.map((doc) {
            final data = doc.data();
            final role = (data['role'] ?? '?').toString();
            final target = AccountLookup.isAdminRole(role.toLowerCase())
                ? AccountLookup.admins
                : AccountLookup.facultyAccounts;

            return Padding(
              padding: EdgeInsets.only(bottom: Responsive.h(8)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['name']?.toString().isNotEmpty == true
                              ? '${data['name']} • $role'
                              : role,
                          style: AppTextStyles.caption
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                        SelectableText(
                          'Move to  $target/${doc.id}',
                          style: AppTextStyles.caption.copyWith(
                            fontFamily: 'monospace',
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _migrateStray(doc.id, data, target),
                    child: const Text('Move'),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Copies a staff record into its proper collection, then removes it
  /// from `students`.
  ///
  /// Copy-then-delete, not a move: if the delete fails the account still
  /// works from its new home, whereas a failed copy after a delete would
  /// lock somebody out of the console.
  Future<void> _migrateStray(
    String uid,
    Map<String, dynamic> data,
    String target,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final db = FirebaseFirestore.instance;

    try {
      await db.collection(target).doc(uid).set(data, SetOptions(merge: true));
      await db.collection(AccountLookup.students).doc(uid).delete();

      messenger.showSnackBar(
        SnackBar(
          content: Text('Moved to $target. Sign out and back in to pick up '
              'the new record.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text("Couldn't move it: $e"),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

  /// Null for anyone who isn't an admin — the row simply has no delete
  /// affordance rather than one that fails when pressed.
  final VoidCallback? onDelete;

  const _StudentTile({
    required this.name,
    required this.regNo,
    required this.photoUrl,
    required this.isCr,
    required this.onTap,
    this.onDelete,
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
                if (onDelete != null)
                  IconButton(
                    tooltip: 'Remove this record',
                    onPressed: onDelete,
                    icon: Icon(Icons.delete_outline_rounded,
                        size: Responsive.sp(19),
                        color: AppColors.textSecondary),
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
