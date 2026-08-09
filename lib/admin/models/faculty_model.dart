class FacultyModel {
  final String id;
  final String name;
  final String shortName;
  final String designation;


  final bool active;

  const FacultyModel({
    required this.id,
    required this.name,
    required this.shortName,
    required this.designation,
    required this.active,
  });

  factory FacultyModel.fromMap(
    String id,
    Map<String, dynamic> map,
  ) {
    return FacultyModel(
      id: id,
      name: map['name'] ?? '',
      shortName: map['shortName'] ?? '',
      designation: map['designation'] ?? '',
      active: map['active'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'shortName': shortName,
      'designation': designation,
      'active': active,
    };
  }
}