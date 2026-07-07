import 'package:flutter/material.dart';

import '../../core/constants/app_config.dart';
import '../services/batch_service.dart';

/// Admin: set how many lab batches each year is divided into.
/// 2 batches = Batch A + Batch B. Lab periods in the timetable can then
/// be assigned to a specific batch.
class BatchScreen extends StatelessWidget {
  const BatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Batch Management")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            "Divide each year into lab batches. Labs in the timetable can be assigned to a specific batch.",
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          for (var year = 1; year <= 4; year++) _YearBatchCard(year: year),
        ],
      ),
    );
  }
}

class _YearBatchCard extends StatelessWidget {
  final int year;

  const _YearBatchCard({required this.year});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<int>(
      stream: BatchService.instance.watchBatchCount(
        department: AppConfig.department,
        year: year,
      ),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 1;
        final labels = BatchService.labels(count);

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          theme.colorScheme.primaryContainer,
                      child: Text("Y$year",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text("Year $year",
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: count <= 1
                          ? null
                          : () => BatchService.instance.setBatchCount(
                                department: AppConfig.department,
                                year: year,
                                count: count - 1,
                              ),
                    ),
                    Text("$count",
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: count >= 6
                          ? null
                          : () => BatchService.instance.setBatchCount(
                                department: AppConfig.department,
                                year: year,
                                count: count + 1,
                              ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    if (count <= 1)
                      Chip(
                        label: const Text("No batch split — whole class"),
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      )
                    else
                      ...labels.map(
                        (b) => Chip(
                          avatar: const Icon(Icons.groups_rounded, size: 16),
                          label: Text("Batch $b"),
                          backgroundColor:
                              theme.colorScheme.primaryContainer
                                  .withValues(alpha: .4),
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
  }
}
