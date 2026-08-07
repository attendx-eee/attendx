import 'package:flutter/material.dart';

/// Web build: there is nothing to open.
///
/// The importer needs a camera and the local filesystem, neither of
/// which the admin console has. More importantly, *importing* this
/// screen on web would drag `image_picker` and `dart:io` into a build
/// that can't compile them — which is why the entry point is behind a
/// conditional export rather than a `kIsWeb` check inside the button.
/// A runtime check would be too late; the import statement is what
/// breaks the build.
Future<void> openTimetableImport(BuildContext context) async {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Reading a timetable from an image needs the mobile '
          'app — the console has no camera.'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Whether the current build can offer the importer at all.
const bool canImportFromImage = false;
