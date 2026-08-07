import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';
import '../import/mlkit_recogniser.dart';
import '../import/timetable_parser.dart';
import '../models/faculty_model.dart';
import '../services/master_data_service.dart';

/// Reads a timetable off a photograph, for review before saving.
///
/// A companion to the manual editor, not a replacement for it. Typing a
/// four-year timetable in by hand is a day's work; photographing four
/// sheets is a minute. But OCR on a photographed, sometimes handwritten
/// document is never perfect, so nothing here writes to the timetable
/// until it's been looked at — a silently wrong timetable would misroute
/// attendance for a whole year before anyone noticed.
///
/// What it saves today is the **faculty legend**, which is the safest
/// and most immediately useful part: the codes and names printed under
/// every grid are exactly the records Master Data needs, and they're
/// unambiguous in a way a merged, half-legible cell isn't. The parsed
/// periods are shown for checking; writing them into the timetable is
/// the next step and deliberately still manual.
class TimetableImportScreen extends StatefulWidget {
  const TimetableImportScreen({super.key});

  @override
  State<TimetableImportScreen> createState() => _TimetableImportScreenState();
}

class _TimetableImportScreenState extends State<TimetableImportScreen> {
  final MlKitRecogniser _recogniser = MlKitRecogniser();
  final ImagePicker _picker = ImagePicker();

  File? _image;
  ParsedTimetable? _parsed;
  bool _busy = false;
  String? _error;

  /// Legend codes the admin has chosen to import.
  final Set<String> _selectedFaculty = {};

  @override
  void dispose() {
    _recogniser.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        // A timetable is dense small text; downscaling loses the
        // faculty initials first.
        maxWidth: 3000,
        imageQuality: 100,
      );
      if (picked == null) return;

      setState(() {
        _image = File(picked.path);
        _parsed = null;
        _error = null;
        _busy = true;
        _selectedFaculty.clear();
      });

      final doc = await _recogniser.recognise(picked.path);

      if (doc.isEmpty) {
        setState(() {
          _busy = false;
          _error = 'No text found in that image. Try a straighter, '
              'better-lit photo of the printed sheet.';
        });
        return;
      }

      final parsed = TimetableParser.instance.parse(doc);

      setState(() {
        _parsed = parsed;
        _selectedFaculty.addAll(parsed.faculty.map((f) => f.code));
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Could not read that image: $e';
      });
    }
  }

  Future<void> _importFaculty() async {
    final parsed = _parsed;
    if (parsed == null) return;

    final chosen =
        parsed.faculty.where((f) => _selectedFaculty.contains(f.code));
    if (chosen.isEmpty) return;

    setState(() => _busy = true);

    var added = 0;
    var skipped = 0;

    try {
      // Existing records are matched on short name so re-importing the
      // same sheet doesn't create duplicates.
      final existing = await MasterDataService.instance.getFaculty().first;
      final haveCodes = existing
          .map((f) => f.shortName.toUpperCase())
          .where((s) => s.isNotEmpty)
          .toSet();

      for (final f in chosen) {
        if (haveCodes.contains(f.code)) {
          skipped++;
          continue;
        }

        await MasterDataService.instance.addFaculty(FacultyModel(
          id: '',
          name: f.name,
          shortName: f.code,
          // Designation is inferred from the honorific the sheet
          // printed; the admin can correct it in Faculty Management.
          designation: f.name.toLowerCase().startsWith('prof')
              ? 'Professor'
              : 'Assistant Professor',
          active: true,
        ));
        added++;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $added faculty'
              '${skipped > 0 ? ', skipped $skipped already on file' : ''}.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Couldn't save: $e"),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Import from image'),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: MaxWidthBody(
        maxWidth: 820,
        child: ListView(
          padding: Responsive.all(18),
          children: [
            _buildPickers(),
            if (_busy) ...[
              SizedBox(height: Responsive.h(24)),
              const Center(child: CircularProgressIndicator()),
              SizedBox(height: Responsive.h(12)),
              Center(
                child: Text('Reading the sheet…',
                    style: AppTextStyles.caption),
              ),
            ],
            if (_error != null) ...[
              SizedBox(height: Responsive.h(18)),
              _buildError(),
            ],
            if (_parsed != null && !_busy) ...[
              SizedBox(height: Responsive.h(20)),
              _buildFacultySection(),
              SizedBox(height: Responsive.h(20)),
              _buildPeriodSection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPickers() {
    return Container(
      padding: Responsive.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Photograph the timetable sheet',
              style: AppTextStyles.title),
          SizedBox(height: Responsive.h(6)),
          Text(
            'Lay it flat, fill the frame, and keep the camera square to '
            'the page. Everything read is shown for checking before '
            'anything is saved.',
            style: AppTextStyles.caption,
          ),
          if (_image != null) ...[
            SizedBox(height: Responsive.h(14)),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Image.file(_image!, height: 170, fit: BoxFit.cover),
            ),
          ],
          SizedBox(height: Responsive.h(16)),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _busy ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Camera'),
                  style: OutlinedButton.styleFrom(
                    padding: Responsive.symmetric(vertical: 12),
                  ),
                ),
              ),
              SizedBox(width: Responsive.w(12)),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      _busy ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text('Upload'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: Responsive.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: Responsive.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.danger.withValues(alpha: .3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.danger, size: 18),
          SizedBox(width: Responsive.w(8)),
          Expanded(
            child: Text(_error!,
                style:
                    AppTextStyles.caption.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  Widget _buildFacultySection() {
    final faculty = _parsed!.faculty;

    return Container(
      padding: Responsive.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Faculty found in the legend', style: AppTextStyles.title),
          SizedBox(height: Responsive.h(4)),
          Text(
            faculty.isEmpty
                ? "No legend found. It's the line under the grid mapping "
                    'initials to names.'
                : 'Untick anyone already on file under a different '
                    'spelling.',
            style: AppTextStyles.caption,
          ),
          SizedBox(height: Responsive.h(10)),
          ...faculty.map((f) => CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _selectedFaculty.contains(f.code),
                title: Text(f.name,
                    style: AppTextStyles.body
                        .copyWith(color: AppColors.textPrimary)),
                subtitle: Text(f.code, style: AppTextStyles.caption),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selectedFaculty.add(f.code);
                  } else {
                    _selectedFaculty.remove(f.code);
                  }
                }),
              )),
          if (faculty.isNotEmpty) ...[
            SizedBox(height: Responsive.h(8)),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selectedFaculty.isEmpty || _busy
                    ? null
                    : _importFaculty,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: Text('Add ${_selectedFaculty.length} to Master Data'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: Responsive.symmetric(vertical: 13),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPeriodSection() {
    final periods = _parsed!.periods;

    return Container(
      padding: Responsive.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${periods.length} classes read', style: AppTextStyles.title),
          SizedBox(height: Responsive.h(4)),
          Text(
            'Check these against the sheet, then build the timetable in '
            'the manual editor. Writing them in automatically is not '
            'enabled yet — a misread cell would misroute a year of '
            'attendance.',
            style: AppTextStyles.caption,
          ),
          SizedBox(height: Responsive.h(12)),
          ...periods.map((p) => Padding(
                padding: EdgeInsets.only(bottom: Responsive.h(8)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: Responsive.w(78),
                      child: Text(
                        '${p.day.substring(0, 3)} · ${p.column + 1}',
                        style: AppTextStyles.caption
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.subject,
                              style: AppTextStyles.body.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600)),
                          if (p.facultyCodes.isNotEmpty ||
                              p.batch.isNotEmpty)
                            Text(
                              [
                                if (p.facultyCodes.isNotEmpty)
                                  p.facultyCodes.join(', '),
                                if (p.batch.isNotEmpty) 'Batch ${p.batch}',
                              ].join('  •  '),
                              style: AppTextStyles.caption,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
