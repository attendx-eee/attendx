import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:async';

import '../models/face_enrollment_imports.dart';

class FaceEnrollmentScreen extends StatefulWidget {
  const FaceEnrollmentScreen({super.key});

  @override
  State<FaceEnrollmentScreen> createState() => _FaceEnrollmentScreenState();
}

class _FaceEnrollmentScreenState extends State<FaceEnrollmentScreen> {
  final FirestoreService firestoreService = FirestoreService();
  final FaceDetectionService faceDetectionService = FaceDetectionService();
  final FaceCropService faceCropService = FaceCropService();
  final FaceEmbeddingService faceEmbeddingService = FaceEmbeddingService();
  final SharpnessService sharpnessService = SharpnessService();
  final BrightnessService brightnessService = const BrightnessService();
  final ContrastService contrastService = const ContrastService();
  final OccupancyService occupancyService = const OccupancyService();
  final FaceCenteringService faceCenteringService = const FaceCenteringService();
  final PoseService poseService = const PoseService();
  final HeadStabilityService headStabilityService = const HeadStabilityService();
  final EmbeddingFusionService embeddingFusionService = const EmbeddingFusionService();
  final EyeDistanceService eyeDistanceService = const EyeDistanceService();
  final FaceAlignmentService faceAlignmentService = const FaceAlignmentService();
  final FaceMatchService faceMatchService = FaceMatchService();
  final CalibrationService calibrationService=CalibrationService();
  final BlinkService blinkService = BlinkService();
  final EnrollmentGuideStyleService guideStyleService = const EnrollmentGuideStyleService();

  final Map<EnrollmentStage,List<List<double>>> _stageEmbeddings = {
    EnrollmentStage.front: [],
    EnrollmentStage.left: [],
    EnrollmentStage.right: [],
    EnrollmentStage.up: [],
    EnrollmentStage.down: [],
  };

  EnrollmentStage _currentStage = EnrollmentStage.front;

  EnrollmentFlowState _flowState = EnrollmentFlowState.warmingUp;

  final Map<EnrollmentStage, int> _poseCounts = {
        EnrollmentStage.front: 0,
        EnrollmentStage.left: 0,
        EnrollmentStage.right: 0,
        EnrollmentStage.up: 0,
        EnrollmentStage.down: 0,
      };

  final Map<EnrollmentStage, int> _requiredCounts = {
    EnrollmentStage.front: 6,
    EnrollmentStage.left: 3,
    EnrollmentStage.right: 3,
    EnrollmentStage.up: 2,
    EnrollmentStage.down: 2,
  };


  final List<List<double>> _capturedEmbeddings = [];

  double? _previousFaceCenterX;
  double? _previousFaceCenterY;

  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isProcessingFrame = false;
  bool _isSaving = false;
  bool _isWarmUpComplete = false;
  bool _isLivenessVerified = false;
  
  // Advanced State Management Flags
  bool _isLowLightPaused = false;
  bool _hasEnrollmentFailed = false;

  Rect? _detectedFaceRect;
  

Rect _getGuideRect(Size screenSize) {
  final bool isPortrait = screenSize.height > screenSize.width;
  final double widthRatio = isPortrait ? 0.74 : 0.60;
  final double heightRatio = isPortrait ? 0.46 : 0.60;
  final double verticalFactor = isPortrait ? 0.45 : 0.50;

  return Rect.fromCenter(
    center: Offset(screenSize.width / 2, screenSize.height * verticalFactor),
    width: screenSize.width * widthRatio,
    height: screenSize.height * heightRatio,
  );
}



  bool _isCurrentStageSatisfied(
  FacePose detectedPose,
  Face face,
) {

  switch (_currentStage) {

    case EnrollmentStage.front:
      return detectedPose == FacePose.front;

    case EnrollmentStage.left:
      return detectedPose == FacePose.left;

    case EnrollmentStage.right:
      return detectedPose == FacePose.right;

    case EnrollmentStage.up:
      return detectedPose == FacePose.up;

    case EnrollmentStage.down:
      return detectedPose == FacePose.down;

    case EnrollmentStage.completed:
      return false;
  }
}
  
  String _statusMessage = "Initializing biometric scanner...";
  List<double> targetEmbedding = [];

  @override
  void initState() {
    super.initState();
    _initializeServicesAndCamera();
  }


Future<CalibrationFrame?> _captureSingleFrame() async {
    try {
      final completer = Completer<CameraImage>();
      _cameraController?.startImageStream((CameraImage image) {
        if (!completer.isCompleted) {
          completer.complete(image);
        }
        _cameraController?.stopImageStream();
      });

      final cameraImage = await completer.future;
      final inputImage = _convertCameraImageToInputImage(cameraImage);
      if (inputImage == null) return null;

      final faces = await faceDetectionService.detector.processImage(inputImage);
      if (faces.isEmpty) return null;

      final face = faces.first;
      final imageFile = await _convertStreamFrameToFile(cameraImage);
      if (imageFile == null) return null;

      final croppedFace = await faceCropService.cropFace(imageFile, face);

      return CalibrationFrame(file: imageFile, face: face, croppedFace: croppedFace);
    } catch (e) {
      debugPrint("Calibration frame capture error: $e");
      return null;
    }
  }


  Future<void> _initializeServicesAndCamera() async {
    try {
      await faceEmbeddingService.initialize();

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _updateStatus("No hardware imaging sensors detected.");
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

      Future.delayed(const Duration(milliseconds: 2500), () async {
        if (mounted) {
          setState(() {
            _isWarmUpComplete = true;
            _flowState = EnrollmentFlowState.waitingForFace;
            _statusMessage = "Position your face inside the guide";
          });

          // 🔑 Run calibration once warm-up is complete
         await calibrationService.calibrateSharpnessThreshold(() async {
            final scores = <double>[];
            for (int i = 0; i < 10; i++) {
              final frame = await _captureSingleFrame();
              if (frame?.croppedFace != null) {
                final score = sharpnessService.calculateLaplacianVariance(frame!.croppedFace!);
                scores.add(score);
              }
            }
            return scores;
          });

        }
      });

      _startFrameSubscription();
    } catch (e) {
      _updateStatus("Failed to safely bridge camera subsystem.");
    }
  }

  void _startFrameSubscription() {
    _cameraController?.startImageStream((CameraImage image) {
      if (!_isProcessingFrame && !_isSaving && _isWarmUpComplete && !_isLowLightPaused && !_hasEnrollmentFailed) {
        _processVideoFrame(image);
      }
    });
  }

  Future<void> _processVideoFrame(CameraImage cameraImage) async {
    if (_isProcessingFrame || _isSaving || _isLowLightPaused || _hasEnrollmentFailed) return;
    _isProcessingFrame = true;

    try {

      final bool isDark = _evaluateAmbientLight(cameraImage);
      if (isDark) {
        _handleLowLightPause();
        return;
      }

      final inputImage = _convertCameraImageToInputImage(cameraImage);
      if (inputImage == null) return;

      final faces = await faceDetectionService.detector.processImage(inputImage);

      if (faces.isEmpty) {
        _setFlowState(
          EnrollmentFlowState.waitingForFace,
          "Position your face inside the guide",
        );
        return;
      }

      if (faces.length > 1) {
        _setFlowState(
          EnrollmentFlowState.waitingForFace,
          "Only one face should be visible",
        );
        return;
      }

      final face = faces.first;
      final detectedPose = poseService.detect(face);

      // Guard: the frame arrived asynchronously — bail out if the
      // widget was disposed while the detector was working.
      if (!mounted) return;

      // Compute preview + transformed rect
      final previewSize = MediaQuery.of(context).size;
      final imageSize = Size(cameraImage.width.toDouble(), cameraImage.height.toDouble());
      final transformedFaceRect = const CameraCoordinateTransformer().transformRect(
        rect: face.boundingBox,
        imageSize: imageSize,
        previewSize: previewSize,
        isFrontCamera: _cameraController!.description.lensDirection == CameraLensDirection.front,
      );


        // Now compute centering and alignment
      final guideRect = _getGuideRect(previewSize);

      final centerResult = faceCenteringService.evaluate(
        faceRect: transformedFaceRect,
        guideRect: guideRect,
        screenSize: previewSize,
      );
      

      final eyeResult = eyeDistanceService.evaluate(face, cameraImage.width.toDouble());
      final poseResult = poseService.evaluate(face);

      final alignmentResult = faceAlignmentService.evaluate(
        occupancyPassed: true,
        centeringPassed: centerResult.passed,
        posePassed: poseResult.accepted,
        eyeDistancePassed: eyeResult.passed,
      );

      
      

      if (_currentStage == EnrollmentStage.front) {
        // ---------- Liveness not completed ----------
        if (!_isLivenessVerified) {
          if (centerResult.passed && alignmentResult.passed) {
            _setFlowState(
              EnrollmentFlowState.waitingForBlink,
              "Blink once to continue",
            );

            if (blinkService.checkBlink(face)) {
              _setFlowState(
                EnrollmentFlowState.waitingForStability,
                "Blink detected. Hold still...",
              );

              _isLivenessVerified = true;

              _setFlowState(
                EnrollmentFlowState.livenessVerified,
                "Liveness Verified!",
              );
            }
          } else {
            _setFlowState(
              EnrollmentFlowState.aligningFace,
              "Center your face",
            );
          }

          return;
        }

        // ---------- Blink completed ----------
        if (centerResult.passed &&
            alignmentResult.passed &&
            headStabilityService.isStable(
              headStabilityService.calculateMovement(
                previousX: _previousFaceCenterX ?? face.boundingBox.center.dx,
                previousY: _previousFaceCenterY ?? face.boundingBox.center.dy,
                currentX: face.boundingBox.center.dx,
                currentY: face.boundingBox.center.dy,
              ),
              20,
            )) {

          _setFlowState(
            EnrollmentFlowState.capturing,
            "Capturing...",
          );

          _showCurrentInstruction();

          await Future.delayed(const Duration(milliseconds: 350));

          await _handleFrameCapture(cameraImage, face);
        } else {
          _setFlowState(
            EnrollmentFlowState.waitingForStability,
            "Hold still...",
          );
          _showCurrentInstruction();
        }

        return;
      }

      // ---------- Remaining poses ----------
      if (_isCurrentStageSatisfied(detectedPose, face)) {
        if (centerResult.passed && alignmentResult.passed) {

          _setFlowState(
            EnrollmentFlowState.capturing,
            "Capturing...",
          );

          await _handleFrameCapture(cameraImage, face);
        } else {
          _setFlowState(
            EnrollmentFlowState.aligningFace,
            "Center your face before capture",
          );
        }
      } else {
        _showCurrentInstruction();
      }


      if (mounted) {
        setState(() {
          _detectedFaceRect = transformedFaceRect;
        });
      }


      final occupancy = occupancyService.calculateOccupancy(
        face: face,
        frameWidth: cameraImage.width.toDouble(),
        frameHeight: cameraImage.height.toDouble(),
      );

      if (!occupancyService.isOccupancyValid(
        occupancy,
        QualityThresholds.minFaceOccupancy,
        QualityThresholds.maxFaceOccupancy,
      )) {

        _setFlowState(
          EnrollmentFlowState.aligningFace,
          occupancy < QualityThresholds.minFaceOccupancy
              ? "Move closer"
              : "Move farther",
        );

        return;
      }

          } catch (e) {
            debugPrint("Stream frame processing error: $e");
          } finally {
            _isProcessingFrame = false;
          }
        }





  bool _evaluateAmbientLight(CameraImage image) {
    try {
      final Uint8List yPlaneBytes = image.planes.first.bytes;
      int totalLuminance = 0;
      final int step = (yPlaneBytes.length / 400).round().clamp(1, yPlaneBytes.length);
      int sampleCount = 0;
      
      for (int i = 0; i < yPlaneBytes.length; i += step) {
        totalLuminance += yPlaneBytes[i];
        sampleCount++;
      }
      return (totalLuminance / sampleCount) < 60.0;
    } catch (_) {
      return false;
    }
  }

  void _handleLowLightPause() async {
    if (_isLowLightPaused) return;
    setState(() {
      _isLowLightPaused = true;
      _setFlowState(
        EnrollmentFlowState.lowLight,
        "Move to a brighter area",
      );
    });
    await _cameraController?.stopImageStream();
    _pollAmbientLightForRecovery();
  }

  Future<void> _pollAmbientLightForRecovery() async {
    while (_isLowLightPaused && mounted) {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted || _cameraController == null || !_cameraController!.value.isInitialized) return;

      try {
        _cameraController?.startImageStream((CameraImage image) {
          final isDark = _evaluateAmbientLight(image);
          _cameraController?.stopImageStream();
          
          if (!isDark && mounted) {
            setState(() {
              _isLowLightPaused = false;
              _statusMessage = "Lighting normalized. Aligning tracker matrix...";
            });
            _startFrameSubscription();
          }
        });
      } catch (e) {
        debugPrint("Luminance polling module faulted: $e");
      }
    }
  }

  void _setFlowState(
    EnrollmentFlowState state,
    String message,
  ) {
    if (!mounted) return;

    if (_flowState == state &&
        _statusMessage == message) {
      return;
    }

    setState(() {
      _flowState = state;
      _statusMessage = message;
    });
  }

  Future<void> _handleFrameCapture(CameraImage streamImage, Face detectedFace) async {
    setState(() {
      _isSaving = true;
    });

    _setFlowState(
      EnrollmentFlowState.processing,
      "Processing face...",
    );

    try {
      await _cameraController?.stopImageStream();

      File? imageFile = await _convertStreamFrameToFile(streamImage);
      if (imageFile == null) throw Exception("Isolate conversion target output failed.");

      final croppedFace = await faceCropService.cropFace(imageFile, detectedFace);
      if (croppedFace == null) {
        _signalEnrollmentFailure("Isolation crop mapping broke. Retry standard posture.");
        return;
      }

      // Use improved sharpness evaluation      

      final deviceModel = await getDeviceModel(); // use platform info
      final threshold = calibrationService.calibratedSharpnessThreshold ??
          DeviceQualityThresholds.getSharpnessThreshold(deviceModel);

      final isSharp = sharpnessService.isSharpEnough(croppedFace, dynamicThreshold: threshold);
      if (!isSharp) {
        _signalEnrollmentFailure("Camera struggling to capture a clear face. Please hold steady or adjust lighting.");
        return;
      }





      final brightness = brightnessService.calculateBrightness(croppedFace);

      debugPrint('Brightness Score: $brightness',);

      if (brightness < QualityThresholds.minBrightness || brightness > QualityThresholds.maxBrightness) {

        _signalEnrollmentFailure(
          'Face lighting not suitable.',
        );

        return;
      }

      final contrast = contrastService.calculateContrast(croppedFace);

      debugPrint('Contrast Score: $contrast',);

      if (contrast < QualityThresholds.minContrast) {

        _signalEnrollmentFailure(
          'Low contrast face image.',
        );

        return;
      }

      final rawEmbedding = faceEmbeddingService.generateEmbedding(croppedFace);
      final normalized = faceEmbeddingService.normalizeEmbedding(rawEmbedding);

      final currentStageEmbeddings = _stageEmbeddings[_currentStage]!;

      for (final embedding in currentStageEmbeddings) {
        final similarity = faceMatchService.cosineSimilarity(
          normalized,
          embedding,
        );

        if (similarity > 0.995) {
          if (mounted) {
            setState(() {
              _isSaving = false;
            });
          }

          await Future.delayed(
            const Duration(milliseconds: 300),
          );

          _startFrameSubscription();
          return;
        }
      }

      _capturedEmbeddings.add(normalized);
      _stageEmbeddings[_currentStage]!.add(normalized);

      _poseCounts[_currentStage] =
          _poseCounts[_currentStage]! + 1;

      _updateStatus(
        "${_currentStage.name} "
        "${_poseCounts[_currentStage]}/${_requiredCounts[_currentStage]}",
      );

      if (_poseCounts[_currentStage]! >= _requiredCounts[_currentStage]!) {
        _advanceStage();
        _showCurrentInstruction();
      } else {
        _updateStatus(
          "${_currentStage.name} "
          "${_poseCounts[_currentStage]}/${_requiredCounts[_currentStage]}",
        );
      }

      if (_currentStage == EnrollmentStage.completed) {

        final fusedEmbedding =
            embeddingFusionService.average(
                _capturedEmbeddings);

        targetEmbedding =
            faceEmbeddingService
                .normalizeEmbedding(
                    fusedEmbedding);

        await _uploadEmbeddingsToFirebase();

        return;
      }

      _isSaving = false;

      if (_currentStage != EnrollmentStage.completed) {
        _showCurrentInstruction();
      }

      await Future.delayed(
        const Duration(milliseconds: 500),
      );

      _startFrameSubscription();

      
    } catch (e) {
      _signalEnrollmentFailure("Pipeline processing failure: $e");
    }
  }

  

  void _signalEnrollmentFailure(String msg) {
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _hasEnrollmentFailed = true;
      _setFlowState(
          EnrollmentFlowState.failed,
          msg,
      );
    });
  }

  void _resetForManualRetry() {
    _capturedEmbeddings.clear();
    _stageEmbeddings.forEach((stage, embeddings) {
      embeddings.clear();
    });
    _poseCounts.updateAll((key, value) => 0);
    _currentStage = EnrollmentStage.front;
    _flowState = EnrollmentFlowState.warmingUp;
    _resetBlinkState();
    setState(() {
      _isSaving = false;
      _hasEnrollmentFailed = false;
      _isLivenessVerified = false;
      _isLowLightPaused = false;
      _flowState = EnrollmentFlowState.waitingForFace;
      _statusMessage = "Position your face inside the Frame";
    });
    _startFrameSubscription();
  }

  void _showCurrentInstruction() {

    switch (_currentStage) {

      case EnrollmentStage.front:
        _updateStatus(
          "Look straight",
        );
        break;

      case EnrollmentStage.left:
        _setFlowState(
            EnrollmentFlowState.waitingForPose,
            "Turn head left slightly",
        );
        break;

      case EnrollmentStage.right:
        _setFlowState(
            EnrollmentFlowState.waitingForPose,
            "Turn head right slightly",
        );
        break;

      case EnrollmentStage.up:
        _setFlowState(
            EnrollmentFlowState.waitingForPose,
            "Look slightly up",
        );
        break;

      case EnrollmentStage.down:
        _setFlowState(
            EnrollmentFlowState.waitingForPose,
            "Look slightly down",
        );
        break;


      case EnrollmentStage.completed:
        break;
    }
  }

  void _advanceStage() {

  switch (_currentStage) {

    case EnrollmentStage.front:
      _currentStage = EnrollmentStage.left;
      _showCurrentInstruction();
      break;

    case EnrollmentStage.left:
      _currentStage = EnrollmentStage.right;
      _showCurrentInstruction();
      break;

    case EnrollmentStage.right:
      _currentStage = EnrollmentStage.up;
      _showCurrentInstruction();
      break;

    case EnrollmentStage.up:
      _currentStage = EnrollmentStage.down;
      _showCurrentInstruction();
      break;

    case EnrollmentStage.down:
      _currentStage = EnrollmentStage.completed;
      _showCurrentInstruction();
      break;


    case EnrollmentStage.completed:
      break;
  }
}



  Future<File?> _convertStreamFrameToFile(CameraImage image) async {
    try {
      final path = '${Directory.systemTemp.path}/enroll_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      // Map out all layout configurations explicitly to prevent thread data omissions
      final List<Map<String, dynamic>> planeData = image.planes.map((p) => {
        'bytes': p.bytes,
        'bytesPerRow': p.bytesPerRow,
        'bytesPerPixel': p.bytesPerPixel,
      }).toList();

      final jpegBytes = await compute(encodeImageToJpegIsolate, {
        'planes': planeData,
        'width': image.width,
        'height': image.height,
        'format': image.format.group,
      });

      if (jpegBytes == null) return null;
      final file = File(path);
      await file.writeAsBytes(jpegBytes);
      return file;
    } catch (_) {
      return null;
    }
  }

  

Future<void> _uploadEmbeddingsToFirebase() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    _showSnackbar("User instance token dead. Re-authenticate configuration context.", Colors.red);
    return;
  }

  try {
    // Build stage-wise embeddings map (excluding smile)
    final Map<String, List<double>> fusedEmbeddings = {
      "front": embeddingFusionService.average(
          _stageEmbeddings[EnrollmentStage.front]!),

      "left": embeddingFusionService.average(
          _stageEmbeddings[EnrollmentStage.left]!),

      "right": embeddingFusionService.average(
          _stageEmbeddings[EnrollmentStage.right]!),

      "up": embeddingFusionService.average(
          _stageEmbeddings[EnrollmentStage.up]!),

      "down": embeddingFusionService.average(
          _stageEmbeddings[EnrollmentStage.down]!),
    };

    _setFlowState(
      EnrollmentFlowState.uploading,
      "Saving enrollment...",
    );    

    // Call Firestore service with name + registration number
    await firestoreService.updateFaceEmbeddings(
      user.uid,
      fusedEmbeddings,
    );

    _showSnackbar("All stage embeddings stored securely!", Colors.green);
    if (mounted) Navigator.pop(context);

    _setFlowState(
      EnrollmentFlowState.completed,
      "Enrollment completed",
    );

  } catch (e) {
    debugPrint("========== FIRESTORE ERROR ==========");
    debugPrint(e.toString());
    _showSnackbar("Cloud Database storage sync rejected.", Colors.red);
    _setFlowState(
      EnrollmentFlowState.failed,
      "Enrollment failed",
    );
    _resetForManualRetry();
  }
}



  void _resetBlinkState() {
    blinkService.resetBlinkState();
  }

  void _updateStatus(String msg) {
    if (_statusMessage != msg && mounted) {
      setState(() {
        _statusMessage = msg;
      });
    }
  }

  void _showSnackbar(String text, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: bg),
    );
  }

  InputImage? _convertCameraImageToInputImage(CameraImage image) {
    try {
      final camera = _cameraController!.description;
      final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation0deg;
      final format = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;

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
      return InputImage.fromBytes(bytes: allBytes.done().buffer.asUint8List(), metadata: metadata);
    } catch (e) {
      return null;
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final style = guideStyleService.getStyle(_flowState);
    


    return Scaffold(
      appBar: AppBar(
        title: const Text("Biometric Asset Enrollment"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: !_isCameraInitialized
          ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
          : Stack(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: CameraPreview(_cameraController!),
                ),
                if (!_isWarmUpComplete)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: FaceDebugPainter(
                          faceRect: _detectedFaceRect,
                          guideRect: _getGuideRect(MediaQuery.of(context).size),
                          borderColor: style.borderColor,
                        ),
                      ),
                    ),
                  ),
                if (_isWarmUpComplete)
                  IgnorePointer(
                    child: Stack(
                      children: [
                        ColorFiltered(
                          colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.7), BlendMode.srcOut),
                          child: Stack(
                            children: [
                              Container(color: Colors.transparent),
                              Align(
                                alignment: const Alignment(0, -0.2),
                                child: Container(
                                  width: size.width * 0.74,
                                  height: size.height * 0.46,
                                  decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(28)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Align(
                          alignment: const Alignment(0, -0.2),
                          child: Container(
                            width: size.width * 0.74,
                            height: size.height * 0.46,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: style.borderColor,
                                width: 4.0,
                              ),
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Positioned(
                  bottom: 40,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              style.icon,
                              color: style.iconColor,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _statusMessage,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        if (_isSaving) ...[
                          const SizedBox(height: 16),
                          const LinearProgressIndicator(color: Colors.blueAccent, backgroundColor: Colors.white24)
                        ],
                        if (_hasEnrollmentFailed) ...[
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _resetForManualRetry,
                            icon: const Icon(Icons.refresh_sharp, size: 18),
                            label: const Text("Enroll Again", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 45),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                          )
                        ]
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
