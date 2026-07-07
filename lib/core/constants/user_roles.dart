class UserModel {
  final String uid;
  final String name;
  final String email;
  final String phone;

  final String department;
  final int year;
  final String section;

  final String role;

  final bool active;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.department,
    required this.year,
    required this.section,
    required this.role,
    required this.active,
  });

  factory UserModel.fromMap(Map<String, dynamic> json) {
    return UserModel(
      uid: json["uid"] ?? "",
      name: json["name"] ?? "",
      email: json["email"] ?? "",
      phone: json["phone"] ?? "",
      department: json["department"] ?? "",
      year: json["year"] ?? 1,
      section: json["section"] ?? "A",
      role: json["role"] ?? "STUDENT",
      active: json["active"] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "uid": uid,
      "name": name,
      "email": email,
      "phone": phone,
      "department": department,
      "year": year,
      "section": section,
      "role": role,
      "active": active,
    };
  }
}

class UserRoles {
  static const student = "student";

  static const cr = "cr";

  static const office = "office";

  static const hod = "hod";
}