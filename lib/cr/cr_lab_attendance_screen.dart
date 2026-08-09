import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../admin/models/period_model.dart';
import '../admin/services/timetable_service.dart';
import '../core/constants/app_config.dart';
import '../core/responsive/responsive.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radius.dart';
import '../core/theme/app_text_styles.dart';
import '../faculty/models/period_attendance.dart';
import '../faculty/services/period_attendance_service.dart';

/// Lets a CR mark a lab for their own batch.
///
/// Labs are the one place a CR is better placed than the camera. A
/// theory class is a roomful of faces a lecturer can sweep in one pass;
/// a lab is a dozen students spread across benches, heads down over
/// equipment, facing away. The CR already knows who turned up, and
/// asking them to tick a list is faster and more accurate than asking a
/// camera to find faces that are mostly pointed at an oscilloscope.
///
/// Deliberately narrower than the faculty scan:
/// - only labs, never theory;
/// - only the CR's own year;
/// - only their own batch, when the period names one.
class CrLabAttendanceScreen extends StatefulWidget {
  final Map<String, dynamic> studentData;

  const CrLabAttendanceScreen({super.key, required this.studentData});

  @override
  State<CrLabAttendanceScreen> createState() =>
      _CrLabAttendanceScreenState();
}

class _CrLabAttendanceScreenState extends State<CrLabAttendanceScreen> {
  late final int _year = AppConfig.yearOf(widget.studentData);
  late final String _department = AppConfig.departmentOf(widget.studentData);
  late final String _myBatch =
      (widget.studentData['batch'] ?? '').toString();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<PeriodModel> _labs = const [];
  PeriodModel? _selected;

  /// uid -> student doc, for the batch this lab belongs to.
  Map<String, Map<String, dynamic>> _roster = {};
  final Set<String> _present = {};

  DateTime get _now => DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadLabs();
  }

  Future<void> _loadLabs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final weekday = AppConfig.dayName(_now);

      final periods = weekday == 'Sunday'
          ? <PeriodModel>[]
          : await TimetableService.instance.getDaySchedule(
              department: _department,
              academicYear: AppConfig.academicYear,
              year: _year,
              day: weekday,
            );

      final labs = periods
          .where((p) =>
              !p.isFree &&
              p.subject.isNotEmpty &&
              p.classType.toLowerCase() == 'lab' &&
              // A lab for another batch isn't this CR's to mark.
              (p.batch.isEmpty || _myBatch.isEmpty || p.batch == _myBatch))
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

      if (mounted) {
        setState(() {
          _labs = labs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _selectLab(PeriodModel lab) async {
    setState(() {
      _selected = lab;
      _loading = true;
      _present.clear();
    });

    try {
      final snap =
          await FirebaseFirestore.instance.collection('students').get();

      final roster = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        if (AppConfig.departmentOf(data) != _department) continue;
        if (AppConfig.yearOf(data) != _year) continue;

        // Only this batch, when the lab names one.
        if (lab.batch.isNotEmpty) {
          final batch = (data['batch'] ?? '').toString();
          if (batch.isNotEmpty && batch != lab.batch) continue;
        }

        roster[doc.id] = data;
      }

      // Pre-fill from an existing record so re-marking corrects rather
      // than starts from a blank list.
      final existing = await PeriodAttendanceService.instance.forPeriod(
        department: _department,
        year: _year,
        date: AppConfig.dateId(_now),
        periodNo: lab.periodNo,
      );

      if (mounted) {
        setState(() {
          _roster = roster;
          if (existing != null) _present.addAll(existing.presentUids);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final lab = _selected;
    if (lab == null) return;

    setState(() => _saving = true);

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    final record = PeriodAttendance(
      id: '',
      department: _department,
      year: _year,
      academicYear: AppConfig.academicYear,
      date: AppConfig.dateId(_now),
      periodNo: lab.periodNo,
      startTime: lab.startTime,
      endTime: lab.endTime,
      subject: lab.subject,
      batch: lab.batch,
      facultyId: lab.facultyId,
      facultyName: lab.facultyName,
      presentUids: _present.toList(),
      // Nothing was recognised by a camera — every tick here is a
      // person's judgement, and the record should say so.
      recognisedUids: const [],
      method: PeriodAttendanceMethod.manual,
      markedBy: uid,
      markedByName:
          '${widget.studentData['name'] ?? 'CR'} (CR)',
    );

    try {
      await PeriodAttendanceService.instance.save(record);
      await PeriodAttendanceService.instance.notifyAbsentees(
        record: record,
        allStudentUids: _roster.keys.toList(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${lab.subject} saved — ${_present.length} present, '
              '${_roster.length - _present.length} absent.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
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
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_selected == null ? 'Lab Attendance' : _selected!.subject),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          if (_selected != null)
            TextButton(
              onPressed: _saving
                  ? null
                  : () => setState(() => _present.addAll(_roster.keys)),
              child: const Text('All present'),
            ),
        ],
      ),
      body: MaxWidthBody(
        maxWidth: 720,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: Responsive.all(24),
                      child: Text("Couldn't load: $_error",
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body),
                    ),
                  )
                : _selected == null
                    ? _buildLabPicker()
                    : _buildRoster(),
      ),
    );
  }

  Widget _buildLabPicker() {
    if (_labs.isEmpty) {
      return Center(
        child: Padding(
          padding: Responsive.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.science_outlined,
                  size: Responsive.sp(40), color: AppColors.textSecondary),
              SizedBox(height: Responsive.h(16)),
              Text('No lab scheduled today', style: AppTextStyles.title),
              SizedBox(height: Responsive.h(6)),
              Text(
                _myBatch.isEmpty
                    ? 'Labs for your year will appear here on the day.'
                    : 'Labs for Batch $_myBatch will appear here on the day.',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: Responsive.all(18),
      children: [
        Text("Today's labs", style: AppTextStyles.title),
        SizedBox(height: Responsive.h(4)),
        Text(
          'Pick the lab you are marking. Only labs for your year'
          '${_myBatch.isEmpty ? '' : ' and batch'} are listed.',
          style: AppTextStyles.caption,
        ),
        SizedBox(height: Responsive.h(14)),
        ..._labs.map((lab) => Container(
              margin: EdgeInsets.only(bottom: Responsive.h(10)),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: const [
                  BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 10,
                      offset: Offset(0, 4)),
                ],
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md)),
                leading: const Icon(Icons.science_rounded,
                    color: AppColors.teal),
                title: Text(lab.subject,
                    style: AppTextStyles.title
                        .copyWith(fontSize: Responsive.sp(14))),
                subtitle: Text(
                  '${lab.startTime} - ${lab.endTime}'
                  '${lab.batch.isEmpty ? '' : '  •  Batch ${lab.batch}'}'
                  '${lab.room.isEmpty ? '' : '  •  ${lab.room}'}',
                  style: AppTextStyles.caption,
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: AppColors.textSecondary),
                onTap: () => _selectLab(lab),
              ),
            )),
      ],
    );
  }

  Widget _buildRoster() {
    final entries = _roster.entries.toList()
      ..sort((a, b) {
        int reg(Map<String, dynamic> d) {
          final m = RegExp(r'(\d+)\s*$')
              .firstMatch((d['regNo'] ?? '').toString());
          return m == null ? 1 << 30 : (int.tryParse(m.group(1)!) ?? 1 << 30);
        }

        return reg(a.value).compareTo(reg(b.value));
      });

    return Column(
      children: [
        if (_saving) const LinearProgressIndicator(minHeight: 2),
        Container(
          margin: Responsive.all(16),
          padding: Responsive.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: const [
              BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 12,
                  offset: Offset(0, 5)),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_present.length} of ${_roster.length} present',
                  style: AppTextStyles.title
                      .copyWith(fontSize: Responsive.sp(15)),
                ),
              ),
              if (_selected!.batch.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.teal.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Batch ${_selected!.batch}',
                      style: TextStyle(
                        color: AppColors.tealDark,
                        fontWeight: FontWeight.w700,
                        fontSize: Responsive.sp(11),
                      )),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(
                Responsive.w(16), 0, Responsive.w(16), Responsive.h(20)),
            itemCount: entries.length,
            separatorBuilder: (_, _) => SizedBox(height: Responsive.h(8)),
            itemBuilder: (context, i) {
              final uid = entries[i].key;
              final data = entries[i].value;
              final present = _present.contains(uid);

              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: CheckboxListTile(
                  value: present,
                  activeColor: AppColors.success,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md)),
                  title: Text((data['name'] ?? 'Unknown').toString(),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text((data['regNo'] ?? '--').toString(),
                      style: AppTextStyles.caption),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _present.add(uid);
                    } else {
                      _present.remove(uid);
                    }
                  }),
                ),
              );
            },
          ),
        ),
        Container(
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
                label: Text('Save — ${_present.length} present'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: Responsive.symmetric(vertical: 15),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
