class FacultyModel {
  final String id;
  final String name;
  final String shortName;
  final String designation;

  /// College staff number.
  ///
  /// Optional, and blank on records created before faculty could sign
  /// in. When present it's what a faculty member types at registration
  /// to claim this record — a stable key that survives the name
  /// spelling changing, which a name match doesn't.
  final String employeeId;

  final bool active;

  const FacultyModel({
    required this.id,
    required this.name,
    required this.shortName,
    required this.designation,
    this.employeeId = '',
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
      employeeId: map['employeeId'] ?? '',
      active: map['active'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'shortName': shortName,
      'designation': designation,
      'employeeId': employeeId,
      'active': active,
    };
  }
}