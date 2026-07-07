class SubjectModel {
  final String id;
  final String name;
  final String code;
  final int year; // 1, 2, 3, or 4
  final String semester; // Odd or Even

  const SubjectModel({
    required this.id,
    required this.name,
    required this.code,
    required this.year,
    required this.semester,
  });

  factory SubjectModel.fromMap(String id, Map<String, dynamic> json) {
    return SubjectModel(
      id: id,
      name: json["name"] ?? "",
      code: json["code"] ?? "",
      year: json["year"] ?? 1,
      semester: json["semester"] ?? "Odd",
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "name": name,
      "code": code,
      "year": year,
      "semester": semester,
    };
  }

  SubjectModel copyWith({
    String? id,
    String? name,
    String? code,
    int? year,
    String? semester,
  }) {
    return SubjectModel(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      year: year ?? this.year,
      semester: semester ?? this.semester,
    );
  }
}
