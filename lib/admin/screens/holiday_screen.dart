import 'package:flutter/material.dart';

import '../../core/constants/app_config.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';
import '../models/holiday_model.dart';
import '../services/holiday_service.dart';

/// Admin-only: the department's non-working days.
///
/// Sundays and second Saturdays aren't listed — they're a rule the app
/// applies everywhere, not entries anyone should have to maintain. This
/// screen is only for the dates that can't be derived: festivals, exam
/// weeks, and closures called at short notice.
class HolidayScreen extends StatefulWidget {
  const HolidayScreen({super.key});

  @override
  State<HolidayScreen> createState() => _HolidayScreenState();
}

class _HolidayScreenState extends State<HolidayScreen> {
  bool _seeding = false;

  Future<void> _seed() async {
    setState(() => _seeding = true);
    try {
      final added = await HolidayService.instance.seedDefaults();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(added == 0
              ? 'Nothing to add — those dates are already listed.'
              : 'Added $added closed days from the AU 2026-27 calendar.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Couldn't add them: $e"),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  Future<void> _edit([Holiday? existing]) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final reasonController =
        TextEditingController(text: existing?.reason ?? '');
    var date = existing == null
        ? DateTime.now()
        : DateTime.tryParse(existing.date) ?? DateTime.now();
    var type = existing?.type ?? HolidayType.public;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg)),
          title: Text(existing == null ? 'Add a holiday' : 'Edit holiday',
              style: AppTextStyles.title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(AppConfig.dateId(date)),
                  subtitle: Text(AppConfig.dayName(date),
                      style: AppTextStyles.caption),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  // The date is the document id, so changing it on an
                  // existing entry would create a second one rather than
                  // move it. Delete and re-add instead.
                  onTap: existing != null
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: date,
                            firstDate: DateTime(date.year - 1),
                            lastDate: DateTime(date.year + 2),
                          );
                          if (picked != null) {
                            setDialogState(() => date = picked);
                          }
                        },
                ),
                SizedBox(height: Responsive.h(12)),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Name *',
                    hintText: 'Sankranti, Semester break…',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                ),
                SizedBox(height: Responsive.h(12)),
                TextField(
                  controller: reasonController,
                  decoration: InputDecoration(
                    labelText: 'Reason',
                    hintText: 'Shown to students on the calendar',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                ),
                SizedBox(height: Responsive.h(12)),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: HolidayType.public,
                        child: Text('Public holiday')),
                    DropdownMenuItem(
                        value: HolidayType.institutional,
                        child: Text('College holiday')),
                    DropdownMenuItem(
                        value: HolidayType.unscheduled,
                        child: Text('Unscheduled')),
                  ],
                  onChanged: (v) => setDialogState(() => type = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Back',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    if (nameController.text.trim().isEmpty) return;

    try {
      await HolidayService.instance.save(Holiday(
        date: AppConfig.dateId(date),
        name: nameController.text.trim(),
        reason: reasonController.text.trim(),
        type: type,
      ));
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
    }
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Holidays'),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: MaxWidthBody(
        maxWidth: 820,
        child: StreamBuilder<List<Holiday>>(
          stream: HolidayService.instance.watch(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final holidays = snapshot.data ?? const <Holiday>[];

            return ListView(
              padding: EdgeInsets.fromLTRB(Responsive.w(18), Responsive.h(12),
                  Responsive.w(18), Responsive.h(90)),
              children: [
                _buildWeeklyNote(),
                SizedBox(height: Responsive.h(14)),
                if (holidays.isEmpty)
                  _buildEmpty()
                else
                  ...holidays.map((h) => _HolidayTile(
                        holiday: h,
                        onEdit: () => _edit(h),
                        onDelete: () =>
                            HolidayService.instance.delete(h.date),
                      )),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildWeeklyNote() {
    return Container(
      padding: Responsive.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.primary.withValues(alpha: .2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.event_repeat_rounded,
              color: AppColors.primary, size: Responsive.sp(20)),
          SizedBox(width: Responsive.w(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sundays and second Saturdays are automatic',
                    style: AppTextStyles.title
                        .copyWith(fontSize: Responsive.sp(14))),
                SizedBox(height: Responsive.h(4)),
                Text(
                  "They're applied as a rule, so they never need adding "
                  'here and never fall out of date. Only list the dates '
                  "that can't be worked out — festivals, exam weeks, "
                  'unexpected closures.',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: Responsive.symmetric(vertical: 30),
      child: Column(
        children: [
          Icon(Icons.beach_access_outlined,
              size: Responsive.sp(38), color: AppColors.textSecondary),
          SizedBox(height: Responsive.h(14)),
          Text('No holidays listed yet', style: AppTextStyles.title),
          SizedBox(height: Responsive.h(6)),
          Text(
            'Without these, festival days count as absences for everyone.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
          SizedBox(height: Responsive.h(18)),
          ElevatedButton.icon(
            onPressed: _seeding ? null : _seed,
            icon: _seeding
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('Import AU 2026-27 calendar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          ),
          SizedBox(height: Responsive.h(10)),
          Padding(
            padding: Responsive.symmetric(horizontal: 20),
            child: Text(
              'Vacation blocks and semester dates come from the official '
              'AU College of Engineering calendar for 2026-27. Festival '
              'dates that depend on a moon sighting are announced close '
              'to the day and may move.',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _HolidayTile extends StatelessWidget {
  final Holiday holiday;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _HolidayTile({
    required this.holiday,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final parsed = DateTime.tryParse(holiday.date);

    return Container(
      margin: EdgeInsets.only(bottom: Responsive.h(10)),
      padding: Responsive.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: Responsive.w(52),
            padding: Responsive.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Column(
              children: [
                Text(
                  parsed == null ? '--' : '${parsed.day}',
                  style: TextStyle(
                    fontSize: Responsive.sp(17),
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  parsed == null
                      ? ''
                      : AppConfig.dayName(parsed).substring(0, 3),
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          SizedBox(width: Responsive.w(14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(holiday.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.title
                        .copyWith(fontSize: Responsive.sp(14))),
                SizedBox(height: Responsive.h(2)),
                Text(
                  holiday.reason.isEmpty
                      ? '${holiday.date} • ${HolidayType.label(holiday.type)}'
                      : '${holiday.reason} • ${HolidayType.label(holiday.type)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 19),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline_rounded,
                size: 19, color: AppColors.danger),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
