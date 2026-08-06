import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_config.dart';

/// Shared scaffold for admin "pending request" approval screens — CR
/// requests and profile change requests both stream pending `students`
/// docs, show the same header (avatar, name, reg no / year / department),
/// and end in a Reject/Approve row. This widget owns the stream/loading/
/// empty-state handling and the card chrome; each concrete screen only
/// supplies the query, copy, an optional extra detail box, and what
/// actually happens on approve/reject.
class PendingApprovalList extends StatelessWidget {
  final String title;
  final Stream<QuerySnapshot<Map<String, dynamic>>> pendingStream;
  final IconData emptyIcon;
  final String emptyText;
  final String approveLabel;

  /// Extra content shown between the header row and the buttons (e.g.
  /// the amber "requested changes" box on Profile Change Requests).
  /// Return null for nothing extra (CR Approvals has none).
  final Widget? Function(Map<String, dynamic> data)? detailBuilder;

  final Future<void> Function(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> doc,
    bool approve,
  ) onDecide;

  const PendingApprovalList({
    super.key,
    required this.title,
    required this.pendingStream,
    required this.emptyIcon,
    required this.emptyText,
    required this.onDecide,
    this.approveLabel = "Approve",
    this.detailBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: pendingStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(emptyIcon, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(emptyText),
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
              final detail = detailBuilder?.call(data);

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
                      if (detail != null) ...[
                        const SizedBox(height: 12),
                        detail,
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => onDecide(context, doc, false),
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
                              onPressed: () => onDecide(context, doc, true),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: Text(approveLabel),
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
