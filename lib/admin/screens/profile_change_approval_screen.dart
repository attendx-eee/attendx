import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_config.dart';
import '../../notifications/services/notification_service.dart';

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

  Future<void> _decide(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> doc,
    bool approve,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final data = doc.data() ?? {};
    final name = data['name'] ?? 'Student';
    final pending =
        (data['pendingProfile'] as Map?)?.cast<String, dynamic>() ?? const {};

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
    return Scaffold(
      appBar: AppBar(title: const Text("Profile Change Requests")),
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
                  Icon(Icons.badge_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text("No pending profile change requests"),
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
              final pending = (data['pendingProfile'] as Map?)
                      ?.cast<String, dynamic>() ??
                  const {};
              final requestedName = pending['name'];
              final requestedYear = pending['year'];

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
                      Container(
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
                                "Year: Year $year → Year $requestedYear",
                                style: const TextStyle(fontSize: 12.5),
                              ),
                          ],
                        ),
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
                              label: const Text("Approve"),
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
