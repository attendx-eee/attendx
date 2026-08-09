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

  /// How long before a class ends to nudge the lecturer to mark it.
  static const int _wrapUpLeadMinutes = 10;

  // Notification id ranges, kept well apart so faculty reminders can
  // never collide with the student ones. Student class reminders use
  // `weekday * 100 + periodNo` (max ~707), so everything below starts
  // clear of that.
  static const int _facultyDigestIdBase = 20000;
  static const int _facultyStartIdBase = 21000;
  static const int _facultyEndIdBase = 22000;

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

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await android?.requestNotificationsPermission();

    // Created up front rather than lazily on first use. A push arriving
    // while the app has never run in the foreground would otherwise
    // reference a channel that doesn't exist yet, and Android drops
    // those silently on API 26+.
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      'realtime_alerts',
      'Realtime Alerts',
      description: 'Attendance changes, timetable updates and announcements',
      importance: Importance.max,
    ));

    await android?.createNotificationChannel(const AndroidNotificationChannel(
      'daily_schedule',
      'Daily Schedule',
      description: 'Morning summary of classes and labs',
      importance: Importance.high,
    ));

    // Android 12 introduced a separate permission for exact alarms, and
    // every schedule below asks for `exactAllowWhileIdle`. Without the
    // grant the plugin throws `exact_alarms_not_permitted` on the very
    // first zonedSchedule call — and because the callers wrap
    // scheduling in a try/catch that only debugPrints, the whole
    // timetable silently fails to schedule and nothing ever fires.
    //
    // Requesting is best-effort: on some OEM builds it opens a settings
    // screen, on others it's granted at install. Either way the result
    // is recorded so the settings screen can say what's wrong.
    try {
      _exactAlarmsAllowed =
          await android?.canScheduleExactNotifications() ?? true;

      if (_exactAlarmsAllowed != true) {
        await android?.requestExactAlarmsPermission();
        _exactAlarmsAllowed =
            await android?.canScheduleExactNotifications() ?? false;
      }
    } catch (e) {
      debugPrint('Exact alarm permission check failed: $e');
      _exactAlarmsAllowed = null;
    }

    _initialized = true;
  }

  /// Null until [init] has run, then whether the OS will let us schedule
  /// exact alarms. Surfaced in settings, because "my notifications don't
  /// work" is otherwise unanswerable from inside the app.
  bool? _exactAlarmsAllowed;

  bool? get exactAlarmsAllowed => _exactAlarmsAllowed;

  bool get isInitialized => _initialized;

  /// Falls back to inexact scheduling when the OS withholds the exact
  /// alarm permission.
  ///
  /// An inexact alarm can drift by several minutes, which is fine for a
  /// 7am digest and tolerable for a ten-minute class warning. Silence is
  /// not fine, and silence is what the exact-only version delivered.
  AndroidScheduleMode get _scheduleMode => _exactAlarmsAllowed == false
      ? AndroidScheduleMode.inexactAllowWhileIdle
      : AndroidScheduleMode.exactAllowWhileIdle;

  /// Everything currently queued with the OS. Used by the settings
  /// screen to prove scheduling actually happened.
  Future<List<PendingNotificationRequest>> pending() async {
    if (kIsWeb) return const [];
    return _plugin.pendingNotificationRequests();
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
          androidScheduleMode: _scheduleMode,
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
        androidScheduleMode: _scheduleMode,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  /// Reminders for the person *teaching* a period, not attending it.
  ///
  /// Different from the student reminders in what they're for. A student
  /// is told a class is coming so they can get there; a lecturer already
  /// knows their own timetable. What they need is a prompt at the moment
  /// there's something to *do* — start the class scan, and close it out
  /// before the room empties.
  ///
  /// Three per period:
  /// - a morning digest of the day's teaching,
  /// - one at the start of each class: take attendance,
  /// - one [_wrapUpLeadMinutes] before the end: last chance, because
  ///   attendance marked after everyone has walked out is guesswork.
  Future<void> scheduleFacultyReminders(
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

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'faculty_classes',
        'My Classes',
        channelDescription:
            'Reminders to take attendance for classes you teach',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    for (final entry in weekSchedule.entries) {
      final weekday = dayNumbers[entry.key];
      if (weekday == null) continue;

      final periods = entry.value
          .where((p) => !p.isFree && p.subject.isNotEmpty)
          .toList();
      if (periods.isEmpty) continue;

      // ---- morning digest of what they're teaching today ----
      final lines = periods
          .map((p) => "${p.startTime}  ${p.subject}"
              "${p.room.isEmpty ? '' : ' • ${p.room}'}")
          .join('\n');

      await _plugin.zonedSchedule(
        _facultyDigestIdBase + weekday,
        "${entry.key}: ${periods.length} class"
        "${periods.length == 1 ? '' : 'es'} to teach",
        "First at ${periods.first.startTime}\n$lines",
        _nextInstanceOf(
          weekday: weekday,
          hour: AppConfig.dailyDigestHour,
          minute: 0,
          leadMinutes: 0,
        ),
        NotificationDetails(
          android: AndroidNotificationDetails(
            'faculty_classes',
            'My Classes',
            channelDescription:
                'Reminders to take attendance for classes you teach',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation:
                BigTextStyleInformation("First at ${periods.first.startTime}\n$lines"),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: _scheduleMode,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );

      for (final period in periods) {
        final start = _parseTime(period.startTime);
        final end = _parseTime(period.endTime);

        // ---- at the bell: take attendance ----
        if (start != null) {
          await _plugin.zonedSchedule(
            _facultyStartIdBase + weekday * 100 + period.periodNo,
            'Take attendance: ${period.subject}',
            'Class has started'
            '${period.room.isEmpty ? '' : ' in ${period.room}'}. '
            'Open AttendX and scan the room.',
            _nextInstanceOf(
              weekday: weekday,
              hour: start.$1,
              minute: start.$2,
              leadMinutes: 0,
            ),
            details,
            androidScheduleMode: _scheduleMode,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          );
        }

        // ---- shortly before the end: last chance ----
        if (end != null) {
          await _plugin.zonedSchedule(
            _facultyEndIdBase + weekday * 100 + period.periodNo,
            'Class ending: ${period.subject}',
            'Ends at ${period.endTime}. Mark attendance now if you '
            'haven\'t — it\'s guesswork once the room empties.',
            _nextInstanceOf(
              weekday: weekday,
              hour: end.$1,
              minute: end.$2,
              leadMinutes: _wrapUpLeadMinutes,
            ),
            details,
            androidScheduleMode: _scheduleMode,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          );
        }
      }
    }
  }

  /// Loads a faculty member's week from the timetable and schedules the
  /// reminders above.
  ///
  /// Their timetable isn't stored per-teacher — it's per year, with a
  /// facultyId on each period — so their week is assembled by reading
  /// all four years and keeping what names them.
  Future<void> bootstrapForFaculty({
    required String uid,
    required String facultyId,
    required String department,
  }) async {
    if (kIsWeb || facultyId.isEmpty) return;

    await init();
    startRealtimeListener(uid);

    try {
      final weekSchedule = <String, List<PeriodModel>>{};

      for (final day in AppConfig.weekDays) {
        final mine = <PeriodModel>[];

        for (var year = 1; year <= 4; year++) {
          final periods = await TimetableService.instance.getDaySchedule(
            department: department,
            academicYear: AppConfig.academicYear,
            year: year,
            day: day,
          );
          mine.addAll(periods.where((p) => p.facultyId == facultyId));
        }

        mine.sort((a, b) => a.startTime.compareTo(b.startTime));
        weekSchedule[day] = mine;
      }

      await scheduleFacultyReminders(weekSchedule);
    } catch (e) {
      debugPrint('Faculty reminder scheduling failed: $e');
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
