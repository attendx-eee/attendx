import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../services/master_data_service.dart';

class EditRoomDialog extends StatefulWidget {
  final RoomModel room;

  const EditRoomDialog({
    super.key,
    required this.room,
  });

  @override
  State<EditRoomDialog> createState() => _EditRoomDialogState();
}

class _EditRoomDialogState extends State<EditRoomDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _roomNumberController;
  late TextEditingController _buildingController;
  late TextEditingController _capacityController;

  late String _selectedType;
  final List<String> roomTypes = ["Classroom", "Lab", "Auditorium", "Seminar Hall"];

  @override
  void initState() {
    super.initState();
    _roomNumberController = TextEditingController(text: widget.room.roomNumber);
    _buildingController = TextEditingController(text: widget.room.building);
    _capacityController = TextEditingController(text: widget.room.capacity.toString());
    _selectedType = widget.room.type;
  }

  @override
  void dispose() {
    _roomNumberController.dispose();
    _buildingController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        "Edit Room",
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
                controller: _roomNumberController,
                decoration: const InputDecoration(
                  labelText: "Room Number",
                  hintText: "e.g., EE-301",
                  prefixIcon: Icon(Icons.door_front_door),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Enter room number";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _buildingController,
                decoration: const InputDecoration(
                  labelText: "Building",
                  hintText: "e.g., Engineering Block A",
                  prefixIcon: Icon(Icons.apartment),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Enter building name";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _capacityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Capacity",
                  hintText: "e.g., 60",
                  prefixIcon: Icon(Icons.people),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Enter capacity";
                  }
                  if (int.tryParse(value) == null) {
                    return "Enter a valid number";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: "Room Type",
                  prefixIcon: Icon(Icons.category),
                  border: OutlineInputBorder(),
                ),
                items: roomTypes
                    .map((type) => DropdownMenuItem(
                          value: type,
                          child: Text(type),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedType = value ?? "Classroom");
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

            final room = RoomModel(
              id: widget.room.id,
              roomNumber: _roomNumberController.text.trim(),
              building: _buildingController.text.trim(),
              capacity: int.parse(_capacityController.text),
              type: _selectedType,
              active: true,
            );

            await MasterDataService.instance.updateRoom(room);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text("Update"),
        ),
      ],
    );
  }
}
