import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../models/time_slot_model.dart';
import '../services/master_data_service.dart';
import '../widgets/add_time_slot_dialog.dart';
import '../widgets/confirm_and_delete.dart';
import '../widgets/edit_time_slot_dialog.dart';
import '../widgets/management_icon_avatar.dart';

class TimeSlotScreen extends StatefulWidget {
  const TimeSlotScreen({super.key});

  @override
  State<TimeSlotScreen> createState() => _TimeSlotScreenState();
}

class _TimeSlotScreenState extends State<TimeSlotScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Slot Management'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => const AddTimeSlotDialog(),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text("Add Time Slot"),
      ),
      body: StreamBuilder<List<TimeSlotModel>>(
        stream: MasterDataService.instance.getTimeSlots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }

          final timeSlots = snapshot.data ?? [];

          if (timeSlots.isEmpty) {
            return const Center(child: Text("No time slots added"));
          }

          return ListView.builder(
            // Bottom padding clears the extended FAB — otherwise the
            // last card ends up hidden behind it once the list is long
            // enough to scroll.
            padding: const EdgeInsets.fromLTRB(15, 10, 15, 100),
            itemCount: timeSlots.length,
            itemBuilder: (context, index) {
              final slot = timeSlots[index];
              return Card(
                elevation: 1,
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: ListTile(
                  leading: const ManagementIconAvatar(
                    icon: Icons.schedule_rounded,
                    color: AppColors.primary,
                  ),
                  title: Text("Slot ${slot.slotNumber}: ${slot.startTime} - ${slot.endTime}"),
                  subtitle: slot.active ? const Text("Active", style: TextStyle(color: Colors.green)) : const Text("Inactive", style: TextStyle(color: Colors.red)),
                  trailing: PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: const Text("Edit"),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => EditTimeSlotDialog(timeSlot: slot),
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
                          title: "Delete Time Slot",
                          confirmMessage: "Delete Slot ${slot.slotNumber}?",
                          checkInUse: () =>
                              MasterDataService.instance.isTimeSlotScheduled(slot),
                          inUseMessage:
                              "Slot ${slot.slotNumber} (${slot.startTime}-${slot.endTime}) "
                              "has classes scheduled against it. Remove those periods "
                              "from the timetable first, then delete this slot.",
                          onDelete: () => MasterDataService.instance
                              .deleteTimeSlot(slot.id, slot: slot),
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