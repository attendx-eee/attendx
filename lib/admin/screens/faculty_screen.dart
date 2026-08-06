import 'package:attendx/admin/widgets/add_faculty_dialog.dart';
import 'package:attendx/admin/widgets/edit_faculty_dialog.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../models/faculty_model.dart';
import '../services/master_data_service.dart';
import '../widgets/confirm_and_delete.dart';
import '../widgets/management_icon_avatar.dart';

class FacultyScreen extends StatefulWidget {
  const FacultyScreen({super.key});

  @override
  State<FacultyScreen> createState() => _FacultyScreenState();
}

class _FacultyScreenState extends State<FacultyScreen> {
  Future<void> _handleDelete(BuildContext context, FacultyModel item) {
    return confirmAndDelete(
      context: context,
      title: "Delete Faculty",
      confirmMessage:
          "Are you sure you want to delete ${item.name}? This action cannot be undone.",
      checkInUse: () => MasterDataService.instance.isFacultyScheduled(item.id),
      inUseMessage:
          "${item.name} is currently assigned to one or more periods in the "
          "timetable. Remove or reassign those periods first, then delete "
          "${item.name}.",
      onDelete: () =>
          MasterDataService.instance.deleteFaculty(item.id, facultyName: item.name),
    );
  }

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
            // Bottom padding clears the extended FAB — otherwise the
            // last card ends up hidden behind it once the list is long
            // enough to scroll.
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
            itemCount: faculty.length,

            itemBuilder: (context, index) {

              final item = faculty[index];

              return Card(
                elevation: 1,
                margin: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),

                child: ListTile(

                  leading: const ManagementIconAvatar(
                    icon: Icons.person_rounded,
                    color: AppColors.teal,
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
                        onTap: () => _handleDelete(context, item),
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