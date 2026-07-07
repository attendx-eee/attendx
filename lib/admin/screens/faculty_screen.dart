import 'package:attendx/admin/widgets/add_faculty_dialog.dart';
import 'package:attendx/admin/widgets/edit_faculty_dialog.dart';
import 'package:flutter/material.dart';
import '../services/master_data_service.dart';

class FacultyScreen extends StatefulWidget {
  const FacultyScreen({super.key});

  @override
  State<FacultyScreen> createState() => _FacultyScreenState();
}

class _FacultyScreenState extends State<FacultyScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Faculty Management"),
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => const AddFacultyDialog(),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text("Add Faculty"),

      ),

      body: StreamBuilder(
        stream: MasterDataService.instance.getFaculty(),
        builder: (context, snapshot) {

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(snapshot.error.toString()),
            );
          }

          final faculty = snapshot.data ?? [];

          if (faculty.isEmpty) {
            return const Center(
              child: Text("No Faculty Added"),
            );
          }

          return ListView.builder(
            itemCount: faculty.length,

            itemBuilder: (context, index) {

              final item = faculty[index];

              return Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 8,
                ),

                child: ListTile(

                  leading: CircleAvatar(
                    child: Text(item.shortName),
                  ),

                  title: Text(item.name),

                  subtitle: Text(item.designation),

                  trailing: PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: const Text("Edit"),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => EditFacultyDialog(faculty: item),
                          );
                        },
                      ),
                      PopupMenuItem(
                        child: const Text(
                          "Delete",
                          style: TextStyle(color: Colors.red),
                        ),
                        onTap: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              title: const Text(
                                "Delete Faculty",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              content: Text(
                                "Are you sure you want to delete ${item.name}? This action cannot be undone.",
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text("Cancel"),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text(
                                    "Delete",
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ) ?? false;

                          if (confirm) {
                            await MasterDataService.instance
                                .deleteFaculty(item.id);
                          }
                        },
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