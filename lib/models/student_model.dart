class StudentModel {
  final String uid;
  final String name;
  final String regNo;
  final String department;
  final String semester;
  final String mobile;
  final String email;
  final bool faceEnrolled;

  StudentModel({
    required this.uid,
    required this.name,
    required this.regNo,
    required this.department,
    required this.semester,
    required this.mobile,
    required this.email,
    required this.faceEnrolled,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'regNo': regNo,
      'department': department,
      'semester': semester,
      'mobile': mobile,
      'email': email,
      'faceEnrolled': faceEnrolled,
    };
  }
}