import 'package:flutter/material.dart';
import '../models/lab_model.dart';
import '../services/master_data_service.dart';

class EditLabDialog extends StatefulWidget {
  final LabModel lab;

  const EditLabDialog({
    super.key,
    required this.lab,
  });

  @override
  State<EditLabDialog> createState() => _EditLabDialogState();
}

class _EditLabDialogState extends State<EditLabDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _codeController;

  late int _selectedYear;
  late String _selectedSemester;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.lab.name);
    _codeController = TextEditingController(text: widget.lab.code);
    _selectedYear = widget.lab.year;
    _selectedSemester = widget.lab.semester;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        "Edit Lab",
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  labelText: "Lab Name",
                  hintText: "e.g., Digital Electronics Lab",
                  prefixIcon: Icon(Icons.science),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Enter lab name";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: "Lab Code",
                  hintText: "e.g., EE201L",
                  prefixIcon: Icon(Icons.code),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Enter lab code";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _selectedYear,
                decoration: const InputDecoration(
                  labelText: "Year",
                  prefixIcon: Icon(Icons.school),
                  border: OutlineInputBorder(),
                ),
                items: List.generate(
                  4,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text("Year ${index + 1}"),
                  ),
                ),
                onChanged: (value) {
                  setState(() => _selectedYear = value ?? 1);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedSemester,
                decoration: const InputDecoration(
                  labelText: "Semester",
                  prefixIcon: Icon(Icons.calendar_month),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: "Odd", child: Text("Odd")),
                  DropdownMenuItem(value: "Even", child: Text("Even")),
                ],
                onChanged: (value) {
                  setState(() => _selectedSemester = value ?? "Odd");
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () async {
            if (!_formKey.currentState!.validate()) return;

            final lab = LabModel(
              id: widget.lab.id,
              name: _nameController.text.trim(),
              code: _codeController.text.trim().toUpperCase(),
              year: _selectedYear,
              semester: _selectedSemester,
            );

            await MasterDataService.instance.updateLab(lab);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text("Update"),
        ),
      ],
    );
  }
}
