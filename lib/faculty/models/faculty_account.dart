import 'package:cloud_firestore/cloud_firestore.dart';

/// A teaching staff member's login account.
///
/// Deliberately separate from [FacultyModel], the record an admin
/// creates in Master Data. That one is a *name on a timetable* — it
/// exists so a period can say who teaches it, and it's created long
/// before (or without) that person ever installing the app. This is the
/// person's own account: their credentials, their contact details, and
/// the link back to the timetable record.
///
/// Keeping them apart means a faculty member leaving doesn't orphan
/// every period they ever taught, and a timetable can be built for staff
/// who have never signed in.
class FacultyAccount {
  final String uid;


  /// Document id in the `faculty` collection this account is tied to.
  ///
  /// Empty until an admin approves the account and picks which timetable
  /// record it belongs to. That link is what makes "my classes" work —
  /// periods name a facultyId, not a person — so an unapproved account
  /// has no classes to show and nothing it could mark.
  final String facultyId;

  /// 'pending' | 'approved' | 'rejected'
  final String status;

  /// Admin's note when rejecting.
  final String decisionNote;

  final String name;

  /// Initials as they appear on the timetable ("KRS").
  final String shortName;

  /// Professor, Associate Professor, Assistant Professor, Lecturer...
  final String designation;

  /// Short code — 'EEE'.
  final String department;

  /// Highest qualification: Ph.D., M.Tech, M.E., M.Sc.
  final String qualification;

  /// Years of teaching experience. Not used by any logic — kept because
  /// it's on every staff record a college keeps, and asking for it later
  /// means chasing everyone again.
  final int experienceYears;

  final String email;
  final String mobile;

  final bool active;

  final Timestamp? createdAt;

  static const String pending = 'pending';
  static const String approved = 'approved';
  static const String rejected = 'rejected';

  const FacultyAccount({
    required this.uid,
    this.facultyId = '',
    this.status = pending,
    this.decisionNote = '',
    required this.name,
    required this.shortName,
    required this.designation,
    required this.department,
    required this.qualification,
    this.experienceYears = 0,
    required this.email,
    required this.mobile,
    this.active = true,
    this.createdAt,
  });

  /// The designations a college hierarchy actually uses, most senior
  /// first — offered as a dropdown so the timetable doesn't end up with
  /// "Asst. Prof", "Assistant Professor" and "AP" all meaning one thing.
  static const List<String> designations = [
    'Professor',
    'Associate Professor',
    'Assistant Professor',
    'Lecturer',
    'Visiting Faculty',
    'Lab Instructor',
  ];

  static const List<String> qualifications = [
    'Ph.D.',
    'M.Tech',
    'M.E.',
    'M.Sc.',
    'MCA',
    'B.Tech',
    'Other',
  ];

  factory FacultyAccount.fromMap(String uid, Map<String, dynamic> map) {
    return FacultyAccount(
      uid: uid,
      facultyId: (map['facultyId'] ?? '').toString(),
      status: (map['facultyStatus'] ?? pending).toString(),
      decisionNote: (map['decisionNote'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      shortName: (map['shortName'] ?? '').toString(),
      designation: (map['designation'] ?? '').toString(),
      department: (map['department'] ?? '').toString(),
      qualification: (map['qualification'] ?? '').toString(),
      experienceYears: (map['experienceYears'] as num?)?.toInt() ?? 0,
      email: (map['email'] ?? '').toString(),
      mobile: (map['mobile'] ?? '').toString(),
      active: map['active'] ?? true,
      createdAt: map['createdAt'] is Timestamp ? map['createdAt'] : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'facultyId': facultyId,
        // Named `facultyStatus` rather than `status`. It predates the
        // move to `faculty_accounts`, when these docs shared `students`
        // and `status` was already spoken for — kept as-is because the
        // security rules and every existing document use this name.
        'facultyStatus': status,
        'decisionNote': decisionNote,
        'name': name,
        'shortName': shortName,
        'designation': designation,
        'department': department,
        'qualification': qualification,
        'experienceYears': experienceYears,
        'email': email,
        'mobile': mobile,
        'active': active,
        // Redundant now that the collection itself says what these are,
        // but kept so records that haven't been migrated out of
        // `students` still resolve to the right role.
        'role': 'faculty',
        'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      };

  bool get isApproved => status == approved && facultyId.isNotEmpty;
  bool get isPending => status == pending;
  bool get isRejected => status == rejected;
}
