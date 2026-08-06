import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../notifications/services/notification_service.dart';
import '../widgets/pending_approval_list.dart';

/// Admin-only: approve or reject Class Representative requests.
/// Approval flips the student's role to "cr", unlocking the CR
/// timetable tools on their dashboard instantly.
class CrApprovalScreen extends StatelessWidget {
  const CrApprovalScreen({super.key});

  Stream<QuerySnapshot<Map<String, dynamic>>> get _pending =>
      FirebaseFirestore.instance
          .collection('students')
          .where('crStatus', isEqualTo: 'pending')
          .snapshots();

  Future<void> _decide(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> doc,
    bool approve,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final data = doc.data() ?? {};
    final name = data['name'] ?? 'Student';

    try {
      await doc.reference.update({
        'crStatus': approve ? 'approved' : 'rejected',
        'crDecidedAt': FieldValue.serverTimestamp(),
        if (approve) 'role': 'cr',
      });

      // Tell the student immediately.
      await NotificationService.instance.createNotification(
        studentUid: doc.id,
        title: approve ? 'CR Request Approved' : 'CR Request Rejected',
        body: approve
            ? 'You are now the Class Representative. CR timetable tools are unlocked on your dashboard.'
            : 'Your Class Representative request was not approved. You can contact the department office for details.',
        category: 'role',
        priority: 'high',
      );

      messenger.showSnackBar(
        SnackBar(
          content: Text(approve ? '$name approved as CR' : '$name rejected'),
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
      title: "CR Approvals",
      pendingStream: _pending,
      emptyIcon: Icons.how_to_reg_rounded,
      emptyText: "No pending CR requests",
      approveLabel: "Approve as CR",
      onDecide: _decide,
    );
  }
}
