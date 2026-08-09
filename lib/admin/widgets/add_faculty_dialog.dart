import 'package:flutter/material.dart';
import '../models/faculty_model.dart';
import '../services/master_data_service.dart';

class AddFacultyDialog extends StatefulWidget {
  const AddFacultyDialog({super.key});

  @override
  State<AddFacultyDialog> createState() => _AddFacultyDialogState();
}

class _AddFacultyDialogState extends State<AddFacultyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _shortController = TextEditingController();

  String? _selectedDesignation;
  
  final List<String> designations = [
    "Professor",
    "Associate Professor",
    "Assistant Professor",
    "PHD Scholar",
  ];

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
        "Add Faculty",
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
              // --- Faculty Name Field ---
              TextFormField(
                controller: _nameController, // Hooked up controller
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

              // --- Short Name / Abbreviation Field ---
              TextFormField(
                controller: _shortController, // Hooked up controller
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


              // --- Designation Dropdown ---
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
              id: '',
              name: _nameController.text.trim(),
              shortName: _shortController.text.trim().toUpperCase(),
              designation: _selectedDesignation!,
              active: true,
            );

            await MasterDataService.instance.addFaculty(faculty);

            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          child: const Text("Save"),
        ),
      ],
    );
  }
}
