/// Central academic configuration shared by admin, CR and student flows.
class AppConfig {
  AppConfig._();

  static const String department = 'EEE';

  static const String academicYear = '2026-2027';

  // ------------------------------------------------------------------
  // App version + self-update. Bump BOTH numbers together with the
  // `version:` line in pubspec.yaml on every release, then update the
  // Firestore doc `app_meta/android` so installed apps prompt to update:
  //   { latestVersionCode: 4, latestVersion: "1.2.1",
  //     apkUrl: "https://`user`.github.io/`repo`/attendx-v1.2.1.apk",
  //     forceUpdate: false, notes: "What's new..." }
  // ------------------------------------------------------------------
  static const int appVersionCode = 5;
  static const String appVersion = '1.2.2';

  static const String appMetaCollection = 'app_meta';
  static const String appMetaDoc = 'android';

  /// Fixed admin account. On the login screen, admins pick "Admin" and
  /// enter only their secret key — the key is this account's password.
  /// Create this account once in Firebase Auth and give its student doc
  /// role "hod" (or "office").
  static const String adminEmail = 'admin@attendx.app';

  // ------------------------------------------------------------------
  // Firestore contract shared with the Raspberry Pi.
  // The Pi writes check-in/check-out events; the app derives attendance
  // from them against the timetable. Keep these names in sync with the
  // Pi code (see PI_INTEGRATION_NOTES.md in the project root).
  // ------------------------------------------------------------------

  /// One document per student per day: `{uid}_{yyyy-MM-dd}`.
  static const String attendanceEventsCollection = 'attendance_events';

  static String attendanceEventDocId(String uid, DateTime date) =>
      '${uid}_${dateId(date)}';

  /// Hour (24h) at which the daily schedule digest notification fires.
  static const int dailyDigestHour = 7;

  /// Check-in within this many minutes after a period starts = on time.
  static const int onTimeGraceMinutes = 10;

  /// Check-in within this many minutes after a period starts still counts
  /// as present (but is flagged as a late check-in). Used for per-period
  /// (subject-wise) attendance only — see [AttendanceService.periodAttended].
  static const int presentGraceMinutes = 20;

  // ------------------------------------------------------------------
  // Fixed wall-clock cutoffs for the daily present/late/absent verdict
  // (see AttendanceService.classifyDay). Unlike the per-period grace
  // above, these are absolute times of day, not relative to the
  // timetable's first period:
  //   checked in at/before 9:15 AM  -> present (on time)
  //   checked in 9:15-9:30 AM       -> present, but marked late
  //   checked in after 9:30 AM      -> absent
  // ------------------------------------------------------------------
  static const int presentCutoffHour = 9;
  static const int presentCutoffMinute = 15;

  static const int lateCutoffHour = 9;
  static const int lateCutoffMinute = 30;

  /// The on-time cutoff (9:15 AM) for a specific date.
  static DateTime presentCutoffOn(DateTime date) => DateTime(
      date.year, date.month, date.day, presentCutoffHour, presentCutoffMinute);

  /// The absent cutoff (9:30 AM) for a specific date — checking in after
  /// this counts as absent even though a check-in event exists.
  static DateTime lateCutoffOn(DateTime date) => DateTime(
      date.year, date.month, date.day, lateCutoffHour, lateCutoffMinute);

  /// "9:15 AM" — for admin-facing labels.
  static String get presentCutoffLabel =>
      _clockLabel(presentCutoffHour, presentCutoffMinute);

  /// "9:30 AM" — for admin-facing labels.
  static String get lateCutoffLabel =>
      _clockLabel(lateCutoffHour, lateCutoffMinute);

  static String _clockLabel(int hour, int minute) {
    final h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final ap = hour >= 12 ? 'PM' : 'AM';
    return '$h:${minute.toString().padLeft(2, '0')} $ap';
  }

  /// Parses "HH:mm" onto a specific date. Returns null if unparseable.
  static DateTime? timeOn(DateTime date, String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0].trim());
    final m = int.tryParse(parts[1].trim().split(' ').first);
    if (h == null || m == null) return null;
    return DateTime(date.year, date.month, date.day, h, m);
  }

  static const List<String> weekDays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  /// Derives the study year (1-4) from a student document.
  /// Prefers an explicit `year` field, falls back to `semester`
  /// (sem 1-2 -> year 1, sem 3-4 -> year 2, ...).
  static int yearOf(Map<String, dynamic> student) {
    final rawYear = student['year'];
    if (rawYear is int && rawYear >= 1 && rawYear <= 4) return rawYear;

    final semester =
        int.tryParse(student['semester']?.toString() ?? '') ?? 1;
    return ((semester + 1) ~/ 2).clamp(1, 4);
  }

  /// Normalizes any department spelling to its short code, so student
  /// docs ("Electrical Engineering") always match timetable paths ("EEE").
  static String normalizeDepartment(String raw) {
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return department;

    if (v.contains('electron') || v == 'ece') return 'ECE';
    if (v.contains('electrical') || v == 'eee') return 'EEE';
    if (v.contains('computer') || v == 'cse') return 'CSE';
    if (v.contains('mechanical') || v == 'mech') return 'MECH';
    if (v.contains('civil')) return 'CIVIL';
    if (v.contains('chemical') || v == 'chem') return 'CHEM';

    return raw.trim().toUpperCase();
  }

  static String departmentOf(Map<String, dynamic> student) {
    return normalizeDepartment(student['department']?.toString() ?? '');
  }

  /// Weekday name for a [DateTime] (Monday..Sunday).
  static String dayName(DateTime date) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[date.weekday - 1];
  }

  /// Canonical date id used across the app: yyyy-MM-dd.
  static String dateId(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }
}
