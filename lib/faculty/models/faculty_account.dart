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

  /// College-issued staff number. The link to the Master Data faculty
  /// record, and what stops someone claiming to teach a class they
  /// don't.
  final String employeeId;

  /// Document id in the `faculty` collection this account claims.
  final String facultyId;

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

  const FacultyAccount({
    required this.uid,
    required this.employeeId,
    required this.facultyId,
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
      employeeId: (map['employeeId'] ?? '').toString(),
      facultyId: (map['facultyId'] ?? '').toString(),
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
        'employeeId': employeeId,
        'facultyId': facultyId,
        'name': name,
        'shortName': shortName,
        'designation': designation,
        'department': department,
        'qualification': qualification,
        'experienceYears': experienceYears,
        'email': email,
        'mobile': mobile,
        'active': active,
        // Faculty accounts live in `students` alongside everyone else so
        // one role lookup answers "who is this" for every screen in the
        // app. The role field is what separates them.
        'role': 'faculty',
        'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      };
}
