class UserModel {
  final String uid;
  final String name;
  final String email;
  final String role;
  final String department;
  final int year;
  final int semester;
  final String section;
  final String? regNo;
  final bool isActive;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.department,
    required this.year,
    required this.semester,
    required this.section,
    this.regNo,
    required this.isActive,
  });

  factory UserModel.fromFirestore(Map<String, dynamic> json) {
    return UserModel(
      uid: json["uid"] ?? "",
      name: json["name"] ?? "",
      email: json["email"] ?? "",
      role: json["role"] ?? "student",
      department: json["department"] ?? "",
      year: json["year"] ?? 1,
      semester: json["semester"] ?? 1,
      section: json["section"] ?? "",
      regNo: json["regNo"],
      isActive: json["isActive"] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      "uid": uid,
      "name": name,
      "email": email,
      "role": role,
      "department": department,
      "year": year,
      "semester": semester,
      "section": section,
      "regNo": regNo,
      "isActive": isActive,
    };
  }
}