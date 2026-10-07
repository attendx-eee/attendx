import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../admin/models/period_model.dart';
import '../../core/constants/app_config.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';
import '../models/period_attendance.dart';
import '../services/period_attendance_service.dart';
import '../../core/device/scan_provenance_service.dart';

/// The class list after a scan, for the faculty member to confirm.
///
/// This screen is the reason the camera is allowed to mark attendance at
/// all. Classroom recognition is reliably wrong about the back of the
/// room — every published system reports the same — so the scan's output
/// is treated as a draft, not a verdict. Students it found are ticked;
/// the rest are not; the faculty member fixes the difference in a few
/// seconds and saves.
///
/// Unrecognised students are listed first, since they are the only ones
/// that need a decision.
class RosterReviewScreen extends StatefulWidget {
  final PeriodModel period;
  final int year;

  /// uid -> student doc for everyone who could have been in the room.
  final Map<String, Map<String, dynamic>> roster;

  /// Who the camera confirmed.
  final List<String> recognisedUids;

  final String facultyId;
  final String facultyName;
  final String facultyUid;

  const RosterReviewScreen({
    super.key,
    required this.period,
    required this.year,
    required this.roster,
    required this.recognisedUids,
    required this.facultyId,
    required this.facultyName,
    required this.facultyUid,
  });

  @override
  State<RosterReviewScreen> createState() => _RosterReviewScreenState();
}

class _RosterReviewScreenState extends State<RosterReviewScreen> {
  late final Set<String> _present = {...widget.recognisedUids};
  late final Set<String> _recognised = {...widget.recognisedUids};

  bool _saving = false;

  /// Where this register is being taken and what state the phone is in.
  ///
  /// Collected when the review opens rather than when save is pressed,
  /// so the lecturer can be told about anything odd *before* they commit
  /// rather than after. The minute between opening this screen and
  /// pressing save does not move anybody to a different building.
  ScanProvenance _provenance = const ScanProvenance();

  @override
  void initState() {
    super.initState();
    _collectProvenance();
  }

  Future<void> _collectProvenance() async {
    final collected = await ScanProvenanceService.instance.collect();
    if (mounted) setState(() => _provenance = collected);
  }

  /// Unrecognised first, then by roll number within each group.
  late final List<MapEntry<String, Map<String, dynamic>>> _sorted = () {
    final entries = widget.roster.entries.toList();

    int regOf(Map<String, dynamic> d) {
      final m = RegExp(r'(\d+)\s*$')
          .firstMatch((d['regNo'] ?? '').toString());
      return m == null ? 1 << 30 : (int.tryParse(m.group(1)!) ?? 1 << 30);
    }

    entries.sort((a, b) {
      final aKnown = _recognised.contains(a.key) ? 1 : 0;
      final bKnown = _recognised.contains(b.key) ? 1 : 0;
      if (aKnown != bKnown) return aKnown.compareTo(bKnown);
      return regOf(a.value).compareTo(regOf(b.value));
    });

    return entries;
  }();

  int get _absentCount => widget.roster.length - _present.length;

  Future<void> _save() async {
    setState(() => _saving = true);

    final now = DateTime.now();

    final record = PeriodAttendance(
      id: '',
      department: AppConfig.department,
      year: widget.year,
      academicYear: AppConfig.academicYear,
      date: AppConfig.dateId(now),
      periodNo: widget.period.periodNo,
      startTime: widget.period.startTime,
      endTime: widget.period.endTime,
      subject: widget.period.subject,
      batch: widget.period.batch,
      facultyId: widget.facultyId,
      facultyName: widget.facultyName,
      presentUids: _present.toList(),
      recognisedUids: _recognised.toList(),
      method: PeriodAttendanceMethod.scan,
      markedBy: FirebaseAuth.instance.currentUser?.uid ?? widget.facultyUid,
      markedByName: widget.facultyName,
      provenance: _provenance.toMap(),
    );

    try {
      await PeriodAttendanceService.instance.save(record);
      await PeriodAttendanceService.instance.notifyAbsentees(
        record: record,
        allStudentUids: widget.roster.keys.toList(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${widget.period.subject} saved — ${_present.length} present, '
              '$_absentCount absent.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Couldn't save: $e"),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Confirm Attendance'),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () => setState(() => _present.addAll(widget.roster.keys)),
            child: const Text('All present'),
          ),
        ],
      ),
      body: MaxWidthBody(
        maxWidth: 820,
        child: Column(
          children: [
            if (_saving) const LinearProgressIndicator(minHeight: 2),

            // Told, not stopped. Developer options being on is weak
            // evidence of anything by itself, and a lecturer locked out
            // of their own register by a setting they do not remember
            // turning on would be a far worse outcome than a note on the
            // record. Shown here rather than after saving so it is
            // information they can still act on.
            if (_provenance.flagged)
              Container(
                margin: Responsive.symmetric(horizontal: 16, vertical: 8),
                padding: Responsive.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: Responsive.sp(16), color: AppColors.warning),
                    SizedBox(width: Responsive.w(8)),
                    Expanded(
                      child: Text(
                        'Developer options are on for this phone. The '
                        'register will save normally; the department will '
                        'see this noted on it.',
                        style: AppTextStyles.caption,
                      ),
                    ),
                  ],
                ),
              ),

            _buildSummary(),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  Responsive.w(16),
                  0,
                  Responsive.w(16),
                  Responsive.h(24),
                ),
                itemCount: _sorted.length,
                separatorBuilder: (_, _) =>
                    SizedBox(height: Responsive.h(8)),
                itemBuilder: (context, i) {
                  final entry = _sorted[i];
                  final uid = entry.key;
                  final data = entry.value;

                  return _StudentRow(
                    name: (data['name'] ?? 'Unknown').toString(),
                    regNo: (data['regNo'] ?? '--').toString(),
                    present: _present.contains(uid),
                    recognised: _recognised.contains(uid),
                    photoUrl: data['profileImageUrl'] as String?,
                    onChanged: (value) => setState(() {
                      if (value) {
                        _present.add(uid);
                      } else {
                        _present.remove(uid);
                      }
                    }),
                  );
                },
              ),
            ),
            _buildSaveBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final missed = _recognised.length < widget.roster.length;

    return Container(
      margin: Responsive.all(16),
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
          Text(widget.period.subject, style: AppTextStyles.title),
          SizedBox(height: Responsive.h(2)),
          Text(
            'Year ${widget.year} • ${widget.period.startTime}-'
            '${widget.period.endTime}'
            '${widget.period.batch.isEmpty ? '' : ' • Batch ${widget.period.batch}'}',
            style: AppTextStyles.caption,
          ),
          SizedBox(height: Responsive.h(14)),
          Row(
            children: [
              _Metric(
                value: '${_present.length}',
                label: 'Present',
                color: AppColors.success,
              ),
              _Metric(
                value: '$_absentCount',
                label: 'Absent',
                color: _absentCount == 0
                    ? AppColors.textSecondary
                    : AppColors.danger,
              ),
              _Metric(
                value: '${_recognised.length}',
                label: 'By camera',
                color: AppColors.primary,
              ),
            ],
          ),
          if (missed) ...[
            SizedBox(height: Responsive.h(12)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: Responsive.sp(15), color: AppColors.warning),
                SizedBox(width: Responsive.w(8)),
                Expanded(
                  child: Text(
                    'The camera often misses students at the back or turned '
                    'away. Anyone it missed is listed first, unticked — '
                    'tick them before saving.',
                    style: AppTextStyles.caption,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSaveBar() {
    return Container(
      padding: Responsive.all(16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_rounded),
            label: Text(
              'Save — ${_present.length} present, $_absentCount absent',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: Responsive.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  final String name;
  final String regNo;
  final bool present;

  /// Found by the camera rather than ticked by hand. Shown so the
  /// faculty member can see at a glance which entries are the machine's
  /// opinion and which are their own.
  final bool recognised;

  /// Their enrolment photo, if they have supplied one.
  final String? photoUrl;

  final ValueChanged<bool> onChanged;

  const _StudentRow({
    required this.name,
    required this.regNo,
    required this.present,
    required this.recognised,
    required this.photoUrl,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => onChanged(!present),
          child: Padding(
            padding: Responsive.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Checkbox(
                  value: present,
                  activeColor: AppColors.success,
                  onChanged: (v) => onChanged(v ?? false),
                ),

                // The student's own photo.
                //
                // This list is where a lecturer decides whether somebody
                // the camera missed was actually in the room, and a name
                // and roll number are a poor way to make that decision
                // for a class of eighty. A face is the thing they can
                // check against the room in front of them.
                _Portrait(name: name, photoUrl: photoUrl),
                SizedBox(width: Responsive.w(12)),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.title
                            .copyWith(fontSize: Responsive.sp(14)),
                      ),
                      SizedBox(height: Responsive.h(2)),
                      Text(regNo, style: AppTextStyles.caption),
                    ],
                  ),
                ),
                if (recognised)
                  Tooltip(
                    message: 'Recognised by the camera',
                    child: Icon(Icons.center_focus_strong_rounded,
                        size: Responsive.sp(17), color: AppColors.primary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A student's photo, or their initial when they have not supplied one.
///
/// The fallback is deliberately plain rather than an error state. A
/// student without a photo is not a fault to be flagged at the lecturer
/// mid-register; it just means this row has to be judged on the name.
class _Portrait extends StatelessWidget {
  final String name;
  final String? photoUrl;

  const _Portrait({required this.name, required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final size = Responsive.w(42);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    final placeholder = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: AppColors.primary.withValues(alpha: .10),
      child: Text(
        initial,
        style: AppTextStyles.title.copyWith(
          fontSize: Responsive.sp(16),
          color: AppColors.primary,
        ),
      ),
    );

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: (photoUrl == null || photoUrl!.isEmpty)
            ? placeholder
            : Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                // A classroom with poor signal should not leave a column
                // of spinners down the list.
                errorBuilder: (_, _, _) => placeholder,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : placeholder,
              ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _Metric({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: AppTextStyles.headline
                  .copyWith(color: color, fontSize: Responsive.sp(20))),
          SizedBox(height: Responsive.h(2)),
          Text(label, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}
