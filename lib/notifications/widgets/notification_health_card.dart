import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/constants/app_config.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';
import '../services/local_notification_service.dart';

/// Shows whether scheduled notifications are actually working.
///
/// "My notifications don't come" is otherwise unanswerable from inside
/// the app. Three quite different things produce identical silence: the
/// OS withholding the exact-alarm permission, the timetable failing to
/// load so nothing gets scheduled, or the manufacturer's battery saver
/// killing the alarm. This says which.
class NotificationHealthCard extends StatefulWidget {
  /// Re-runs scheduling. Supplied by the caller because a student and a
  /// faculty member schedule different things.
  final Future<void> Function() onReschedule;

  const NotificationHealthCard({super.key, required this.onReschedule});

  @override
  State<NotificationHealthCard> createState() =>
      _NotificationHealthCardState();
}

class _NotificationHealthCardState extends State<NotificationHealthCard> {
  List<PendingNotificationRequest> _pending = const [];
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    final pending = await LocalNotificationService.instance.pending();
    if (!mounted) return;
    setState(() {
      _pending = pending;
      _busy = false;
    });
  }

  Future<void> _reschedule() async {
    setState(() => _busy = true);
    await widget.onReschedule();
    await _refresh();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_pending.length} reminders queued.'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _test() async {
    await LocalNotificationService.instance.showNow(
      id: 999999,
      title: 'AttendX test',
      body: 'If you can see this, notifications are switched on.',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sent — check your notification shade.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exact = LocalNotificationService.instance.exactAlarmsAllowed;
    final scheduled = _pending.length;

    // Zero queued reminders is the real failure. The permission being
    // off only downgrades timing; nothing queued means nothing will ever
    // arrive, whatever the permissions say.
    final healthy = scheduled > 0;

    return Container(
      padding: Responsive.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: healthy
              ? AppColors.divider
              : AppColors.warning.withValues(alpha: .5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                healthy
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_off_rounded,
                color: healthy ? AppColors.success : AppColors.warning,
                size: Responsive.sp(22),
              ),
              SizedBox(width: Responsive.w(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reminders',
                        style: AppTextStyles.title
                            .copyWith(fontSize: Responsive.sp(14))),
                    SizedBox(height: Responsive.h(3)),
                    Text(
                      _busy
                          ? 'Checking…'
                          : healthy
                              ? '$scheduled queued — including your '
                                  '${AppConfig.dailyDigestHour}:00 daily '
                                  'schedule'
                              : 'Nothing is queued',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (!_busy && !healthy) ...[
            SizedBox(height: Responsive.h(12)),
            _note(
              'No reminders are scheduled, so none will arrive. This '
              'usually means the timetable for your year is empty, or '
              'the app has not finished loading it since you signed in. '
              'Try Reschedule below.',
              AppColors.warning,
            ),
          ],

          if (exact == false) ...[
            SizedBox(height: Responsive.h(10)),
            _note(
              'Alarms & reminders is turned off for AttendX, so times '
              'may drift by a few minutes. Android Settings → Apps → '
              'AttendX → Alarms & reminders to allow it.',
              AppColors.primary,
            ),
          ],

          SizedBox(height: Responsive.h(10)),
          _note(
            'Samsung and similar phones put unused apps to sleep, which '
            'stops reminders entirely. Settings → Battery → Background '
            'usage limits — make sure AttendX is not in "Sleeping apps".',
            AppColors.textSecondary,
          ),

          SizedBox(height: Responsive.h(14)),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _test,
                  icon: const Icon(Icons.send_rounded, size: 17),
                  label: const Text('Test'),
                ),
              ),
              SizedBox(width: Responsive.w(10)),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _reschedule,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Reschedule'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _note(String text, Color colour) => Container(
        width: double.infinity,
        padding: Responsive.all(11),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(text, style: AppTextStyles.caption),
      );
}
