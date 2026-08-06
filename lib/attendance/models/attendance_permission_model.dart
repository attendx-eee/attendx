import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle of a CR's request to mark attendance for one month.
class PermissionStatus {
  PermissionStatus._();

  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';
  static const revoked = 'revoked';

  static String label(String status) {
    switch (status) {
      case pending:
        return 'AWAITING APPROVAL';
      case approved:
        return 'APPROVED';
      case rejected:
        return 'REJECTED';
      case revoked:
        return 'REVOKED';
      default:
        return status.toUpperCase();
    }
  }
}

/// A CR's permission to mark attendance for their own year, scoped to a
/// single month.
///
/// Marking attendance is an admin power, so a CR never gets it standing —
/// they raise a request for a specific month, the admin approves it, and
/// the grant dies with that month. Scoping to a month (rather than
/// granting it outright) keeps the blast radius small: a CR can fix the
/// stretch of days they actually know about, and the admin sees a fresh
/// request the next month rather than an old permission nobody remembers
/// issuing.
///
/// One document per (CR, department, year, month): `{uid}_{yyyy-MM}`.
class AttendancePermission {
  final String id;
  final String crUid;
  final String crName;

  final String department;
  final int year;

  /// yyyy-MM — the month this grant covers.
  final String month;

  /// PermissionStatus.*
  final String status;

  /// Why the CR needs it (shown to the admin on the approval card).
  final String requestNote;

  /// Admin's note when rejecting/revoking.
  final String decisionNote;

  final String decidedBy;
  final Timestamp? requestedAt;
  final Timestamp? decidedAt;

  const AttendancePermission({
    required this.id,
    required this.crUid,
    required this.crName,
    required this.department,
    required this.year,
    required this.month,
    required this.status,
    this.requestNote = '',
    this.decisionNote = '',
    this.decidedBy = '',
    this.requestedAt,
    this.decidedAt,
  });

  /// One request per CR per month — re-requesting reuses the same doc.
  static String buildId(String crUid, String month) => '${crUid}_$month';

  /// "2026-08" for a date.
  static String monthId(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  /// "August 2026" — for request cards and dialogs.
  static String monthLabel(String month) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final parts = month.split('-');
    if (parts.length < 2) return month;
    final m = int.tryParse(parts[1]);
    if (m == null || m < 1 || m > 12) return month;
    return '${names[m - 1]} ${parts[0]}';
  }

  factory AttendancePermission.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final json = doc.data() ?? const <String, dynamic>{};

    return AttendancePermission(
      id: doc.id,
      crUid: json['crUid'] ?? '',
      crName: json['crName'] ?? '',
      department: json['department'] ?? '',
      year: json['year'] ?? 1,
      month: json['month'] ?? '',
      status: json['status'] ?? PermissionStatus.pending,
      requestNote: json['requestNote'] ?? '',
      decisionNote: json['decisionNote'] ?? '',
      decidedBy: json['decidedBy'] ?? '',
      requestedAt: json['requestedAt'] is Timestamp ? json['requestedAt'] : null,
      decidedAt: json['decidedAt'] is Timestamp ? json['decidedAt'] : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'crUid': crUid,
      'crName': crName,
      'department': department,
      'year': year,
      'month': month,
      'status': status,
      'requestNote': requestNote,
      'decisionNote': decisionNote,
      'decidedBy': decidedBy,
      'requestedAt': requestedAt ?? FieldValue.serverTimestamp(),
      'decidedAt': decidedAt,
    };
  }

  bool get isApproved => status == PermissionStatus.approved;
  bool get isPending => status == PermissionStatus.pending;

  String get monthName => monthLabel(month);
}
