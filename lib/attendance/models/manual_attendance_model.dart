import 'package:cloud_firestore/cloud_firestore.dart';

/// The day-level verdicts a human can set manually.
class ManualAttendanceStatus {
  ManualAttendanceStatus._();

  static const present = 'present';
  static const late = 'late';
  static const absent = 'absent';

  static const all = [present, late, absent];

  static String label(String status) {
    switch (status) {
      case present:
        return 'PRESENT';
      case late:
        return 'LATE';
      case absent:
        return 'ABSENT';
      default:
        return status.toUpperCase();
    }
  }
}

/// A manual attendance mark laid over the Raspberry Pi's check-in events.
///
/// The Pi owns the `attendance_events` collection and clients can never
/// write there (see firestore.rules) — that keeps the raw biometric
/// history tamper-proof. When a face scan is missed (student forgot to
/// scan, camera down, medical leave, on-duty), an admin — or a CR the
/// admin has approved for that month — records the correction here
/// instead. Reads merge this on top of the derived verdict, so the Pi's
/// original record is preserved and every correction carries an audit
/// trail of who made it, when, and why.
///
/// One document per student per day: `{uid}_{yyyy-MM-dd}`.
class ManualAttendance {
  final String id;
  final String uid;

  /// yyyy-MM-dd
  final String date;

  /// yyyy-MM, derived from [date].
  ///
  /// Redundant on the face of it, but a CR's permission is granted per
  /// month, and the security rules have to check the two against each
  /// other on every write. Storing the month as its own field means the
  /// rule can compare it directly instead of slicing the date string.
  final String month;

  final String department;
  final int year;

  /// ManualAttendanceStatus.*
  final String status;

  final String reason;

  final String markedBy;
  final String markedByName;

  /// 'hod' | 'office' | 'cr' — kept so the audit trail survives a later
  /// role change on the marker's own profile.
  final String markedByRole;

  final Timestamp? markedAt;

  const ManualAttendance({
    required this.id,
    required this.uid,
    required this.date,
    required this.month,
    required this.department,
    required this.year,
    required this.status,
    this.reason = '',
    required this.markedBy,
    required this.markedByName,
    required this.markedByRole,
    this.markedAt,
  });

  /// Deterministic id: one manual mark per student per day, so re-marking
  /// the same day overwrites rather than piling up duplicates.
  static String buildId(String uid, String date) => '${uid}_$date';

  /// "2026-08" from "2026-08-14".
  static String monthOf(String date) =>
      date.length >= 7 ? date.substring(0, 7) : date;

  factory ManualAttendance.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final json = doc.data() ?? const <String, dynamic>{};

    return ManualAttendance(
      id: doc.id,
      uid: json['uid'] ?? '',
      date: json['date'] ?? '',
      month: json['month'] ?? monthOf(json['date'] ?? ''),
      department: json['department'] ?? '',
      year: json['year'] ?? 1,
      status: json['status'] ?? ManualAttendanceStatus.present,
      reason: json['reason'] ?? '',
      markedBy: json['markedBy'] ?? '',
      markedByName: json['markedByName'] ?? '',
      markedByRole: json['markedByRole'] ?? '',
      markedAt: json['markedAt'] is Timestamp ? json['markedAt'] : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'date': date,
      'month': month,
      'department': department,
      'year': year,
      'status': status,
      'reason': reason,
      'markedBy': markedBy,
      'markedByName': markedByName,
      'markedByRole': markedByRole,
      'markedAt': FieldValue.serverTimestamp(),
    };
  }

  bool get isPresent =>
      status == ManualAttendanceStatus.present ||
      status == ManualAttendanceStatus.late;

  bool get isLate => status == ManualAttendanceStatus.late;
}
