import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../services/master_data_service.dart';
import '../widgets/add_room_dialog.dart';
import '../widgets/confirm_and_delete.dart';
import '../widgets/edit_room_dialog.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Room Management'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => const AddRoomDialog(),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text("Add Room"),
      ),
      body: StreamBuilder<List<RoomModel>>(
        stream: MasterDataService.instance.getRooms(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }

          final rooms = snapshot.data ?? [];

          if (rooms.isEmpty) {
            return const Center(child: Text("No rooms added"));
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            itemCount: rooms.length,
            itemBuilder: (context, index) {
              final room = rooms[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(room.roomNumber),
                  ),
                  title: Text("Room ${room.roomNumber} - ${room.type}"),
                  subtitle: Text("${room.building} | Cap: ${room.capacity}"),
                  trailing: PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: const Text("Edit"),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => EditRoomDialog(room: room),
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
                          title: "Delete Room",
                          confirmMessage: "Delete Room ${room.roomNumber}?",
                          checkInUse: () =>
                              MasterDataService.instance.isRoomScheduled(room),
                          inUseMessage:
                              "Room ${room.roomNumber} is assigned in the timetable. "
                              "Remove or reassign those periods first, then delete "
                              "this room.",
                          onDelete: () => MasterDataService.instance
                              .deleteRoom(room.id, room: room),
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
    );
  }
}