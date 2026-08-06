import 'package:flutter/material.dart';

import '../../attendance/models/attendance_permission_model.dart';
import '../../attendance/services/attendance_permission_service.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';

/// Admin-only: decide which CRs may mark attendance, and for which month.
///
/// Two tabs, because the two jobs are genuinely different: the first is a
/// queue to work through, the second is a standing list to audit and, if
/// something looks wrong, revoke before the month is out.
class AttendancePermissionScreen extends StatelessWidget {
  const AttendancePermissionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text("Attendance Access"),
          backgroundColor: AppColors.background,
          surfaceTintColor: AppColors.background,
          elevation: 0,
          foregroundColor: AppColors.textPrimary,
          bottom: const TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(text: "Pending"),
              Tab(text: "Approved"),
            ],
          ),
        ),
        body: const MaxWidthBody(
          maxWidth: 820,
          child: TabBarView(
            children: [
              _PermissionList(status: PermissionStatus.pending),
              _PermissionList(status: PermissionStatus.approved),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionList extends StatelessWidget {
  final String status;

  const _PermissionList({required this.status});

  bool get _isPending => status == PermissionStatus.pending;

  Future<void> _decide(
    BuildContext context,
    AttendancePermission permission,
    bool approve,
  ) async {
    final noteController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    // Approving is the common, low-friction path, so it goes through
    // without a dialog. Saying no — or taking access back — is worth a
    // sentence the CR can actually act on, so those ask for a note.
    if (!approve) {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              title: Text(
                _isPending ? "Decline Request" : "Revoke Access",
                style: AppTextStyles.title,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${permission.crName} • Year ${permission.year} • "
                    "${permission.monthName}",
                    style: AppTextStyles.caption,
                  ),
                  SizedBox(height: Responsive.h(16)),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: "Reason (sent to the CR)",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text("Back",
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                  ),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(_isPending ? "Decline" : "Revoke"),
                ),
              ],
            ),
          ) ??
          false;

      if (!confirmed) return;
    }

    try {
      if (_isPending) {
        await AttendancePermissionService.instance.decide(
          permission: permission,
          approve: approve,
          note: noteController.text.trim(),
        );
      } else {
        await AttendancePermissionService.instance.revoke(
          permission: permission,
          note: noteController.text.trim(),
        );
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? "${permission.crName} can now mark attendance for "
                    "${permission.monthName}."
                : "${permission.crName}'s access for "
                    "${permission.monthName} was withdrawn.",
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text("Couldn't update: $e"),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AttendancePermission>>(
      stream: _isPending
          ? AttendancePermissionService.instance.watchPending()
          : AttendancePermissionService.instance
              .watchApproved(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: Responsive.all(24),
              child: Text("Couldn't load requests: ${snapshot.error}",
                  textAlign: TextAlign.center, style: AppTextStyles.body),
            ),
          );
        }

        final items = snapshot.data ?? const <AttendancePermission>[];

        if (items.isEmpty) {
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
                      _isPending
                          ? Icons.inbox_rounded
                          : Icons.verified_user_outlined,
                      size: Responsive.sp(38),
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(height: Responsive.h(16)),
                  Text(
                    _isPending
                        ? "No pending access requests"
                        : "No CR currently has access",
                    style: AppTextStyles.title,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: Responsive.h(6)),
                  Text(
                    _isPending
                        ? "CRs asking to mark attendance will show up here."
                        : "Approve a request to grant a CR access for a month.",
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: Responsive.all(18),
          itemCount: items.length,
          separatorBuilder: (_, _) => SizedBox(height: Responsive.h(12)),
          itemBuilder: (context, index) => _PermissionCard(
            permission: items[index],
            isPending: _isPending,
            onApprove: () => _decide(context, items[index], true),
            onDeny: () => _decide(context, items[index], false),
          ),
        );
      },
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final AttendancePermission permission;
  final bool isPending;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  const _PermissionCard({
    required this.permission,
    required this.isPending,
    required this.onApprove,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    final initial = permission.crName.isNotEmpty
        ? permission.crName[0].toUpperCase()
        : '?';

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
                child: Text(
                  initial,
                  style: TextStyle(
                    color: AppColors.tealDark,
                    fontWeight: FontWeight.w800,
                    fontSize: Responsive.sp(16),
                  ),
                ),
              ),
              SizedBox(width: Responsive.w(14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(permission.crName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.title
                            .copyWith(fontSize: Responsive.sp(15))),
                    SizedBox(height: Responsive.h(3)),
                    Text(
                      "Year ${permission.year} CR  •  ${permission.department}",
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  permission.monthName,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: Responsive.sp(11),
                  ),
                ),
              ),
            ],
          ),
          if (permission.requestNote.isNotEmpty) ...[
            SizedBox(height: Responsive.h(12)),
            Container(
              width: double.infinity,
              padding: Responsive.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text('"${permission.requestNote}"',
                  style: AppTextStyles.caption
                      .copyWith(fontStyle: FontStyle.italic)),
            ),
          ],
          SizedBox(height: Responsive.h(14)),
          Row(
            children: [
              if (isPending) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDeny,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      padding: Responsive.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                    ),
                    child: const Text("Decline"),
                  ),
                ),
                SizedBox(width: Responsive.w(12)),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onApprove,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: Responsive.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                    ),
                    child: const Text("Approve"),
                  ),
                ),
              ] else
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDeny,
                    icon: const Icon(Icons.lock_outline_rounded, size: 17),
                    label: const Text("Revoke Access"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      padding: Responsive.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
