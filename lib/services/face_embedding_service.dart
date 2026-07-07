// Platform-aware face embedding service.
//
// tflite_flutter depends on dart:ffi, which does not exist on the web —
// importing it there breaks compilation entirely. This facade exports
// the real TFLite implementation on platforms with FFI (Android, iOS,
// desktop) and a no-op stub on the web. Import THIS file everywhere;
// never import the implementation files directly.
export 'face_embedding/face_embedding_stub.dart'
    if (dart.library.ffi) 'face_embedding/face_embedding_native.dart';
