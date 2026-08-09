import 'dart:io';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../admin/models/period_model.dart';
import '../../core/constants/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../models/face_enrollment_imports.dart';
import '../services/classroom_recognition_service.dart';
import 'roster_review_screen.dart';

/// Points the camera at a class and names the students it recognises.
///
/// The rear camera, deliberately — the faculty member holds the phone up
/// and sweeps the room, which is the opposite of every other camera
/// screen in this app.
///
/// Nothing here is saved. The scan produces a draft that the faculty
/// member confirms on the next screen, because classroom recognition
/// reliably misses the back rows and a student marked absent by a
/// camera that simply couldn't see them has no way to know it happened.
class ClassroomScanScreen extends StatefulWidget {
  final PeriodModel period;
  final int year;
  final String facultyId;
  final String facultyName;
  final String facultyUid;

  const ClassroomScanScreen({
    super.key,
    required this.period,
    required this.year,
    required this.facultyId,
    required this.facultyName,
    required this.facultyUid,
  });

  @override
  State<ClassroomScanScreen> createState() => _ClassroomScanScreenState();
}

class _ClassroomScanScreenState extends State<ClassroomScanScreen> {
  final FaceDetectionService _detection = FaceDetectionService();
  final FaceCropService _cropper = FaceCropService();
  final FaceEmbeddingService _embedder = FaceEmbeddingService();
  final ClassroomRecognitionService _recogniser =
      ClassroomRecognitionService.instance;

  CameraController? _camera;
  bool _cameraReady = false;
  bool _busy = false;
  bool _loadingGallery = true;
  String? _error;

  /// Boxes to draw this frame.
  List<FaceLabel> _labels = const [];

  /// Roster for the year, needed both to name faces and to hand the
  /// review screen everyone who *could* have been present.
  Map<String, Map<String, dynamic>> _roster = {};

  int _framesProcessed = 0;

  /// Rotation last given to ML Kit — decides whether its coordinate
  /// space is the buffer's dimensions or their transpose.
  InputImageRotation _lastRotation = InputImageRotation.rotation90deg;

  /// Only every Nth frame is put through recognition. The camera
  /// delivers ~30 a second and a full pass over a roomful of faces takes
  /// far longer than 33ms; without this the queue grows until the app
  /// stops responding.
  static const int _frameStride = 6;
  int _frameCounter = 0;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      await _embedder.initialize();
      await _loadGallery();
      await _initCamera();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Pulls the year's students and their face templates into memory.
  ///
  /// Done once, up front. Matching a face against Firestore per frame
  /// would be both unusably slow and enormously expensive in reads.
  Future<void> _loadGallery() async {
    final db = FirebaseFirestore.instance;

    final studentSnap = await db.collection('students').get();

    final roster = <String, Map<String, dynamic>>{};
    for (final doc in studentSnap.docs) {
      final data = doc.data();
      if (AppConfig.departmentOf(data) != AppConfig.department) continue;
      if (AppConfig.yearOf(data) != widget.year) continue;
      // A lab period belongs to one batch; the rest of the year isn't
      // expected in the room and shouldn't appear on the roster.
      if (widget.period.batch.isNotEmpty) {
        final batch = (data['batch'] ?? '').toString();
        if (batch.isNotEmpty && batch != widget.period.batch) continue;
      }
      roster[doc.id] = data;
    }

    final enrollSnap =
        await db.collection('student_face_enrollments').get();

    final enrollments = <String, Map<String, dynamic>>{
      for (final doc in enrollSnap.docs)
        if (roster.containsKey(doc.id)) doc.id: doc.data(),
    };

    _recogniser.loadGallery(
      enrollments: enrollments,
      students: {
        for (final e in roster.entries)
          e.key: (
            name: (e.value['name'] ?? 'Unknown').toString(),
            regNo: (e.value['regNo'] ?? '').toString(),
          ),
      },
    );

    if (mounted) {
      setState(() {
        _roster = roster;
        _loadingGallery = false;
      });
    }
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      if (mounted) setState(() => _error = 'No camera on this device.');
      return;
    }

    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _camera = CameraController(
      back,
      // Higher than the enrollment screen uses: a face at the back of a
      // classroom is a fraction of the frame, and resolution is the one
      // thing that decides whether its crop carries usable detail.
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );

    await _camera!.initialize();
    if (!mounted) return;

    setState(() => _cameraReady = true);
    await _camera!.startImageStream(_onFrame);
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || !mounted) return;

    _frameCounter++;
    if (_frameCounter % _frameStride != 0) return;

    _busy = true;

    try {
      final input = _toInputImage(image);
      if (input == null) return;

      final faces = await _detection.detector.processImage(input);
      if (!mounted) return;

      final previewSize = MediaQuery.of(context).size;
      final imageSize =
          Size(image.width.toDouble(), image.height.toDouble());

      // ML Kit's coordinate space, which is the buffer transposed for
      // the quarter-turn rotations.
      final mlKitFrameWidth =
          (_lastRotation == InputImageRotation.rotation90deg ||
                  _lastRotation == InputImageRotation.rotation270deg)
              ? image.height.toDouble()
              : image.width.toDouble();

      final labels = <FaceLabel>[];
      File? frameFile;

      for (final face in faces) {
        final box = const CameraCoordinateTransformer().transformRect(
          rect: face.boundingBox,
          imageSize: imageSize,
          previewSize: previewSize,
          isFrontCamera: false,
        );

        // Too far away to identify honestly — drawn, but not guessed at.
        //
        // Measured against ML Kit's own frame width, which is the
        // buffer's *height* under a 90 or 270 degree rotation. Using
        // `image.width` compares a box in a 720-wide space against 1280
        // and makes every face look proportionally tiny.
        if (!_recogniser.isFaceUsable(face.boundingBox, mlKitFrameWidth)) {
          labels.add(FaceLabel(
              box: box, name: null, confirmed: false, score: 0));
          continue;
        }

        // Already counted and hasn't moved — skip the expensive part.
        // Most of a scan is the same seated people frame after frame.
        final known = _recogniser.confirmedNear(box);
        if (known != null) {
          known.lastBox = box;
          known.lastSeen = DateTime.now();
          labels.add(FaceLabel(
            box: box,
            name: known.name,
            confirmed: true,
            score: known.bestScore,
          ));
          continue;
        }

        // The whole frame is written once and cropped many times — one
        // JPEG encode per frame instead of one per face.
        frameFile ??= await _toFile(image);
        if (frameFile == null) continue;

        final crop = await _cropper.cropFace(frameFile, face);
        if (crop == null) continue;

        final embedding = _embedder.generateEmbedding(crop);
        final sighting =
            _recogniser.identify(embedding: embedding, box: box);

        labels.add(FaceLabel(
          box: box,
          name: sighting?.name,
          confirmed: sighting?.confirmed ?? false,
          score: sighting?.bestScore ?? 0,
        ));
      }

      _framesProcessed++;

      if (mounted) setState(() => _labels = labels);
    } catch (e) {
      debugPrint('Classroom frame skipped: $e');
    } finally {
      _busy = false;
    }
  }

  /// Reused every frame rather than a new timestamped file each time.
  /// A classroom sweep runs for minutes and encodes one JPEG per
  /// processed frame; timestamped paths would fill temp storage.
  late final String _scratchPath =
      '${Directory.systemTemp.path}/attendx_class_scratch.jpg';

  Future<File?> _toFile(CameraImage image) async {
    try {
      final path = _scratchPath;

      final planes = image.planes
          .map((p) => {
                'bytes': p.bytes,
                'bytesPerRow': p.bytesPerRow,
                'bytesPerPixel': p.bytesPerPixel,
              })
          .toList();

      // Key names and types must match encodeImageToJpegIsolate exactly:
      // it reads `format` as an ImageFormatGroup, not its name, and has
      // no rotation parameter.
      final jpeg = await compute(encodeImageToJpegIsolate, {
        'planes': planes,
        'width': image.width,
        'height': image.height,
        'format': image.format.group,
      });

      if (jpeg == null) return null;

      final file = File(path);
      await file.writeAsBytes(jpeg);
      return file;
    } catch (e) {
      debugPrint('Frame encode failed: $e');
      return null;
    }
  }

  static const Map<DeviceOrientation, int> _orientationDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  InputImage? _toInputImage(CameraImage image) {
    try {
      final camera = _camera!.description;

      // Back camera here, so the device rotation is subtracted rather
      // than added — the opposite of the front-facing enrollment screen.
      // Getting this wrong doesn't just soften detection; a sideways
      // frame produces crops the embedder can't match against anything.
      final InputImageRotation rotation;

      if (Platform.isIOS) {
        rotation =
            InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
                InputImageRotation.rotation0deg;
      } else {
        final deviceRotation =
            _orientationDegrees[_camera!.value.deviceOrientation] ?? 0;

        final compensated =
            camera.lensDirection == CameraLensDirection.front
                ? (camera.sensorOrientation + deviceRotation) % 360
                : (camera.sensorOrientation - deviceRotation + 360) % 360;

        rotation = InputImageRotationValue.fromRawValue(compensated) ??
            InputImageRotation.rotation0deg;
      }

      _lastRotation = rotation;

      final format =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
              InputImageFormat.nv21;

      // Every plane, concatenated — NV21 carries luma and chroma in
      // separate planes and ML Kit needs both. Passing only the first
      // gives it a Y plane with no colour data and detection quietly
      // degrades. Same approach as the enrollment screen.
      final buffer = WriteBuffer();
      for (final plane in image.planes) {
        buffer.putUint8List(plane.bytes);
      }

      return InputImage.fromBytes(
        bytes: buffer.done().buffer.asUint8List(),
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('InputImage conversion failed: $e');
      return null;
    }
  }

  Future<void> _finish() async {
    try {
      await _camera?.stopImageStream();
    } catch (_) {
      // Already stopped.
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RosterReviewScreen(
          period: widget.period,
          year: widget.year,
          roster: _roster,
          recognisedUids: _recogniser.presentUids,
          facultyId: widget.facultyId,
          facultyName: widget.facultyName,
          facultyUid: widget.facultyUid,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _camera?.dispose();
    _recogniser.dispose();

    // A frame of a classroom full of students shouldn't outlive the scan.
    try {
      final scratch = File(_scratchPath);
      if (scratch.existsSync()) scratch.deleteSync();
    } catch (_) {
      // Best effort.
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Class Scan')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    if (_loadingGallery || !_cameraReady || _camera == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 18),
              Text(
                _loadingGallery
                    ? 'Loading the class list…'
                    : 'Starting the camera…',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    final confirmed = _recogniser.confirmed;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_camera!),

          CustomPaint(painter: _LabelPainter(labels: _labels)),

          // Header: what's being marked.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .78),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.period.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            'Year ${widget.year} • '
                            '${widget.period.startTime}-${widget.period.endTime}'
                            '${widget.period.batch.isEmpty ? '' : ' • Batch ${widget.period.batch}'}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Footer: running count and the way out.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .82),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.groups_rounded,
                            color: AppColors.teal, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${confirmed.length} of ${_roster.length} recognised',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Text(
                          '$_framesProcessed frames',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sweep slowly across the room. Anyone missed can be '
                      'ticked on the next screen.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: Colors.white60, fontSize: 11.5),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _finish,
                        icon: const Icon(Icons.checklist_rounded),
                        label: const Text('Review & Save'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws a box round every detected face, with a name once there is one.
///
/// Three states, deliberately distinguishable at a glance while sweeping
/// a room: green and named (counted), amber and named (seen, not yet
/// confirmed), grey and blank (detected but too far away to identify).
class _LabelPainter extends CustomPainter {
  final List<FaceLabel> labels;

  const _LabelPainter({required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    for (final label in labels) {
      final Color colour;
      if (label.confirmed) {
        colour = AppColors.success;
      } else if (label.name != null) {
        colour = AppColors.warning;
      } else {
        colour = Colors.white38;
      }

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = label.confirmed ? 3 : 2
        ..color = colour;

      canvas.drawRRect(
        RRect.fromRectAndRadius(label.box, const Radius.circular(8)),
        paint,
      );

      if (label.name == null) continue;

      final text = TextPainter(
        text: TextSpan(
          text: label.confirmed
              ? label.name
              : '${label.name} …',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.5);

      // Label sits above the box, or below it when the face is near the
      // top of the frame and there's no room above.
      final labelTop = label.box.top > 24
          ? label.box.top - 22
          : label.box.bottom + 4;

      final bg = Rect.fromLTWH(
        label.box.left,
        labelTop,
        text.width + 12,
        20,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(bg, const Radius.circular(6)),
        Paint()..color = colour.withValues(alpha: .92),
      );

      text.paint(canvas, Offset(bg.left + 6, bg.top + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _LabelPainter old) =>
      old.labels != labels;
}
