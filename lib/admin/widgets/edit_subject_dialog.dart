import 'package:flutter/material.dart';
import '../models/subject_model.dart';
import '../services/master_data_service.dart';

class EditSubjectDialog extends StatefulWidget {
  final SubjectModel subject;

  const EditSubjectDialog({
    super.key,
    required this.subject,
  });

  @override
  State<EditSubjectDialog> createState() => _EditSubjectDialogState();
}

class _EditSubjectDialogState extends State<EditSubjectDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _codeController;

  late int _selectedYear;
  late String _selectedSemester;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.subject.name);
    _codeController = TextEditingController(text: widget.subject.code);
    _selectedYear = widget.subject.year;
    _selectedSemester = widget.subject.semester;
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
        "Edit Subject",
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
                  labelText: "Subject Name",
                  hintText: "e.g., Digital Signal Processing",
                  prefixIcon: Icon(Icons.subject),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Enter subject name";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: "Subject Code",
                  hintText: "e.g., EC501",
                  prefixIcon: Icon(Icons.code),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Enter subject code";
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

            final subject = SubjectModel(
              id: widget.subject.id,
              name: _nameController.text.trim(),
              code: _codeController.text.trim().toUpperCase(),
              year: _selectedYear,
              semester: _selectedSemester,
            );

            await MasterDataService.instance.updateSubject(subject);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text("Update"),
        ),
      ],
    );
  }
}
