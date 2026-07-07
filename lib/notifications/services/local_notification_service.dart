import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../admin/models/period_model.dart';
import '../../admin/services/timetable_service.dart';
import '../../core/constants/app_config.dart';

/// Device-level notifications:
///
/// 1. Daily class reminders - every class in the student's timetable is
///    scheduled as a weekly-repeating local notification that fires a few
///    minutes before the class starts, every day, automatically.
/// 2. Realtime alerts - listens to the Firestore `notifications` collection
///    and pops a device notification the moment a new one arrives
///    (CR timetable changes, admin broadcasts, etc.).
class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _realtimeSub;

  /// Minutes before class start to remind the student.
  static const int reminderLeadMinutes = 10;

  /// Ids < [_classReminderIdCeiling] are reserved for class reminders.
  static const int _classReminderIdCeiling = 10000;

  static const AndroidNotificationDetails _scheduleChannel =
      AndroidNotificationDetails(
    'class_schedule',
    'Class Schedule',
    channelDescription: 'Daily reminders for upcoming classes',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const AndroidNotificationDetails _alertChannel =
      AndroidNotificationDetails(
    'realtime_alerts',
    'Realtime Alerts',
    channelDescription: 'Timetable changes and other instant updates',
    importance: Importance.max,
    priority: Priority.high,
  );

  /// Ids 9900+weekday are reserved for the morning schedule digests.
  static const int _digestIdBase = 9900;

  Future<void> init() async {
    if (_initialized || kIsWeb) return;

    tz_data.initializeTimeZones();
    try {
      final localZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localZone));
    } catch (e) {
      debugPrint('Timezone resolution failed, using default: $e');
    }

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _plugin.initialize(initSettings);

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  /// Immediately shows a device notification.
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    if (kIsWeb || !_initialized) return;

    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: _alertChannel,
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Schedules weekly-repeating reminders for every class in the week's
  /// timetable. Because they repeat weekly, students get their schedule
  /// notifications every day without the app needing to run.
  Future<void> scheduleWeeklyClassReminders(
    Map<String, List<PeriodModel>> weekSchedule,
  ) async {
    if (kIsWeb || !_initialized) return;

    // Clear previously scheduled class reminders.
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if (request.id < _classReminderIdCeiling) {
        await _plugin.cancel(request.id);
      }
    }

    const dayNumbers = {
      'Monday': DateTime.monday,
      'Tuesday': DateTime.tuesday,
      'Wednesday': DateTime.wednesday,
      'Thursday': DateTime.thursday,
      'Friday': DateTime.friday,
      'Saturday': DateTime.saturday,
      'Sunday': DateTime.sunday,
    };

    for (final entry in weekSchedule.entries) {
      final weekday = dayNumbers[entry.key];
      if (weekday == null) continue;

      for (final period in entry.value) {
        if (period.isFree || period.subject.isEmpty) continue;

        final start = _parseTime(period.startTime);
        if (start == null) continue;

        final fireAt = _nextInstanceOf(
          weekday: weekday,
          hour: start.$1,
          minute: start.$2,
          leadMinutes: reminderLeadMinutes,
        );

        final id = weekday * 100 + period.periodNo;
        final room = period.room.isEmpty ? '' : ' in ${period.room}';
        final faculty =
            period.facultyName.isEmpty ? '' : ' by ${period.facultyName}';

        await _plugin.zonedSchedule(
          id,
          'Upcoming: ${period.subject}',
          'Starts at ${period.startTime}$room$faculty.',
          fireAt,
          const NotificationDetails(
            android: _scheduleChannel,
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
    }
  }

  /// Morning digest: one device notification per college day (fires at
  /// [AppConfig.dailyDigestHour], even with the app closed) summarizing
  /// that day's classes and labs so students can plan their day.
  Future<void> scheduleDailyScheduleDigests(
    Map<String, List<PeriodModel>> weekSchedule,
  ) async {
    if (kIsWeb || !_initialized) return;

    const dayNumbers = {
      'Monday': DateTime.monday,
      'Tuesday': DateTime.tuesday,
      'Wednesday': DateTime.wednesday,
      'Thursday': DateTime.thursday,
      'Friday': DateTime.friday,
      'Saturday': DateTime.saturday,
    };

    for (final entry in weekSchedule.entries) {
      final weekday = dayNumbers[entry.key];
      if (weekday == null) continue;

      final periods = entry.value
          .where((p) => !p.isFree && p.subject.isNotEmpty)
          .toList();
      if (periods.isEmpty) continue;

      final labs =
          periods.where((p) => p.classType.toLowerCase() == 'lab').length;

      final title =
          "${entry.key}: ${periods.length} class${periods.length == 1 ? '' : 'es'}"
          "${labs > 0 ? " • $labs lab${labs == 1 ? '' : 's'}" : ""}";

      final lines = periods
          .map((p) => "${p.startTime}  ${p.subject}"
              "${p.batch.isEmpty ? '' : ' (Batch ${p.batch})'}"
              "${p.classType.toLowerCase() == 'lab' ? ' [Lab]' : ''}")
          .join('\n');

      final body = "First class at ${periods.first.startTime}\n$lines";

      final fireAt = _nextInstanceOf(
        weekday: weekday,
        hour: AppConfig.dailyDigestHour,
        minute: 0,
        leadMinutes: 0,
      );

      await _plugin.zonedSchedule(
        _digestIdBase + weekday,
        title,
        body,
        fireAt,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_schedule',
            'Daily Schedule',
            channelDescription: 'Morning summary of classes and labs',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  /// Loads the student's full week timetable and (re)schedules reminders,
  /// then starts the realtime Firestore listener.
  Future<void> bootstrapForStudent({
    required String uid,
    required Map<String, dynamic> studentData,
  }) async {
    if (kIsWeb) return;

    await init();
    startRealtimeListener(uid);

    try {
      final department = AppConfig.departmentOf(studentData);
      final year = AppConfig.yearOf(studentData);

      final weekSchedule = <String, List<PeriodModel>>{};

      for (final day in AppConfig.weekDays) {
        weekSchedule[day] = await TimetableService.instance.getDaySchedule(
          department: department,
          academicYear: AppConfig.academicYear,
          year: year,
          day: day,
        );
      }

      await scheduleWeeklyClassReminders(weekSchedule);
      await scheduleDailyScheduleDigests(weekSchedule);
    } catch (e) {
      debugPrint('Class reminder scheduling failed: $e');
    }
  }

  /// Pops a device notification whenever a new notification document
  /// arrives for this student (e.g. a CR timetable change).
  void startRealtimeListener(String uid) {
    if (kIsWeb) return;

    _realtimeSub?.cancel();

    final listenStart = Timestamp.now();

    // studentUid-only filter: no composite index required.
    _realtimeSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('studentUid', isEqualTo: uid)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;

        final data = change.doc.data();
        if (data == null) continue;

        final createdAt = data['createdAt'];
        if (createdAt is! Timestamp) continue;
        if (createdAt.compareTo(listenStart) <= 0) continue;

        showNow(
          id: _classReminderIdCeiling + (change.doc.id.hashCode % 90000).abs(),
          title: data['title'] ?? 'AttendX',
          body: data['body'] ?? '',
        );
      }
    }, onError: (e) => debugPrint('Realtime notification listener error: $e'));
  }

  Future<void> stop() async {
    await _realtimeSub?.cancel();
    _realtimeSub = null;
  }

  /// "09:05" -> (9, 5)
  (int, int)? _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length < 2) return null;

    final hour = int.tryParse(parts[0].trim());
    final minute = int.tryParse(parts[1].trim().split(' ').first);
    if (hour == null || minute == null) return null;

    return (hour, minute);
  }

  tz.TZDateTime _nextInstanceOf({
    required int weekday,
    required int hour,
    required int minute,
    required int leadMinutes,
  }) {
    final now = tz.TZDateTime.now(tz.local);

    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    ).subtract(Duration(minutes: leadMinutes));

    while (scheduled.weekday != weekday || scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }
}
