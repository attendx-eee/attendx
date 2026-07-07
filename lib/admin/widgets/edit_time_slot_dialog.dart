import 'package:flutter/material.dart';
import '../models/time_slot_model.dart';
import '../services/master_data_service.dart';

class EditTimeSlotDialog extends StatefulWidget {
  final TimeSlotModel timeSlot;

  const EditTimeSlotDialog({
    super.key,
    required this.timeSlot,
  });

  @override
  State<EditTimeSlotDialog> createState() => _EditTimeSlotDialogState();
}

class _EditTimeSlotDialogState extends State<EditTimeSlotDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _slotNumberController;
  late TextEditingController _startTimeController;
  late TextEditingController _endTimeController;

  Future<void> _selectTime(TextEditingController controller) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time != null) {
      controller.text = "${time.hour}:${time.minute.toString().padLeft(2, '0')}";
    }
  }

  @override
  void initState() {
    super.initState();
    _slotNumberController = TextEditingController(text: widget.timeSlot.slotNumber.toString());
    _startTimeController = TextEditingController(text: widget.timeSlot.startTime);
    _endTimeController = TextEditingController(text: widget.timeSlot.endTime);
  }

  @override
  void dispose() {
    _slotNumberController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        "Edit Time Slot",
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
                controller: _slotNumberController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Slot Number",
                  hintText: "e.g., 1",
                  prefixIcon: Icon(Icons.numbers),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Enter slot number";
                  }
                  if (int.tryParse(value) == null) {
                    return "Enter a valid number";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _startTimeController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: "Start Time",
                  hintText: "Select start time",
                  prefixIcon: const Icon(Icons.access_time),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.schedule),
                    onPressed: () => _selectTime(_startTimeController),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Select start time";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _endTimeController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: "End Time",
                  hintText: "Select end time",
                  prefixIcon: const Icon(Icons.access_time),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.schedule),
                    onPressed: () => _selectTime(_endTimeController),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Select end time";
                  }
                  return null;
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

            final timeSlot = TimeSlotModel(
              id: widget.timeSlot.id,
              startTime: _startTimeController.text.trim(),
              endTime: _endTimeController.text.trim(),
              slotNumber: int.parse(_slotNumberController.text),
              active: true,
            );

            await MasterDataService.instance.updateTimeSlot(timeSlot);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text("Update"),
        ),
      ],
    );
  }
}
