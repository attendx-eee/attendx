import 'package:cloud_firestore/cloud_firestore.dart';

/// How a period's attendance was arrived at.
class PeriodAttendanceMethod {
  PeriodAttendanceMethod._();

  /// Camera scan, then confirmed by the faculty member.
  static const scan = 'scan';

  /// Ticked entirely by hand.
  static const manual = 'manual';

  static String label(String method) =>
      method == scan ? 'Camera scan' : 'Marked by hand';
}

/// Attendance for one class period.
///
/// Kept apart from the Pi's `attendance_events`, which answer a
/// different question: the gate knows a student entered the building,
/// this knows they were in the room when the subject was taught. A
/// student can easily do the first without the second, and collapsing
/// the two would quietly destroy the distinction — so neither collection
/// writes to the other.
///
/// One document per class period:
/// `{department}_{year}_{date}_{periodNo}`.
class PeriodAttendance {
  final String id;

  final String department;
  final int year;

  /// yyyy-MM-dd
  final String date;

  final int periodNo;
  final String startTime;
  final String endTime;

  final String subject;

  /// Lab batch, empty for a whole-class period.
  final String batch;

  final String facultyId;
  final String facultyName;

  /// Student uids present. Absent is derived — everyone enrolled in the
  /// year who isn't in here — rather than stored, so a student who joins
  /// the class next week doesn't retroactively appear absent for periods
  /// that happened before they existed.
  final List<String> presentUids;

  /// Of [presentUids], the ones the camera found on its own. The rest
  /// were added by the faculty member during review. Kept so the scan's
  /// real hit rate can be measured against a human's correction, which
  /// is the only honest way to know whether it's working.
  final List<String> recognisedUids;

  /// PeriodAttendanceMethod.*
  final String method;

  final String markedBy;
  final String markedByName;
  final Timestamp? markedAt;

  const PeriodAttendance({
    required this.id,
    required this.department,
    required this.year,
    required this.date,
    required this.periodNo,
    required this.startTime,
    required this.endTime,
    required this.subject,
    this.batch = '',
    required this.facultyId,
    required this.facultyName,
    required this.presentUids,
    this.recognisedUids = const [],
    required this.method,
    required this.markedBy,
    required this.markedByName,
    this.markedAt,
  });

  static String buildId({
    required String department,
    required int year,
    required String date,
    required int periodNo,
  }) =>
      '${department}_${year}_${date}_$periodNo';

  factory PeriodAttendance.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final json = doc.data() ?? const <String, dynamic>{};

    return PeriodAttendance(
      id: doc.id,
      department: json['department'] ?? '',
      year: (json['year'] as num?)?.toInt() ?? 1,
      date: json['date'] ?? '',
      periodNo: (json['periodNo'] as num?)?.toInt() ?? 0,
      startTime: json['startTime'] ?? '',
      endTime: json['endTime'] ?? '',
      subject: json['subject'] ?? '',
      batch: json['batch'] ?? '',
      facultyId: json['facultyId'] ?? '',
      facultyName: json['facultyName'] ?? '',
      presentUids: List<String>.from(json['presentUids'] ?? const []),
      recognisedUids:
          List<String>.from(json['recognisedUids'] ?? const []),
      method: json['method'] ?? PeriodAttendanceMethod.manual,
      markedBy: json['markedBy'] ?? '',
      markedByName: json['markedByName'] ?? '',
      markedAt: json['markedAt'] is Timestamp ? json['markedAt'] : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'department': department,
        'year': year,
        'date': date,
        // Denormalised so a student's "my attendance this month" read is
        // one query instead of one per day.
        'month': date.length >= 7 ? date.substring(0, 7) : date,
        'periodNo': periodNo,
        'startTime': startTime,
        'endTime': endTime,
        'subject': subject,
        'batch': batch,
        'facultyId': facultyId,
        'facultyName': facultyName,
        'presentUids': presentUids,
        'recognisedUids': recognisedUids,
        'presentCount': presentUids.length,
        'method': method,
        'markedBy': markedBy,
        'markedByName': markedByName,
        'markedAt': FieldValue.serverTimestamp(),
      };

  bool wasPresent(String uid) => presentUids.contains(uid);

  /// How many of the present students the camera found unaided.
  int get recognisedCount =>
      recognisedUids.where(presentUids.contains).length;

  /// Added by the faculty member because the camera missed them.
  int get correctedCount => presentUids.length - recognisedCount;
}
