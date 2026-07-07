class AdminSession {
  final String uid;

  final String name;

  final String role;

  final String department;

  final String academicYear;

  final int year;

  final String section;

  const AdminSession({
    required this.uid,
    required this.name,
    required this.role,
    required this.department,
    required this.academicYear,
    required this.year,
    required this.section,
  });

  bool get isHOD => role == "hod";

  bool get isOffice => role == "office";

  bool get isCR => role == "cr";

  bool get isStudent => role == "student";
}