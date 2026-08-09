import 'package:flutter/material.dart';
import '../models/faculty_model.dart';
import '../services/master_data_service.dart';

class EditFacultyDialog extends StatefulWidget {
  final FacultyModel faculty;

  const EditFacultyDialog({
    super.key,
    required this.faculty,
  });

  @override
  State<EditFacultyDialog> createState() => _EditFacultyDialogState();
}

class _EditFacultyDialogState extends State<EditFacultyDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _shortController;

  String? _selectedDesignation;

  final List<String> designations = [
    "Professor",
    "Associate Professor",
    "Assistant Professor",
    "PHD Scholar",
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.faculty.name);
    _shortController = TextEditingController(text: widget.faculty.shortName);
    _selectedDesignation = widget.faculty.designation;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _shortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        "Edit Faculty",
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: "Faculty Name",
                  hintText: "e.g., Dr. Jane Doe",
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Enter faculty name";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _shortController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: "Short Name",
                  hintText: "e.g., JDOE",
                  prefixIcon: Icon(Icons.badge),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Enter short name";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedDesignation,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: "Designation",
                  prefixIcon: Icon(Icons.work),
                  border: OutlineInputBorder(),
                ),
                hint: const Text("Select designation"),
                items: designations
                    .map((designation) => DropdownMenuItem(
                          value: designation,
                          child: Text(
                            designation,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedDesignation = value;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Select a designation";
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () async {
            if (!_formKey.currentState!.validate()) return;

            final faculty = FacultyModel(
              id: widget.faculty.id,
              name: _nameController.text.trim(),
              shortName: _shortController.text.trim().toUpperCase(),
              designation: _selectedDesignation!,
              active: true,
            );

            await MasterDataService.instance.updateFaculty(faculty);

            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          child: const Text("Update"),
        ),
      ],
    );
  }
}
