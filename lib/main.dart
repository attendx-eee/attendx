import 'package:attendx/screens/splash_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'services/face_embedding_service.dart';
import 'package:flutter_litert/flutter_litert.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeWeb();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint("Firebase Connected Successfully");

  // Face recognition runs on-device (Android/iOS). On web the TFLite
  // model isn't available — the app still boots, face features are
  // hidden there.
  if (!kIsWeb) {
    try {
      await FaceEmbeddingService.instance.initialize();
    } catch (e) {
      debugPrint("Face model unavailable: $e");
    }
  }

  runApp(const AttendXApp());
}

class AttendXApp extends StatelessWidget {
  const AttendXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AttendX',
      debugShowCheckedModeBanner: false,
      // Brand theme derived from the AttendX logo (blue -> teal).
      theme: AppTheme.light,
      home: const SplashScreen(),
    );
  }
}
