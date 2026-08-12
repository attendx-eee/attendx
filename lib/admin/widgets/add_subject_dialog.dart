import 'package:flutter/material.dart';
import '../models/subject_model.dart';
import '../services/master_data_service.dart';

class AddSubjectDialog extends StatefulWidget {
  /// Pre-selects the year (e.g. when opened from the Timetable screen
  /// for a specific year's Add Period form) instead of always defaulting
  /// to Year 1.
  final int? initialYear;

  const AddSubjectDialog({super.key, this.initialYear});

  @override
  State<AddSubjectDialog> createState() => _AddSubjectDialogState();
}

class _AddSubjectDialogState extends State<AddSubjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();

  /// Classes the syllabus is planned around. Pre-filled with the usual
  /// figure so nobody has to think about it for the common case.
  final _targetController = TextEditingController(
      text: '${SubjectModel.defaultTarget}');

  late int _selectedYear = widget.initialYear ?? 1;
  String _selectedSemester = "Odd";

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        "Add Subject",
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
              TextFormField(
                controller: _targetController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Classes to complete",
                  hintText: "e.g., 64",
                  helperText: "Used to track syllabus progress",
                  prefixIcon: Icon(Icons.checklist_rtl_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final n = int.tryParse((value ?? '').trim());
                  if (n == null || n <= 0) return "Enter a number";
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
              id: '',
              name: _nameController.text.trim(),
              code: _codeController.text.trim().toUpperCase(),
              year: _selectedYear,
              semester: _selectedSemester,
              targetClasses:
                  int.tryParse(_targetController.text.trim()) ??
                      SubjectModel.defaultTarget,
            );

            await MasterDataService.instance.addSubject(subject);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text("Save"),
        ),
      ],
    );
  }
}
