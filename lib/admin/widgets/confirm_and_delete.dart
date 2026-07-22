import 'package:flutter/material.dart';

/// Shared delete flow for every master-data screen (faculty, subjects,
/// labs, rooms, time slots): check whether the record is still used in
/// the timetable first. If it is, show a blocking "can't delete" dialog
/// explaining why — no confirm step, since deleting isn't an option yet.
/// Otherwise fall through to the normal "are you sure?" confirmation and
/// call [onDelete]. Any exception [onDelete] itself throws (e.g. a second
/// in-use check server-side) is caught and shown the same way.
Future<void> confirmAndDelete({
  required BuildContext context,
  required String title,
  required String confirmMessage,
  required Future<bool> Function() checkInUse,
  required String inUseMessage,
  required Future<void> Function() onDelete,
}) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  bool inUse;
  try {
    inUse = await checkInUse();
  } catch (e) {
    if (!context.mounted) return;
    Navigator.pop(context); // close the loading spinner
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not check timetable: $e'), backgroundColor: Colors.redAccent),
    );
    return;
  }

  if (!context.mounted) return;
  Navigator.pop(context); // close the loading spinner

  if (inUse) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
        title: const Text("Can't Delete"),
        content: Text(inUseMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
    return;
  }

  final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Text(confirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Delete", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ) ??
      false;

  if (!confirm || !context.mounted) return;

  try {
    await onDelete();
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
    );
  }
}
