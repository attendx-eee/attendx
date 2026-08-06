import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../models/lab_model.dart';
import '../services/master_data_service.dart';
import '../widgets/add_lab_dialog.dart';
import '../widgets/confirm_and_delete.dart';
import '../widgets/edit_lab_dialog.dart';
import '../widgets/management_icon_avatar.dart';

class LabScreen extends StatefulWidget {
  const LabScreen({super.key});

  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> {
  int _selectedYear = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lab Management'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => const AddLabDialog(),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text("Add Lab"),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: List.generate(
                4,
                (index) {
                  final year = index + 1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: _selectedYear == year,
                      label: Text("Year $year"),
                      onSelected: (selected) {
                        setState(() => _selectedYear = year);
                      },
                    ),
                  );
                },
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<LabModel>>(
              stream: MasterDataService.instance.getLabsByYear(_selectedYear),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text(snapshot.error.toString()));
                }

                final labs = snapshot.data ?? [];

                if (labs.isEmpty) {
                  return const Center(child: Text("No labs for this year"));
                }

                return ListView.builder(
                  // Bottom padding clears the extended FAB — otherwise the
                  // last card ends up hidden behind it once the list is
                  // long enough to scroll.
                  padding: const EdgeInsets.fromLTRB(15, 8, 15, 100),
                  itemCount: labs.length,
                  itemBuilder: (context, index) {
                    final lab = labs[index];
                    return Card(
                      elevation: 1,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: ListTile(
                        leading: const ManagementIconAvatar(
                          icon: Icons.science_rounded,
                          color: AppColors.primary,
                        ),
                        title: Text(lab.name),
                        subtitle: Text("Code: ${lab.code} | Sem: ${lab.semester}"),
                        trailing: PopupMenuButton(
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              child: const Text("Edit"),
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => EditLabDialog(lab: lab),
                                );
                              },
                            ),
                            PopupMenuItem(
                              child: const Text(
                                "Delete",
                                style: TextStyle(color: Colors.red),
                              ),
                              onTap: () => confirmAndDelete(
                                context: context,
                                title: "Delete Lab",
                                confirmMessage: "Delete ${lab.name}?",
                                checkInUse: () =>
                                    MasterDataService.instance.isLabScheduled(lab),
                                inUseMessage:
                                    "${lab.name} is assigned in the Year ${lab.year} "
                                    "timetable. Remove or reassign those lab periods first, "
                                    "then delete ${lab.name}.",
                                onDelete: () => MasterDataService.instance
                                    .deleteLab(lab.id, lab: lab),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
