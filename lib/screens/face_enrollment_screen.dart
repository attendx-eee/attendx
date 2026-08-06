import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:async';

import '../models/face_enrollment_imports.dart';
import '../services/enrollment/scan_guide.dart';
import '../services/enrollment/scan_harvester.dart';
import '../services/profile_photo_service.dart';
import '../services/quality/face_quality_score.dart';
import 'login.dart';
import 'role_router.dart';

class FaceEnrollmentScreen extends StatefulWidget {
  /// When true, this screen is a required step of registration:
  /// the back button/gesture is disabled (no skipping), and on
  /// success it replaces the whole stack with [RoleRouter] instead
  /// of just popping back to whatever screen pushed it.
  final bool mandatory;

  /// The profile RegisterScreen collected but held back from Firestore.
  /// Required when [mandatory] is true — this screen is what actually
  /// saves it, atomically with the face data, once enrollment succeeds.
  /// Ignored for re-enrollment (mandatory: false), since the profile
  /// already exists in that case.
  final Map<String, dynamic>? pendingProfile;

  /// Profile photo picked at registration (mandatory for CR, optional for
  /// students) — held in memory the same way, and only actually uploaded
  /// to Cloud Storage once enrollment succeeds.
  final File? pendingPhoto;

  const FaceEnrollmentScreen({
    super.key,
    this.mandatory = false,
    this.pendingProfile,
    this.pendingPhoto,
  }) : assert(
          !mandatory || pendingProfile != null,
          'pendingProfile is required when mandatory is true',
        );

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
  final EyeDistanceService eyeDistanceService = const EyeDistanceService();
  final FaceAlignmentService faceAlignmentService = const FaceAlignmentService();
  final CalibrationService calibrationService = CalibrationService();
  // HeadStabilityService, EmbeddingFusionService and FaceMatchService are
  // no longer used here. Stability was a gate on when to take a photo,
  // which a continuous scan doesn't need; fusion and near-duplicate
  // comparison both moved into ScanHarvester, where they can be weighted
  // by frame quality.
  final BlinkService blinkService = BlinkService();
  final EnrollmentGuideStyleService guideStyleService = const EnrollmentGuideStyleService();

  EnrollmentFlowState _flowState = EnrollmentFlowState.warmingUp;

  /// Collects the best frames of the sweep.
  ///
  /// Replaces the old per-pose counters and embedding buckets outright.
  /// Those tracked "have we taken two photos of the left side yet"; this
  /// tracks "which frames, out of every one the camera has produced, are
  /// the best representatives of each angle" — a question the student
  /// never has to participate in answering.
  final ScanHarvester _harvester = ScanHarvester();

  /// Decides what the student is asked to do next.
  final ScanGuide _guide = ScanGuide();

  /// Measurements from the current frame, computed in the cheap
  /// pre-check and handed to the scorer once the crop exists.
  double _lastOccupancy = 0;
  double _lastCenterOffset = 0;

  /// When the required bins filled. Optional far-angle bins get this
  /// long to fill before the scan closes itself.
  DateTime? _optionalGraceStarted;
  static const int _optionalGraceMs = 2500;

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
  bool _cameraUnavailable = false;
  

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



  // The old per-stage pose gate lived here. It answered "is the head in
  // the one position we're currently waiting for", which forced the
  // student to hit five discrete targets in a fixed order. The
  // harvester's angle bins answer the more useful question — "which part
  // of the sweep does this frame belong to" — and accept frames from any
  // of them, in any order, whenever they happen to be good.

  String _statusMessage = "Initializing biometric scanner...";

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
        _updateStatus("No camera detected on this device.");
        if (mounted) setState(() => _cameraUnavailable = true);
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
      _updateStatus("Camera failed to start. Check camera permission.");
      if (mounted) setState(() => _cameraUnavailable = true);
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

      
      

      // Framing measurements, kept for the scorer once the crop exists.
      _lastOccupancy = occupancyService.calculateOccupancy(
        face: face,
        frameWidth: cameraImage.width.toDouble(),
        frameHeight: cameraImage.height.toDouble(),
      );
      _lastCenterOffset = centerResult.distance /
          (math.sqrt(previewSize.width * previewSize.width +
                  previewSize.height * previewSize.height) /
              2);

      if (mounted) {
        setState(() {
          _detectedFaceRect = transformedFaceRect;
        });
      }

      // ---------- Liveness, once, before any frame is kept ----------
      //
      // Still a blink, still up front — but it now gates the whole scan
      // rather than just the front pose, and the sweep that follows is
      // itself corroborating evidence: a printed photo or a phone held
      // up to the lens cannot produce a coherent series of yaw angles
      // with consistent face geometry across them.
      if (!_isLivenessVerified) {
        if (!centerResult.passed || !alignmentResult.passed) {
          _setFlowState(
            EnrollmentFlowState.aligningFace,
            "Position your face in the circle",
          );
          return;
        }

        _setFlowState(
          EnrollmentFlowState.waitingForBlink,
          "Blink once to begin the scan",
        );

        if (blinkService.checkBlink(face)) {
          _isLivenessVerified = true;
          _setFlowState(
            EnrollmentFlowState.livenessVerified,
            "Starting scan",
          );
        }

        return;
      }

      // ---------- Continuous scan ----------
      //
      // No pose gate, no stability wait, no capture countdown. Every
      // frame is offered to the harvester, which keeps it only if it is
      // both good and useful. The old flow spent most of its time
      // waiting for the student to hold a pose it approved of; this one
      // spends that time collecting.
      final phaseChanged = _guide.update(
        harvester: _harvester,
        faceDetected: true,
      );

      _setFlowState(
        EnrollmentFlowState.capturing,
        ScanGuide.title(_guide.phase),
      );

      if (phaseChanged) {
        HapticFeedback.selectionClick();
      }

      await _harvestFrame(cameraImage, face);

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

  /// Offers one live frame to the harvester.
  ///
  /// This is the heart of the scanning flow, and it differs from the old
  /// capture step in two ways that matter.
  ///
  /// First, it never fails enrollment. The previous version aborted the
  /// entire session the moment a single frame came back blurry or badly
  /// lit — which, during a head turn, is most of them. Here a poor frame
  /// is simply not kept, and the sweep carries on.
  ///
  /// Second, it leaves the camera stream running. Stopping and
  /// restarting the stream around every capture cost roughly a second
  /// each time and is what made enrollment feel like a series of
  /// photographs. Frames arriving while this is still working are
  /// dropped by the `_isProcessingFrame` guard in the caller, which is
  /// the right behaviour: there is always another frame coming.
  Future<void> _harvestFrame(
      CameraImage streamImage, Face detectedFace) async {
    try {
      final imageFile = await _convertStreamFrameToFile(streamImage);
      if (imageFile == null) return;

      final croppedFace =
          await faceCropService.cropFace(imageFile, detectedFace);
      if (croppedFace == null) return;

      final deviceModel = await getDeviceModel();
      final threshold = calibrationService.calibratedSharpnessThreshold ??
          DeviceQualityThresholds.getSharpnessThreshold(deviceModel);

      final sharpness = sharpnessService.calculateSharpness(croppedFace);

      final brightness = brightnessService.calculateBrightness(croppedFace);
      final contrast = contrastService.calculateContrast(croppedFace);

      // Flip test-time-augmentation: averaging the embedding with its
      // mirror produces a more stable, canonical vector for this capture
      // (see FaceEmbeddingService.generateEmbeddingTTA), which is what the
      // duplicate-face check and later logins are compared against.
      final normalized =
          faceEmbeddingService.generateEmbeddingTTA(croppedFace);

      final quality = FaceQualityScorer.instance.score(
        sharpness: sharpness,
        brightness: brightness,
        contrast: contrast,
        occupancy: _lastOccupancy,
        centerOffset: _lastCenterOffset,
        yaw: detectedFace.headEulerAngleY ?? 0,
        pitch: detectedFace.headEulerAngleX ?? 0,
        roll: detectedFace.headEulerAngleZ ?? 0,
        sharpnessThreshold: threshold,
        // The sweep is *made* of off-centre views, so the yaw and pitch
        // limits are opened right up here. The harvester decides which
        // angle bin a frame belongs to; anything outside every bin is
        // dropped there, not treated as a quality defect.
        maxYaw: 60,
        maxPitch: 40,
      );

      final feedback = _harvester.offer(
        embedding: normalized,
        quality: quality,
      );

      if (!mounted) return;

      // Only the two states a student can act on reach the screen.
      // Narrating every redundant or duplicate frame would produce text
      // that changes several times a second and says nothing.
      if (feedback == ScanFeedback.poorQuality &&
          _harvester.lastFailure != null) {
        _updateStatus(_harvester.lastFailure!);
      }

      setState(() {}); // repaint the progress ring

      if (_harvester.hasRequiredCoverage && !_isSaving) {
        // Required coverage reached. Give the optional far-angle bins a
        // brief window to fill — they widen the template — but never
        // wait on them, so someone who can't turn far still finishes.
        _optionalGraceStarted ??= DateTime.now();

        final graceElapsed = DateTime.now()
                .difference(_optionalGraceStarted!)
                .inMilliseconds >
            _optionalGraceMs;

        if (graceElapsed || _harvester.outstandingBins.isEmpty) {
          await _finishScan();
        }
      }
    } catch (e) {
      // A single bad frame is not an enrollment failure. The sweep is
      // still running and the next frame is milliseconds away.
      debugPrint('Frame harvest skipped: $e');
    }
  }

  /// Ends the scan: grades the harvest, then either saves or sends the
  /// student round again.
  Future<void> _finishScan() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      await _cameraController?.stopImageStream();
    } catch (_) {
      // Already stopped — nothing to undo.
    }

    final grade = _harvester.grade();
    _harvester.debugDump();

    if (!grade.passed) {
      _signalEnrollmentFailure(
        "${grade.reason}\n\n"
        "Captured ${grade.sampleCount} usable frames across "
        "${grade.binsCovered} angles (quality ${grade.band}).",
      );
      return;
    }

    _setFlowState(
      EnrollmentFlowState.processing,
      "Scan complete — building your face profile",
    );

    await _uploadEmbeddingsToFirebase();
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
    _harvester.reset();
    _guide.reset();
    _optionalGraceStarted = null;
    _flowState = EnrollmentFlowState.warmingUp;
    _resetBlinkState();
    setState(() {
      _isSaving = false;
      _hasEnrollmentFailed = false;
      _isLivenessVerified = false;
      _isLowLightPaused = false;
      _flowState = EnrollmentFlowState.waitingForFace;
      _statusMessage = "Position your face in the circle";
    });
    _startFrameSubscription();
  }

  // The fixed instruction table and stage-advance ladder that used to
  // live here are now ScanGuide, which derives the next instruction from
  // what the harvester still needs rather than from a hardcoded order.


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
    // One representative vector per angle bin the scan actually
    // covered, each a quality-weighted mean of that bin's best frames.
    //
    // Weighted rather than a flat average because a bin's frames are not
    // equally good — the sweep passes through each angle and only some
    // of those moments were sharp. Letting a marginal frame pull the
    // bin's vector as hard as a crisp one is how a template ends up
    // representing nobody in particular.
    final Map<String, List<double>> fusedEmbeddings =
        _harvester.fusedByBin();

    if (fusedEmbeddings.isEmpty) {
      _signalEnrollmentFailure(
        "The scan didn't capture enough of your face. Please try again "
        "in better light.",
      );
      return;
    }

    final grade = _harvester.grade();

    _setFlowState(
      EnrollmentFlowState.checkingDuplicate,
      "Checking this face isn't already enrolled...",
    );

    // ---------- duplicate-face guard ----------
    // Compare against every OTHER student's stored enrollment before
    // saving anything. Uses findDuplicate(), which cross-compares every
    // pose captured just now against every pose the candidate has on
    // file (not a single blended vector against single poses — that
    // mismatch was under-scoring real duplicates and letting them
    // through). See AdaptiveFaceService.findDuplicate doc comment.
    final allEnrollments = await firestoreService.getAllFaceEnrollments();
    final otherCandidates = allEnrollments.docs
        .where((doc) => doc.id != user.uid)
        .map((doc) => FaceCandidate.fromDoc(doc.id, doc.data()))
        .toList();

    if (otherCandidates.isNotEmpty) {
      final liveCentroid =
          AdaptiveFaceService.fuse(fusedEmbeddings.values.toList());

      final duplicate = AdaptiveFaceService.instance.findDuplicate(
        livePoses: fusedEmbeddings,
        liveCentroid: liveCentroid,
        candidates: otherCandidates,
      );

      if (duplicate.accepted) {
        _signalEnrollmentFailure(
          "This face already appears to be enrolled under a different "
          "account. If you believe this is a mistake, contact the "
          "administration office — nothing has been saved.",
        );
        return;
      }
    }

    _setFlowState(
      EnrollmentFlowState.uploading,
      "Saving enrollment...",
    );

    if (widget.mandatory) {
      // The photo (mandatory for CR, optional for students) uploads now,
      // right alongside the rest of the profile — not at pick time —
      // for the same reason the profile itself waited: nothing should
      // exist anywhere until enrollment actually succeeds.
      var profile = widget.pendingProfile!;
      if (widget.pendingPhoto != null) {
        _setFlowState(
          EnrollmentFlowState.uploading,
          "Uploading profile photo...",
        );
        final photoUrl = await ProfilePhotoService.instance
            .upload(user.uid, widget.pendingPhoto!);
        profile = {...profile, 'profileImageUrl': photoUrl};
      }

      // First-time registration: profile + face data are written
      // together, atomically, only now that enrollment has actually
      // succeeded (see FirestoreService.completeRegistrationWithFace).
      await firestoreService.completeRegistrationWithFace(
        uid: user.uid,
        profile: profile,
        fusedEmbeddings: fusedEmbeddings,
        grade: grade,
      );
    } else {
      // Re-enrollment: the profile already exists, just refresh the
      // face data and the faceEnrolled/faceImagesCaptured flags on it.
      await firestoreService.updateFaceEmbeddings(
        user.uid,
        fusedEmbeddings,
        grade: grade,
      );
    }

    _showSnackbar(
      "Face profile saved — ${grade.sampleCount} frames across "
      "${grade.binsCovered} angles (${grade.band}).",
      Colors.green,
    );

    if (mounted) {
      if (widget.mandatory) {
        // Registration's required step just finished — go straight
        // into the app instead of popping back to the register form.
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const RoleRouter()),
          (_) => false,
        );
      } else {
        Navigator.pop(context);
      }
    }

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

  /// Only relevant when [widget.mandatory] is true: the profile was never
  /// saved (see FaceEnrollmentScreen doc comment), so there's nothing to
  /// "skip enrollment and finish later" — the account itself is rolled
  /// back instead, so the same email can be used to register again.
  Future<void> _cancelRegistration() async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text("Cancel Registration?"),
            content: const Text(
              "Nothing has been saved yet. Your account will be deleted so "
              "you can register again — including a chance to enroll your "
              "face — whenever you're ready.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Keep Trying"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Cancel & Delete Account",
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    try {
      await FirebaseAuth.instance.currentUser?.delete();
    } catch (_) {
      await FirebaseAuth.instance.signOut();
    }

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
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
    


    return PopScope(
      canPop: !widget.mandatory,
      child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.mandatory,
        title: Text(widget.mandatory
            ? "Enroll Your Face (Required)"
            : "Biometric Asset Enrollment"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: !_isCameraInitialized
          ? Center(
              child: _cameraUnavailable
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_off_rounded,
                              size: 44, color: Colors.redAccent),
                          const SizedBox(height: 16),
                          Text(_statusMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14)),
                          if (widget.mandatory) ...[
                            const SizedBox(height: 20),
                            OutlinedButton(
                              onPressed: _cancelRegistration,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(color: Colors.redAccent),
                              ),
                              child: const Text("Cancel Registration"),
                            ),
                          ],
                        ],
                      ),
                    )
                  : const CircularProgressIndicator(color: Colors.blueAccent),
            )
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

                        // Live scan progress. Shows how much of the sweep
                        // is covered, not how many photos have been
                        // taken — the student is never asked to think in
                        // shots, so the progress shouldn't be counted in
                        // them either.
                        if (_isLivenessVerified &&
                            !_hasEnrollmentFailed &&
                            !_isSaving) ...[
                          const SizedBox(height: 14),
                          Text(
                            ScanGuide.subtitle(_guide.phase),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(100),
                            child: LinearProgressIndicator(
                              value: _harvester.progress,
                              minHeight: 6,
                              color: Colors.tealAccent,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _ScanBinStrip(harvester: _harvester),
                        ],

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
                          ),
                          if (widget.mandatory) ...[
                            const SizedBox(height: 10),
                            OutlinedButton(
                              onPressed: _cancelRegistration,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                minimumSize: const Size(double.infinity, 45),
                                side: const BorderSide(color: Colors.redAccent),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text("Cancel Registration"),
                            ),
                          ],
                        ]
                      ],
                    ),
                  ),
                ),
              ],
            ),
      ),
    );
  }
}

/// The row of angle pips under the scan progress bar.
///
/// Gives the sweep a visible shape: the student can see which directions
/// are already covered and which the scan is still waiting on, without
/// any of it being phrased as a photo count. Required angles are drawn
/// solid; the optional far-angle ones sit at half opacity so an
/// unfilled one doesn't read as a failure.
class _ScanBinStrip extends StatelessWidget {
  final ScanHarvester harvester;

  const _ScanBinStrip({required this.harvester});

  static const List<ScanBin> _order = [
    ScanBin.farLeft,
    ScanBin.left,
    ScanBin.up,
    ScanBin.centre,
    ScanBin.down,
    ScanBin.right,
    ScanBin.farRight,
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _order.map((bin) {
        final required = ScanHarvester.requiredBins.contains(bin);
        final progress = harvester.progressFor(bin);
        final complete = harvester.isBinComplete(bin);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Opacity(
            opacity: required ? 1 : 0.55,
            child: Container(
              width: 22,
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                color: complete
                    ? Colors.tealAccent
                    : Color.lerp(
                        Colors.white24,
                        Colors.tealAccent,
                        progress,
                      ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
