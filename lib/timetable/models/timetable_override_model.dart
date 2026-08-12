import 'package:cloud_firestore/cloud_firestore.dart';

/// Types of temporary timetable changes a CR can apply.
class OverrideType {
  OverrideType._();

  static const cancelled = 'cancelled';
  static const replacement = 'replacement';
  static const roomChange = 'room_change';

  /// A class put into a period the year has free.
  ///
  /// Every subject has to fit a fixed number of classes into the term,
  /// and days get lost to holidays, exams and staff absence. The usual
  /// remedy is to hold the missed class in a free period, agreed on the
  /// day. This is that: a one-off class on one date, in a slot the
  /// master timetable leaves empty, at a time the CR types in rather
  /// than picks from the standard grid — because a period borrowed at
  /// short notice rarely lines up with the bells.
  static const extraClass = 'extra_class';

  static String label(String type) {
    switch (type) {
      case cancelled:
        return 'CANCELLED';
      case replacement:
        return 'REPLACEMENT';
      case roomChange:
        return 'ROOM CHANGE';
      case extraClass:
        return 'EXTRA CLASS';
      default:
        return type.toUpperCase();
    }
  }
}

/// A temporary, date-specific change layered on top of the master timetable.
/// One override per (department, academicYear, year, date, periodNo).
class TimetableOverride {
  final String id;
  final String department;
  final String academicYear;
  final int year;

  /// yyyy-MM-dd
  final String date;

  /// Monday..Saturday
  final String day;

  final int periodNo;
  final String startTime;
  final String endTime;

  /// OverrideType.*
  final String type;

  final String originalSubject;
  final String originalFacultyName;
  final String originalRoom;

  final String newSubject;
  final String newFacultyName;
  final String newRoom;

  /// Lab batch the period belongs to ('A', 'B', ...). Empty = whole class.
  /// Notifications go to all students of the year with the batch specified
  /// in the message.
  final String batch;

  /// 'Theory' or 'Lab'. Only meaningful for [OverrideType.extraClass],
  /// where there is no master period to inherit it from — and it has to
  /// be right, because it decides whether the class is worth
  /// ClassWeight.lab or ClassWeight.theory.
  final String classType;

  final String note;

  final String createdBy;
  final String createdByName;
  final Timestamp? createdAt;

  const TimetableOverride({
    required this.id,
    required this.department,
    required this.academicYear,
    required this.year,
    required this.date,
    required this.day,
    required this.periodNo,
    required this.startTime,
    required this.endTime,
    required this.type,
    required this.originalSubject,
    required this.originalFacultyName,
    required this.originalRoom,
    this.newSubject = '',
    this.newFacultyName = '',
    this.newRoom = '',
    this.batch = '',
    this.classType = 'Theory',
    this.note = '',
    required this.createdBy,
    required this.createdByName,
    this.createdAt,
  });

  /// Deterministic id: one override per period per date.
  static String buildId({
    required String department,
    required String academicYear,
    required int year,
    required String date,
    required int periodNo,
  }) {
    return '${department}_${academicYear}_${year}_${date}_$periodNo';
  }

  factory TimetableOverride.fromFirestore(DocumentSnapshot doc) {
    final json = doc.data() as Map<String, dynamic>;

    return TimetableOverride(
      id: doc.id,
      department: json['department'] ?? '',
      academicYear: json['academicYear'] ?? '',
      year: json['year'] ?? 1,
      date: json['date'] ?? '',
      day: json['day'] ?? '',
      periodNo: json['periodNo'] ?? 0,
      startTime: json['startTime'] ?? '',
      endTime: json['endTime'] ?? '',
      type: json['type'] ?? OverrideType.cancelled,
      originalSubject: json['originalSubject'] ?? '',
      originalFacultyName: json['originalFacultyName'] ?? '',
      originalRoom: json['originalRoom'] ?? '',
      newSubject: json['newSubject'] ?? '',
      newFacultyName: json['newFacultyName'] ?? '',
      newRoom: json['newRoom'] ?? '',
      batch: json['batch'] ?? '',
      classType: json['classType'] ?? 'Theory',
      note: json['note'] ?? '',
      createdBy: json['createdBy'] ?? '',
      createdByName: json['createdByName'] ?? '',
      createdAt: json['createdAt'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'department': department,
      'academicYear': academicYear,
      'year': year,
      'date': date,
      'day': day,
      'periodNo': periodNo,
      'startTime': startTime,
      'endTime': endTime,
      'type': type,
      'originalSubject': originalSubject,
      'originalFacultyName': originalFacultyName,
      'originalRoom': originalRoom,
      'newSubject': newSubject,
      'newFacultyName': newFacultyName,
      'newRoom': newRoom,
      'batch': batch,
      'classType': classType,
      'note': note,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// " (Batch A)" suffix when the period is batch-specific.
  String get _batchTag => batch.isEmpty ? '' : ' (Batch $batch)';

  /// Human readable summary used in notifications.
  String notificationTitle() {
    switch (type) {
      case OverrideType.cancelled:
        return 'Class Cancelled: $originalSubject$_batchTag';
      case OverrideType.replacement:
        return 'Replacement Class: $newSubject$_batchTag';
      case OverrideType.roomChange:
        return 'Room Changed: $originalSubject$_batchTag';
      default:
        return 'Timetable Update';
    }
  }

  String notificationBody() {
    final slot = '$startTime - $endTime on $date';
    final batchInfo =
        batch.isEmpty ? '' : ' This applies to Batch $batch only.';
    final extra =
        '$batchInfo${note.isEmpty ? '' : '\nNote: $note'}';

    switch (type) {
      case OverrideType.cancelled:
        return '$originalSubject ($slot) has been cancelled.$extra';
      case OverrideType.replacement:
        final faculty =
            newFacultyName.isEmpty ? '' : ' by $newFacultyName';
        final room = newRoom.isEmpty ? originalRoom : newRoom;
        return '$newSubject$faculty replaces $originalSubject ($slot) in $room.$extra';
      case OverrideType.roomChange:
        return '$originalSubject ($slot) moved from $originalRoom to $newRoom.$extra';
      default:
        return 'Timetable updated for $slot.$extra';
    }
  }
}
