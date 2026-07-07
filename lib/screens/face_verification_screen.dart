import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../services/adaptive_face_service.dart';
import '../services/face_detection_service.dart';
import '../services/face_crop_service.dart';
import '../services/face_embedding_service.dart';
import '../services/firestore_service.dart';

class FaceVerificationScreen extends StatefulWidget {
  const FaceVerificationScreen({super.key, this.verifyAcrossUsers = false});

  final bool verifyAcrossUsers;

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen> {
  final FaceDetectionService faceDetectionService = FaceDetectionService();
  final FaceCropService faceCropService = FaceCropService();
  final FaceEmbeddingService faceEmbeddingService = FaceEmbeddingService();
  final AdaptiveFaceService adaptiveFaceService = AdaptiveFaceService.instance;
  final FirestoreService firestoreService = FirestoreService();

  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isProcessingFrame = false;
  bool _isVerifying = false;
  bool _isWarmUpComplete = false;
  bool _isFaceAlignedValidly = false;
  bool _hasVerificationFailed = false;
  bool _isLowLightPaused = false;

  // Liveness System State Flags
  bool _livenessVerified = false;
  bool _hasSeenEyesOpen = false;
  bool _hasSeenEyesClosed = false;

  String _statusMessage = "Initializing secure scanner...";
  double bestScore = 0.0;
  bool matched = false;
  bool _agingProfile = false;
  List<FaceCandidate> _candidateProfiles = [];

  @override
  void initState() {
    super.initState();
    _prepareVerificationDataAndCamera();
  }

  /// No enrollment data — leave immediately (never start the camera or
  /// sit on a spinner). The caller falls back to credential login.
  void _exitNoEnrollmentData() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pop(context, widget.verifyAcrossUsers ? null : false);
    });
  }

  Future<void> _prepareVerificationDataAndCamera() async {
    try {
      await faceEmbeddingService.initialize();

      if (widget.verifyAcrossUsers) {
        final snapshot = await firestoreService.getAllFaceEnrollments();
        if (!mounted) return;

        _candidateProfiles = snapshot.docs
            .where((doc) => doc.data()['embeddings'] is Map)
            .map((doc) => FaceCandidate.fromDoc(doc.id, doc.data()))
            .toList();

        if (_candidateProfiles.isEmpty) {
          _exitNoEnrollmentData();
          return;
        }
      } else {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          _exitNoEnrollmentData();
          return;
        }

        final doc = await firestoreService.getStageEmbeddings(user.uid);
        if (!mounted) return;

        if (!doc.exists || doc.data() == null) {
          _exitNoEnrollmentData();
          return;
        }

        final data = doc.data()!;
        final storedEmbeddings = data['embeddings'] as Map<String, dynamic>?;

        if (storedEmbeddings == null || !storedEmbeddings.containsKey('front')) {
          _exitNoEnrollmentData();
          return;
        }

        _agingProfile = AdaptiveFaceService.isAgingProfile(data);
        _candidateProfiles = [FaceCandidate.fromDoc(user.uid, data)];
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _updateStatus("No camera sensors found.");
        return;
      }

      final frontCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
      });

      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _isWarmUpComplete = true;
            _statusMessage = "Position face in frame & blink to verify";
          });
        }
      });

      _startFrameSubscription();
    } catch (e) {
      _updateStatus("Initialization failure.");
    }
  }

  void _startFrameSubscription() {
    _cameraController?.startImageStream((CameraImage image) {
      if (!_isProcessingFrame &&
          !_isVerifying &&
          _isWarmUpComplete &&
          !_hasVerificationFailed &&
          !_isLowLightPaused &&
          !_livenessVerified) {
        _processVideoFrame(image);
      }
    });
  }

  Future<void> _processVideoFrame(CameraImage cameraImage) async {
    if (_isProcessingFrame ||
        _isVerifying ||
        _hasVerificationFailed ||
        _isLowLightPaused ||
        _livenessVerified) {
      return;
    }
    _isProcessingFrame = true;

    try {
      final isEnvironmentDark = _evaluateAmbientLight(cameraImage);
      if (isEnvironmentDark) {
        if (!_isLowLightPaused) {
          _setLowLightState(true, "Low light environment detected");
          await _cameraController?.stopImageStream();
          _pollAmbientLightForRecovery();
        }
        return;
      }

      final inputImage = _convertCameraImageToInputImage(cameraImage);
      if (inputImage == null) return;

      final faces = await faceDetectionService.detector.processImage(inputImage);

      if (faces.length != 1) {
        _setFaceAlignment(false,
            faces.isEmpty ? "Frame your face completely" : "Multiple faces detected");
        _resetBlinkState();
        return;
      }

      final face = faces.first;

      if (face.headEulerAngleY!.abs() > 10 || face.headEulerAngleZ!.abs() > 10) {
        _setFaceAlignment(false, "Look directly at the screen");
        _resetBlinkState();
        return;
      }

      _setFaceAlignment(true, "Steady... Blink eyes naturally");

      double leftEyeOpenProb = face.leftEyeOpenProbability ?? 1.0;
      double rightEyeOpenProb = face.rightEyeOpenProbability ?? 1.0;

      if (leftEyeOpenProb > 0.75 && rightEyeOpenProb > 0.75) {
        _hasSeenEyesOpen = true;
      }

      if (_hasSeenEyesOpen && leftEyeOpenProb < 0.25 && rightEyeOpenProb < 0.25) {
        _hasSeenEyesClosed = true;
      }

      if (_hasSeenEyesClosed && leftEyeOpenProb > 0.75 && rightEyeOpenProb > 0.75) {
        _livenessVerified = true;
        _updateStatus("Liveness verified. Validating...");
        await _handleAutoVerification(cameraImage, face);
      }
    } catch (e) {
      debugPrint("Stream error: $e");
    } finally {
      _isProcessingFrame = false;
    }
  }

  bool _evaluateAmbientLight(CameraImage image) {
    try {
      final Uint8List yPlaneBytes = image.planes.first.bytes;
      int totalLuminance = 0;
      final int step =
          (yPlaneBytes.length / 400).round().clamp(1, yPlaneBytes.length);
      int sampleCount = 0;

      for (int i = 0; i < yPlaneBytes.length; i += step) {
        totalLuminance += yPlaneBytes[i];
        sampleCount++;
      }
      return (totalLuminance / sampleCount) < 55.0;
    } catch (_) {
      return false;
    }
  }

  Future<void> _pollAmbientLightForRecovery() async {
    while (_isLowLightPaused && mounted) {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted ||
          _cameraController == null ||
          !_cameraController!.value.isInitialized) {
        return;
      }

      try {
        _cameraController?.startImageStream((CameraImage image) {
          final isDark = _evaluateAmbientLight(image);
          _cameraController?.stopImageStream();

          if (!isDark && mounted) {
            _setLowLightState(false, "Position face in frame & blink");
            _startFrameSubscription();
          }
        });
      } catch (e) {
        debugPrint("Ambient recovery tracking error: $e");
      }
    }
  }

  void _updateStatus(String msg) {
    if (!mounted) return;
    if (_statusMessage != msg) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _statusMessage = msg);
      });
    }
  }

  void _setFaceAlignment(bool isValid, String status) {
    if (!mounted) return;
    if (_isFaceAlignedValidly != isValid || _statusMessage != status) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isFaceAlignedValidly = isValid;
            _statusMessage = status;
          });
        }
      });
    }
  }

  void _setLowLightState(bool isPaused, String status) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isLowLightPaused = isPaused;
          if (isPaused) _isFaceAlignedValidly = false;
          _statusMessage = status;
        });
      }
    });
  }

  Future<void> _handleAutoVerification(
      CameraImage targetFrame, Face detectedFace) async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _isVerifying = true);
    });

    try {
      await _cameraController?.stopImageStream();

      File? imageFile = await _convertStreamFrameToFile(targetFrame);
      if (imageFile == null) throw Exception("Frame parsing error.");

      final croppedFace = await faceCropService.cropFace(imageFile, detectedFace);
      if (croppedFace == null) {
        _updateStatus("Isolation failure. Re-aligning...");
        _resetForManualRetry();
        return;
      }

      final Uint8List faceBytes = Uint8List.fromList(img.encodeJpg(croppedFace));

      final bool isBlurred = await compute(_verifyImageSharpnessIsolate, faceBytes);
      if (isBlurred) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _hasVerificationFailed = true;
              _isVerifying = false;
              _statusMessage = "Image blurred. Please hold steady.";
            });
          }
        });
        return;
      }

      final rawEmbedding = faceEmbeddingService.generateEmbedding(croppedFace);
      final currentEmbedding = faceEmbeddingService.normalizeEmbedding(rawEmbedding);

      if (currentEmbedding.isEmpty) throw Exception("Mapping error.");

      // Centroid prefilter + pose-level scoring + runner-up margin check.
      final result = adaptiveFaceService.identify(
        currentEmbedding,
        _candidateProfiles,
      );

      debugPrint("Best Pose : ${result.bestPose}");
      debugPrint("Best Score: ${result.bestScore}");
      debugPrint("Margin    : ${result.margin}");

      if (!mounted) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            bestScore = result.bestScore;
            matched = result.accepted;
          });

          if (result.accepted && result.uid != null) {
            final matchedUid = result.uid!;

            // Learn and grow: nudge the matched template toward today's
            // face so the profile keeps up with appearance changes.
            // Fire-and-forget — login never waits on it.
            adaptiveFaceService.learnFromMatch(
              uid: matchedUid,
              live: currentEmbedding,
              result: result,
            );

            _updateStatus(_agingProfile
                ? "Verified. Tip: re-enroll soon for sharper matching."
                : "Identity Verified Successfully");

            Future.delayed(const Duration(milliseconds: 1500), () {
              if (!mounted) return;
              // Cross-user login needs the uid; single-user flows
              // (profile / biometric update) expect a boolean.
              Navigator.pop(
                context,
                widget.verifyAcrossUsers ? matchedUid : true,
              );
            });
          } else {
            setState(() {
              _hasVerificationFailed = true;
              _isFaceAlignedValidly = false;
              _isVerifying = false;
              _statusMessage = result.bestScore >= 0.75 &&
                      result.margin < AdaptiveFaceService.identificationMargin
                  ? "Ambiguous match. Please try again in better light."
                  : "Biometric Match Mismatch. Access Denied.";
            });
          }
        }
      });
    } catch (e) {
      _updateStatus("System error. Resetting...");
      _resetForManualRetry();
    }
  }

  void _resetForManualRetry() {
    if (!mounted) return;
    _resetBlinkState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _livenessVerified = false;
          _hasVerificationFailed = false;
          _isFaceAlignedValidly = false;
          bestScore = 0.0;
          _statusMessage = "Position face in frame & blink to verify";
        });
        _startFrameSubscription();
      }
    });
  }

  void _resetBlinkState() {
    _hasSeenEyesOpen = false;
    _hasSeenEyesClosed = false;
  }

  Future<File?> _convertStreamFrameToFile(CameraImage image) async {
    try {
      final path =
          '${Directory.systemTemp.path}/verify_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Pack full plane attributes securely for the isolate calculation requirements
      final List<Map<String, dynamic>> serializedPlanes = image.planes
          .map((p) => {
                'bytes': p.bytes,
                'bytesPerRow': p.bytesPerRow,
                'bytesPerPixel': p.bytesPerPixel,
              })
          .toList();

      final List<int>? jpegBytes =
          await compute(_encodeVerificationImageToJpegIsolate, {
        'planes': serializedPlanes,
        'width': image.width,
        'height': image.height,
        'format': image.format.group,
      });

      if (jpegBytes == null) return null;
      final file = File(path);
      await file.writeAsBytes(jpegBytes);
      return file;
    } catch (e) {
      return null;
    }
  }

  InputImage? _convertCameraImageToInputImage(CameraImage image) {
    try {
      final camera = _cameraController!.description;
      final rotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
              InputImageRotation.rotation0deg;
      final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.nv21;

      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      );

      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      return InputImage.fromBytes(
          bytes: allBytes.done().buffer.asUint8List(), metadata: metadata);
    } catch (e) {
      return null;
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Color _getBrandColor() {
    if (_isLowLightPaused) return const Color(0xFFD4AF37); // Matte Academic Gold
    if (_hasVerificationFailed) return const Color(0xFFCF6679); // Premium Muted Crimson
    if (_isVerifying && matched) return const Color(0xFF00E676); // Crisp Emerald
    if (_isFaceAlignedValidly) return const Color(0xFFFFFFFF); // High-contrast Corporate White
    return const Color(0xFF1F2937); // Tailored Slate Gray
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final viewWidth = size.width * 0.70;
    final viewHeight = viewWidth * 1.30; // Premium rectangular golden ratio aesthetic

    return Scaffold(
      backgroundColor: const Color(0xFF0B111E), // Elite Navy/Black Depth Base
      appBar: AppBar(
        title: const Text("IDENTITY VERIFICATION",
            style: TextStyle(
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Color(0xFFE5E7EB))),
        centerTitle: true,
        backgroundColor: const Color(0xFF0B111E),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: !_isCameraInitialized
          ? const Center(
              child: CircularProgressIndicator(
                  color: Colors.white24, strokeWidth: 2))
          : Stack(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: CameraPreview(_cameraController!),
                ),

                if (!_isWarmUpComplete)
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                      child: Container(
                        color: const Color(0xFF0B111E).withValues(alpha: 0.85),
                        child: const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFFD4AF37), strokeWidth: 1.5),
                        ),
                      ),
                    ),
                  ),

                // Clean Rectangular Mask Overlay
                if (_isWarmUpComplete)
                  IgnorePointer(
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                          const Color(0xFF0B111E).withValues(alpha: 0.82),
                          BlendMode.srcOut),
                      child: Stack(
                        children: [
                          Container(color: Colors.transparent),
                          Align(
                            alignment: const Alignment(0, -0.2),
                            child: Container(
                              width: viewWidth,
                              height: viewHeight,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Sleek Minimalist Bounding Corner Accents
                if (_isWarmUpComplete)
                  Align(
                    alignment: const Alignment(0, -0.2),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: viewWidth,
                      height: viewHeight,
                      child: CustomPaint(
                        painter: RectangularReticlePainter(color: _getBrandColor()),
                      ),
                    ),
                  ),

                // Modern Bottom Glass Control Card
                Positioned(
                  bottom: 40,
                  left: 20,
                  right: 20,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111827).withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 1),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                _buildStatusIcon(),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    _statusMessage,
                                    style: const TextStyle(
                                      color: Color(0xFFF3F4F6),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_isVerifying) ...[
                              const SizedBox(height: 18),
                              const LinearProgressIndicator(
                                color: Color(0xFFD4AF37),
                                backgroundColor: Colors.white10,
                                minHeight: 1.5,
                              )
                            ],
                            if (_isVerifying && bestScore > 0.0) ...[
                              const SizedBox(height: 12),
                              Text(
                                "MATCH CONFIDENCE: ${(bestScore * 100).toStringAsFixed(1)}%",
                                style: TextStyle(
                                  color: matched
                                      ? const Color(0xFF00E676)
                                      : Colors.white38,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                            if (_hasVerificationFailed) ...[
                              const SizedBox(height: 16),
                              OutlinedButton(
                                onPressed: _resetForManualRetry,
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                      color:
                                          Colors.white.withValues(alpha: 0.15)),
                                  minimumSize: const Size(double.infinity, 44),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text("RETRY AUTHENTICATION",
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                        letterSpacing: 0.8)),
                              )
                            ]
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatusIcon() {
    if (_isLowLightPaused) {
      return const Icon(Icons.wb_incandescent_outlined,
          color: Color(0xFFD4AF37), size: 16);
    }
    if (_hasVerificationFailed) {
      return const Icon(Icons.error_outline_rounded,
          color: Color(0xFFCF6679), size: 16);
    }
    if (_livenessVerified) {
      return const Icon(Icons.check_circle_outline_rounded,
          color: Color(0xFF00E676), size: 16);
    }
    return const Icon(Icons.face_retouching_natural_sharp,
        color: Colors.white54, size: 16);
  }
}

// Custom Painter for Minimalist Rectangular Bracket Reticle
class RectangularReticlePainter extends CustomPainter {
  final Color color;
  RectangularReticlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    const double cornerLength = 24.0;
    final radius = const Radius.circular(16);

    final path = Path();

    // Top Left Corner
    path.moveTo(0, cornerLength);
    path.lineTo(0, radius.y);
    path.arcToPoint(Offset(radius.x, 0), radius: radius);
    path.lineTo(cornerLength, 0);

    // Top Right Corner
    path.moveTo(size.width - cornerLength, 0);
    path.lineTo(size.width - radius.x, 0);
    path.arcToPoint(Offset(size.width, radius.y), radius: radius);
    path.lineTo(size.width, cornerLength);

    // Bottom Right Corner
    path.moveTo(size.width, size.height - cornerLength);
    path.lineTo(size.width, size.height - radius.y);
    path.arcToPoint(Offset(size.width - radius.x, size.height), radius: radius);
    path.lineTo(size.width - cornerLength, size.height);

    // Bottom Left Corner
    path.moveTo(cornerLength, size.height);
    path.lineTo(radius.x, size.height);
    path.arcToPoint(Offset(0, size.height - radius.y), radius: radius);
    path.lineTo(0, size.height - cornerLength);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant RectangularReticlePainter oldDelegate) =>
      oldDelegate.color != color;
}

List<int>? _encodeVerificationImageToJpegIsolate(Map<String, dynamic> data) {
  try {
    final List<Map<String, dynamic>> planes =
        List<Map<String, dynamic>>.from(data['planes']);
    final int width = data['width'];
    final int height = data['height'];
    final ImageFormatGroup format = data['format'];

    img.Image? targetImage;

    if (format == ImageFormatGroup.bgra8888) {
      final Uint8List rgbaBytes = planes[0]['bytes'];
      targetImage = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgbaBytes.buffer,
        order: img.ChannelOrder.bgra,
      );
    } else {
      targetImage = img.Image(width: width, height: height);

      final Uint8List yPlane = planes[0]['bytes'];

      // Fallback Safety Check for Single-Plane devices running NV21
      final bool isPackedYUV = planes.length < 3;

      final Uint8List uPlane = isPackedYUV ? yPlane : planes[1]['bytes'];
      final Uint8List vPlane = isPackedYUV ? yPlane : planes[2]['bytes'];

      final int yRowStride = planes[0]['bytesPerRow'];
      final int uvRowStride = isPackedYUV ? yRowStride : planes[1]['bytesPerRow'];
      final int uvPixelStride = isPackedYUV ? 2 : (planes[1]['bytesPerPixel'] ?? 1);

      final int uvOffset = width * height;

      for (int w = 0; w < width; w++) {
        for (int h = 0; h < height; h++) {
          final int yIndex = h * yRowStride + w;

          int uIndex;
          int vIndex;

          if (isPackedYUV) {
            final int uvIndex = uvOffset + ((h >> 1) * width) + (w & ~1);
            vIndex = uvIndex;
            uIndex = uvIndex + 1;
          } else {
            final int uvIndex = (h >> 1) * uvRowStride + (w >> 1) * uvPixelStride;
            uIndex = uvIndex;
            vIndex = uvIndex;
          }

          if (yIndex >= yPlane.length ||
              uIndex >= uPlane.length ||
              vIndex >= vPlane.length) {
            continue;
          }

          final int yVal = yPlane[yIndex];
          final int uVal = uPlane[uIndex];
          final int vVal = vPlane[vIndex];

          int r = (yVal + (1.370705 * (vVal - 128))).round().clamp(0, 255);
          int g = (yVal -
                  (0.337633 * (uVal - 128)) -
                  (0.698001 * (vVal - 128)))
              .round()
              .clamp(0, 255);
          int b = (yVal + (1.732446 * (uVal - 128))).round().clamp(0, 255);

          targetImage.setPixelRgb(w, h, r, g, b);
        }
      }
    }

    return img.encodeJpg(img.copyRotate(targetImage, angle: 270));
  } catch (e) {
    debugPrint("Isolate color encoding failure: $e");
    return null;
  }
}

bool _verifyImageSharpnessIsolate(Uint8List imageBytes) {
  try {
    final img.Image? decoded = img.decodeImage(imageBytes);
    if (decoded == null) return true;

    final grayscale = img.grayscale(decoded);
    int totalPixelCount = grayscale.width * grayscale.height;
    double meanValue = 0;

    for (var pixel in grayscale) {
      meanValue += pixel.r;
    }
    meanValue /= totalPixelCount;

    double varianceSum = 0;
    for (var pixel in grayscale) {
      double diff = pixel.r - meanValue;
      varianceSum += diff * diff;
    }

    return (varianceSum / totalPixelCount) < 120.0;
  } catch (_) {
    return true;
  }
}
