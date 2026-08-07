import 'package:flutter/material.dart';

import '../screens/timetable_import_screen.dart';

/// Mobile and desktop: open the real importer.
Future<void> openTimetableImport(BuildContext context) {
  return Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const TimetableImportScreen()),
  );
}

const bool canImportFromImage = true;
