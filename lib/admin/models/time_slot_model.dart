class TimeSlotModel {
  final String id;
  final String startTime;
  final String endTime;
  final int slotNumber;
  final bool active;

  const TimeSlotModel({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.slotNumber,
    required this.active,
  });

  factory TimeSlotModel.fromMap(String id, Map<String, dynamic> json) {
    return TimeSlotModel(
      id: id,
      startTime: json["startTime"] ?? "",
      endTime: json["endTime"] ?? "",
      slotNumber: json["slotNumber"] ?? 0,
      active: json["active"] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "startTime": startTime,
      "endTime": endTime,
      "slotNumber": slotNumber,
      "active": active,
    };
  }

  TimeSlotModel copyWith({
    String? id,
    String? startTime,
    String? endTime,
    int? slotNumber,
    bool? active,
  }) {
    return TimeSlotModel(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      slotNumber: slotNumber ?? this.slotNumber,
      active: active ?? this.active,
    );
  }
}
