class RoomModel {
  final String id;
  final String roomNumber;
  final String building;
  final int capacity;
  final String type; // Classroom, Lab, Auditorium
  final bool active;

  const RoomModel({
    required this.id,
    required this.roomNumber,
    required this.building,
    required this.capacity,
    required this.type,
    required this.active,
  });

  factory RoomModel.fromMap(String id, Map<String, dynamic> json) {
    return RoomModel(
      id: id,
      roomNumber: json["roomNumber"] ?? "",
      building: json["building"] ?? "",
      capacity: json["capacity"] ?? 0,
      type: json["type"] ?? "Classroom",
      active: json["active"] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "roomNumber": roomNumber,
      "building": building,
      "capacity": capacity,
      "type": type,
      "active": active,
    };
  }

  RoomModel copyWith({
    String? id,
    String? roomNumber,
    String? building,
    int? capacity,
    String? type,
    bool? active,
  }) {
    return RoomModel(
      id: id ?? this.id,
      roomNumber: roomNumber ?? this.roomNumber,
      building: building ?? this.building,
      capacity: capacity ?? this.capacity,
      type: type ?? this.type,
      active: active ?? this.active,
    );
  }
}
