import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';
import '../../faculty/models/faculty_account.dart';
import '../../notifications/services/notification_service.dart';
import '../models/faculty_model.dart';
import '../services/master_data_service.dart';

/// Admin-only: approve staff who have signed up, and say who they are on
/// the timetable.
///
/// Approving is two decisions in one, which is why this isn't a simple
/// yes/no list. "Is this person really staff" is the obvious one. The
/// second is "which timetable record are they" — periods name a
/// `facultyId`, not a person, so until that link is made an approved
/// account still has no classes. The admin picks it here.
class FacultyApprovalScreen extends StatelessWidget {
  const FacultyApprovalScreen({super.key});

  Stream<List<FacultyAccount>> get _pending => FirebaseFirestore.instance
      .collection('students')
      .where('role', isEqualTo: 'faculty')
      .snapshots()
      .map((snap) {
        final list = snap.docs
            .map((d) => FacultyAccount.fromMap(d.id, d.data()))
            .where((a) => a.isPending)
            .toList();
        list.sort((a, b) => a.name.compareTo(b.name));
        return list;
      });

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Faculty Approvals'),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: MaxWidthBody(
        maxWidth: 820,
        child: StreamBuilder<List<FacultyAccount>>(
          stream: _pending,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: Responsive.all(24),
                  child: Text("Couldn't load requests: ${snapshot.error}",
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body),
                ),
              );
            }

            final pending = snapshot.data ?? const <FacultyAccount>[];

            if (pending.isEmpty) return const _Empty();

            return ListView.separated(
              padding: Responsive.all(18),
              itemCount: pending.length,
              separatorBuilder: (_, _) => SizedBox(height: Responsive.h(12)),
              itemBuilder: (context, i) =>
                  _RequestCard(account: pending[i]),
            );
          },
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
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
              child: Icon(Icons.verified_user_outlined,
                  size: Responsive.sp(38), color: AppColors.primary),
            ),
            SizedBox(height: Responsive.h(16)),
            Text('No staff waiting for approval',
                style: AppTextStyles.title, textAlign: TextAlign.center),
            SizedBox(height: Responsive.h(6)),
            Text(
              'Teachers who register in the app will appear here.',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatefulWidget {
  final FacultyAccount account;

  const _RequestCard({required this.account});

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  String? _facultyId;
  bool _busy = false;

  /// Editable copies of what the applicant typed.
  ///
  /// People fill sign-up forms carelessly — a name in lower case, the
  /// wrong designation, blank initials. Rejecting them over it means a
  /// round trip and a second attempt; letting the admin fix it here
  /// costs one field and gets the record right first time.
  late final TextEditingController _name =
      TextEditingController(text: widget.account.name);
  late final TextEditingController _shortName =
      TextEditingController(text: widget.account.shortName);

  late String _designation =
      FacultyAccount.designations.contains(widget.account.designation)
          ? widget.account.designation
          : FacultyAccount.designations[2];

  bool _editing = false;

  @override
  void dispose() {
    _name.dispose();
    _shortName.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    if (_facultyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pick which timetable record this teacher is '
              'first — without it they have no classes.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _busy = true);

    try {
      // One account per timetable record: two logins on the same
      // facultyId would both see the same classes and could overwrite
      // each other's attendance.
      final clash = await FirebaseFirestore.instance
          .collection('students')
          .where('facultyId', isEqualTo: _facultyId)
          .limit(1)
          .get();

      if (clash.docs.isNotEmpty && clash.docs.first.id != widget.account.uid) {
        if (!mounted) return;
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Another account is already linked to that '
                'timetable record.'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Any corrections the admin made are saved with the approval, so
      // the record that goes live is the corrected one.
      await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.account.uid)
          .update({
        'facultyStatus': FacultyAccount.approved,
        'facultyId': _facultyId,
        'name': _name.text.trim().isEmpty
            ? widget.account.name
            : _name.text.trim(),
        'shortName': _shortName.text.trim().toUpperCase(),
        'designation': _designation,
        'facultyDecidedAt': FieldValue.serverTimestamp(),
      });

      await NotificationService.instance.createNotification(
        studentUid: widget.account.uid,
        title: 'Staff account approved',
        body: 'Your AttendX staff account is active. Your classes for '
            'today are on the home screen.',
        category: 'role',
        priority: 'high',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.account.name} approved.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Couldn't approve: $e"),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _reject() async {
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg)),
            title: Text('Reject ${widget.account.name}?',
                style: AppTextStyles.title),
            content: TextField(
              controller: noteController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Reason (sent to them)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Back',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Reject'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _busy = true);

    try {
      await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.account.uid)
          .update({
        'facultyStatus': FacultyAccount.rejected,
        'decisionNote': noteController.text.trim(),
        'facultyDecidedAt': FieldValue.serverTimestamp(),
      });

      await NotificationService.instance.createNotification(
        studentUid: widget.account.uid,
        title: 'Staff account not approved',
        body: noteController.text.trim().isEmpty
            ? 'Your AttendX staff account request was not approved. '
                'Contact the department office.'
            : noteController.text.trim(),
        category: 'role',
        priority: 'high',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Couldn't reject: $e"),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final initial = a.name.isNotEmpty ? a.name[0].toUpperCase() : '?';

    return Container(
      padding: Responsive.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: Responsive.w(22),
                backgroundColor: AppColors.teal.withValues(alpha: .14),
                child: Text(initial,
                    style: TextStyle(
                      color: AppColors.tealDark,
                      fontWeight: FontWeight.w800,
                      fontSize: Responsive.sp(16),
                    )),
              ),
              SizedBox(width: Responsive.w(14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.title
                            .copyWith(fontSize: Responsive.sp(15))),
                    SizedBox(height: Responsive.h(3)),
                    Text('${a.designation} • ${a.qualification}',
                        style: AppTextStyles.caption),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: Responsive.h(12)),
          Wrap(
            spacing: Responsive.w(8),
            runSpacing: Responsive.h(8),
            children: [
              _Tag(icon: Icons.mail_outline_rounded, text: a.email),
              _Tag(icon: Icons.phone_outlined, text: a.mobile),
              if (a.experienceYears > 0)
                _Tag(
                    icon: Icons.timeline_rounded,
                    text: '${a.experienceYears} yrs'),
            ],
          ),

          SizedBox(height: Responsive.h(6)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => setState(() => _editing = !_editing),
              icon: Icon(_editing ? Icons.close_rounded : Icons.edit_outlined,
                  size: 16),
              label: Text(_editing ? 'Done editing' : 'Correct details'),
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact),
            ),
          ),

          if (_editing) ...[
            SizedBox(height: Responsive.h(8)),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Full name',
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
            ),
            SizedBox(height: Responsive.h(10)),
            TextField(
              controller: _shortName,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Initials on the timetable',
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
            ),
            SizedBox(height: Responsive.h(10)),
            DropdownButtonFormField<String>(
              initialValue: _designation,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Designation',
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              items: FacultyAccount.designations
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: (v) => setState(() => _designation = v!),
            ),
          ],

          SizedBox(height: Responsive.h(14)),

          // The link that makes their timetable work.
          StreamBuilder<List<FacultyModel>>(
            stream: MasterDataService.instance.getFaculty(),
            builder: (context, snapshot) {
              final faculty = snapshot.data ?? const <FacultyModel>[];

              return DropdownButtonFormField<String>(
                initialValue: _facultyId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Timetable record *',
                  helperText: 'Which name on the timetable is this?',
                  helperMaxLines: 2,
                  prefixIcon: const Icon(Icons.link_rounded, size: 20),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                items: faculty
                    .map((f) => DropdownMenuItem(
                          value: f.id,
                          child: Text(
                            '${f.name}${f.shortName.isEmpty ? '' : ' (${f.shortName})'}',
                            style: TextStyle(fontSize: Responsive.sp(13)),
                          ),
                        ))
                    .toList(),
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _facultyId = v),
              );
            },
          ),

          SizedBox(height: Responsive.h(14)),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _reject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    padding: Responsive.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.xs)),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              SizedBox(width: Responsive.w(12)),
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy ? null : _approve,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: Responsive.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.xs)),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
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
