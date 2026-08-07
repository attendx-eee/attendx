// Platform-aware entry point for the image importer.
//
// The importer needs `image_picker`, `dart:io` and an ML Kit recogniser,
// none of which compile for the web. Importing the screen directly from
// a shared admin screen would pull all three into the console's build
// and break it — as it did, until this indirection was added.
//
// Import THIS file; never the screen. Same pattern, and same reason, as
// services/face_embedding_service.dart.
export 'import_entry_stub.dart'
    if (dart.library.io) 'import_entry_native.dart';
