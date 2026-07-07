/// Central academic configuration shared by admin, CR and student flows.
class AppConfig {
  AppConfig._();

  static const String department = 'EEE';

  static const String academicYear = '2026-2027';

  // ------------------------------------------------------------------
  // App version + self-update. Bump BOTH numbers together with the
  // `version:` line in pubspec.yaml on every release, then update the
  // Firestore doc `app_meta/android` so installed apps prompt to update:
  //   { latestVersionCode: 2, latestVersion: "1.1.0",
  //     apkUrl: "https://<user>.github.io/<repo>/attendx.apk",
  //     forceUpdate: false, notes: "What's new..." }
  // ------------------------------------------------------------------
  static const int appVersionCode = 2;
  static const String appVersion = '1.1.0';

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
  /// as present (but is flagged as a late check-in).
  static const int presentGraceMinutes = 20;

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
