import 'package:flutter/material.dart';
import '../models/subject_model.dart';
import '../services/master_data_service.dart';
import '../widgets/add_subject_dialog.dart';
import '../widgets/confirm_and_delete.dart';
import '../widgets/edit_subject_dialog.dart';

class SubjectScreen extends StatefulWidget {
  const SubjectScreen({super.key});

  @override
  State<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<SubjectScreen> {
  int _selectedYear = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subject Management'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => const AddSubjectDialog(),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text("Add Subject"),
      ),
      body: Column(
        children: [
          // Year Filter Tabs
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
          // Subjects List
          Expanded(
            child: StreamBuilder<List<SubjectModel>>(
              stream: MasterDataService.instance.getSubjectsByYear(_selectedYear),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text(snapshot.error.toString()));
                }

                final subjects = snapshot.data ?? [];

                if (subjects.isEmpty) {
                  return const Center(child: Text("No subjects for this year"));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  itemCount: subjects.length,
                  itemBuilder: (context, index) {
                    final subject = subjects[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(subject.code),
                        ),
                        title: Text(subject.name),
                        subtitle: Text("Code: ${subject.code} | Sem: ${subject.semester}"),
                        trailing: PopupMenuButton(
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              child: const Text("Edit"),
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => EditSubjectDialog(subject: subject),
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
                                title: "Delete Subject",
                                confirmMessage: "Delete ${subject.name}?",
                                checkInUse: () =>
                                    MasterDataService.instance.isSubjectScheduled(subject),
                                inUseMessage:
                                    "${subject.name} is assigned in the Year ${subject.year} "
                                    "timetable. Remove or reassign those periods first, then "
                                    "delete ${subject.name}.",
                                onDelete: () => MasterDataService.instance
                                    .deleteSubject(subject.id, subject: subject),
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