import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_config.dart';
import '../../notifications/services/notification_service.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text("CR Approvals")),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _pending,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.how_to_reg_rounded,
                      size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text("No pending CR requests"),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final year = AppConfig.yearOf(data);

              return Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            child: Text(
                              (data['name'] ?? '?')
                                  .toString()
                                  .substring(0, 1)
                                  .toUpperCase(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data['name'] ?? 'Unknown',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  "Reg ${data['regNo'] ?? '--'}  •  Year $year  •  ${data['department'] ?? ''}",
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _decide(context, doc, false),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: const Text("Reject"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(
                                    color: Colors.redAccent),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _decide(context, doc, true),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text("Approve as CR"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
