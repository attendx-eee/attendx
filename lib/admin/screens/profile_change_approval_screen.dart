import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_config.dart';
import '../../notifications/services/notification_service.dart';
import '../widgets/pending_approval_list.dart';

/// Admin-only: approve or reject student requests to change their name
/// or year. Students can update these from Account Settings, but the
/// change is only staged (`pendingProfile`) until an admin decides here
/// — approving copies the requested values into the live `name`/`year`
/// fields; rejecting just clears the request. Batch changes never go
/// through this screen — those save immediately, no approval needed.
class ProfileChangeApprovalScreen extends StatelessWidget {
  const ProfileChangeApprovalScreen({super.key});

  Stream<QuerySnapshot<Map<String, dynamic>>> get _pending =>
      FirebaseFirestore.instance
          .collection('students')
          .where('profileChangeStatus', isEqualTo: 'pending')
          .snapshots();

  Map<String, dynamic> _pendingProfileOf(Map<String, dynamic> data) =>
      (data['pendingProfile'] as Map?)?.cast<String, dynamic>() ?? const {};

  Widget? _buildDetail(Map<String, dynamic> data) {
    final pending = _pendingProfileOf(data);
    final requestedName = pending['name'];
    final requestedYear = pending['year'];

    if (requestedName == null && requestedYear == null) return null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (requestedName != null)
            Text(
              "Name: ${data['name'] ?? '--'} → $requestedName",
              style: const TextStyle(fontSize: 12.5),
            ),
          if (requestedYear != null)
            Text(
              "Year: Year ${AppConfig.yearOf(data)} → Year $requestedYear",
              style: const TextStyle(fontSize: 12.5),
            ),
        ],
      ),
    );
  }

  Future<void> _decide(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> doc,
    bool approve,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final data = doc.data() ?? {};
    final name = data['name'] ?? 'Student';
    final pending = _pendingProfileOf(data);

    try {
      await doc.reference.update({
        'profileChangeStatus': approve ? 'approved' : 'rejected',
        'profileChangeDecidedAt': FieldValue.serverTimestamp(),
        'pendingProfile': FieldValue.delete(),
        if (approve && pending.containsKey('name')) 'name': pending['name'],
        if (approve && pending.containsKey('year')) 'year': pending['year'],
      });

      final changeSummary = [
        if (pending['name'] != null) 'name to "${pending['name']}"',
        if (pending['year'] != null) 'year to Year ${pending['year']}',
      ].join(' and ');

      await NotificationService.instance.createNotification(
        studentUid: doc.id,
        title: approve ? 'Profile Change Approved' : 'Profile Change Rejected',
        body: approve
            ? 'Your request to change your $changeSummary was approved.'
            : 'Your request to change your $changeSummary was not approved. Contact the department office for details.',
        category: 'profile',
        priority: 'high',
      );

      messenger.showSnackBar(
        SnackBar(
          content:
              Text(approve ? '$name\'s change approved' : '$name\'s change rejected'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to update: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PendingApprovalList(
      title: "Profile Change Requests",
      pendingStream: _pending,
      emptyIcon: Icons.badge_outlined,
      emptyText: "No pending profile change requests",
      detailBuilder: _buildDetail,
      onDecide: _decide,
    );
  }
}
