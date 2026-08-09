import 'package:cloud_firestore/cloud_firestore.dart';

/// Why a day isn't a working day.
class HolidayType {
  HolidayType._();

  /// Declared by the state or the university — Sankranti, Republic Day.
  static const public = 'public';

  /// Closed for a university reason — exams, semester break, sports day.
  static const institutional = 'institutional';

  /// Called at short notice — cyclone, strike, local bandh.
  static const unscheduled = 'unscheduled';

  static String label(String type) => switch (type) {
        public => 'Public holiday',
        institutional => 'College holiday',
        unscheduled => 'Unscheduled',
        _ => type,
      };
}

/// A non-working day.
///
/// Sundays and second Saturdays are deliberately **not** stored here —
/// they're a rule, not data, and seeding four years of them would be
/// both wasteful and something to maintain. See [HolidayCalendar].
class Holiday {
  /// yyyy-MM-dd — also the document id, which makes a date lookup a
  /// single get and makes double-entry impossible.
  final String date;

  final String name;

  /// The human explanation shown on the calendar: "Sankranti", "Second
  /// Saturday", "Semester break".
  final String reason;

  /// HolidayType.*
  final String type;

  /// Optional — when a holiday only applies to some years.
  /// Empty means the whole department.
  final List<int> years;

  final Timestamp? createdAt;

  const Holiday({
    required this.date,
    required this.name,
    this.reason = '',
    this.type = HolidayType.public,
    this.years = const [],
    this.createdAt,
  });

  factory Holiday.fromMap(String date, Map<String, dynamic> map) {
    return Holiday(
      date: date,
      name: (map['name'] ?? '').toString(),
      reason: (map['reason'] ?? '').toString(),
      type: (map['type'] ?? HolidayType.public).toString(),
      years: (map['years'] as List?)?.map((e) => (e as num).toInt()).toList() ??
          const [],
      createdAt: map['createdAt'] is Timestamp ? map['createdAt'] : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'date': date,
        'name': name,
        'reason': reason,
        'type': type,
        'years': years,
        'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      };

  bool appliesTo(int year) => years.isEmpty || years.contains(year);
}

/// Works out whether a date is a working day.
class HolidayCalendar {
  HolidayCalendar._();

  /// Whether [date] is the second Saturday of its month.
  ///
  /// Andhra Pradesh government offices — and the university with them —
  /// close on every Sunday and every second Saturday. Computed rather
  /// than stored: it's the same rule every month forever, and a stored
  /// version would be a list somebody has to remember to extend.
  static bool isSecondSaturday(DateTime date) {
    if (date.weekday != DateTime.saturday) return false;
    // Days 8-14 contain exactly one of each weekday, so the Saturday in
    // that window is by definition the second one.
    return date.day >= 8 && date.day <= 14;
  }

  static bool isSunday(DateTime date) => date.weekday == DateTime.sunday;

  /// The stock reason for a weekly closure, or null if it's a normal day.
  static String? weeklyClosureReason(DateTime date) {
    if (isSunday(date)) return 'Sunday';
    if (isSecondSaturday(date)) return 'Second Saturday';
    return null;
  }
}

/// A block of consecutive closed days — a vacation.
///
/// Stored expanded into one document per date rather than as a range.
/// The alternative is that every "is this day closed" check has to test
/// membership of every range, and that check runs per student per day
/// across a whole semester. One document per date makes it a map lookup.
class HolidayRange {
  final String from;
  final String to;
  final String name;
  final String reason;
  final String type;

  const HolidayRange({
    required this.from,
    required this.to,
    required this.name,
    this.reason = '',
    this.type = HolidayType.institutional,
  });

  /// Every date in the range, inclusive.
  List<Holiday> expand() {
    final start = DateTime.tryParse(from);
    final end = DateTime.tryParse(to);
    if (start == null || end == null || end.isBefore(start)) return const [];

    final out = <Holiday>[];
    for (var d = start;
        !d.isAfter(end);
        d = DateTime(d.year, d.month, d.day + 1)) {
      final id = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      out.add(Holiday(date: id, name: name, reason: reason, type: type));
    }
    return out;
  }
}

/// Seed holidays for AU College of Engineering, AY 2026-27.
///
/// The vacation blocks and semester dates are taken from the official
/// academic calendar (Note for Orders, AY 2026-2027) — not guessed, and
/// not the state list. Where the two disagree, this wins: a state
/// holiday falling inside a university vacation is already closed, and
/// a university working day isn't made a holiday by the state list.
///
/// Still worth checking two things by hand:
/// - Moon-dependent dates (Ramzan, Bakrid, Moharram, Milad-un-Nabi)
///   are announced close to the day and move.
/// - Ugadi 2027 and other second-half festivals aren't listed here,
///   because most of that stretch falls inside the Christmas/Pongal and
///   Summer vacations and the rest wasn't on the calendar image.
class SeedHolidays {
  SeedHolidays._();

  /// Vacations, straight off the academic calendar.
  static const List<HolidayRange> auVacations2026 = [
    HolidayRange(
      from: '2026-10-15',
      to: '2026-10-21',
      name: 'Dussehra Vacation',
      reason: 'University vacation',
    ),
    HolidayRange(
      from: '2026-12-24',
      to: '2027-01-17',
      name: 'Christmas & Pongal Vacation',
      reason: 'University vacation',
    ),
    HolidayRange(
      from: '2027-05-15',
      to: '2027-06-28',
      name: 'Summer Vacation',
      reason: 'University vacation',
    ),
  ];

  /// Single-day closures falling on working days of this academic year,
  /// each with the occasion named so the calendar explains itself.
  ///
  /// Festivals inside a vacation block are deliberately left out —
  /// Sankranti, for instance, sits inside the Christmas/Pongal break and
  /// would only be a duplicate entry.
  ///
  /// Everything here is editable. A date the university decides to work
  /// through can be deleted, and one it closes at short notice can be
  /// added from the Holidays screen or straight from a student's
  /// calendar.
  static const List<Holiday> auSingleDays2026 = [
    Holiday(
        date: '2026-08-15',
        name: 'Independence Day',
        reason: 'National holiday'),
    Holiday(
        date: '2026-08-26',
        name: 'Eid Milad-un-Nabi',
        reason: 'Festival holiday — date subject to moon sighting'),
    Holiday(
        date: '2026-08-28',
        name: 'Raksha Bandhan',
        reason: 'Festival holiday'),
    Holiday(
        date: '2026-09-04',
        name: 'Sri Krishna Janmashtami',
        reason: 'Festival holiday'),
    Holiday(
        date: '2026-09-14',
        name: 'Vinayaka Chavithi',
        reason: 'Ganesh Chaturthi — festival holiday'),
    Holiday(
        date: '2026-10-02',
        name: 'Gandhi Jayanti',
        reason: 'National holiday'),
    Holiday(
        date: '2026-11-08',
        name: 'Deepavali',
        reason: 'Festival of lights'),
    Holiday(
        date: '2026-11-24',
        name: 'Guru Nanak Jayanti',
        reason: 'Festival holiday'),
    // Christmas isn't listed: 25 December sits inside the
    // Christmas/Pongal vacation, as does Sankranti in January.
    Holiday(
        date: '2027-01-26',
        name: 'Republic Day',
        reason: 'National holiday'),
    Holiday(
        date: '2027-02-15',
        name: 'Maha Shivaratri',
        reason: 'Festival holiday'),
    Holiday(
        date: '2027-03-22',
        name: 'Holi',
        reason: 'Festival holiday'),
    Holiday(
        date: '2027-04-08',
        name: 'Ugadi',
        reason: 'Telugu New Year'),
    Holiday(
        date: '2027-04-14',
        name: 'Dr B.R. Ambedkar Jayanti',
        reason: 'National holiday'),
    Holiday(
        date: '2027-04-15',
        name: 'Sri Rama Navami',
        reason: 'Festival holiday'),
    Holiday(
        date: '2027-05-01',
        name: 'May Day',
        reason: 'Labour Day'),
  ];

  /// Everything, ready to write.
  static List<Holiday> get all => [
        ...auSingleDays2026,
        for (final range in auVacations2026) ...range.expand(),
      ];
}

/// Key dates from the academic calendar that aren't holidays.
///
/// Not stored as holidays because classes still run — these drive
/// "semester starts", "mid-sem week" labelling and exam notifications.
class AcademicCalendar2026 {
  AcademicCalendar2026._();

  static const String classworkStart = '2026-06-29';

  /// Closing day of classwork, by B.Tech year.
  static const Map<int, String> classworkEnd = {
    4: '2026-11-03',
    3: '2026-11-03',
    2: '2026-11-10',
    1: '2026-12-23',
  };

  static const String midOneFrom = '2026-09-01';
  static const String midOneTo = '2026-09-03';

  static const String midTwoFrom = '2026-10-29';
  static const String midTwoTo = '2026-10-31';

  /// First day of end-semester exams, by B.Tech year.
  static const Map<int, String> endSemesterStart = {
    4: '2026-11-09',
    3: '2026-11-10',
    2: '2026-11-19',
    1: '2027-01-20',
  };

  /// Working days per month, from the calendar's own table. Useful as a
  /// sanity check: if the app's computed working days for a month differ
  /// wildly from these, the holiday list is wrong.
  static const Map<String, int> workingDays = {
    '2026-06': 2,
    '2026-07': 26,
    '2026-08': 22,
    '2026-09': 23,
    '2026-10': 20,
    '2026-11': 24,
    '2026-12': 19,
    '2027-01': 11,
    '2027-02': 23,
    '2027-03': 23,
    '2027-04': 21,
    '2027-05': 11,
  };

  /// 225 working days across the year, per the calendar.
  static const int totalWorkingDays = 225;
}
