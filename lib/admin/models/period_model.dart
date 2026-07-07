class PeriodModel {
  final int periodNo;
  final String startTime;
  final String endTime;

  final String subject;
  final String facultyId;
  final String facultyName;
  final String room;
  final String classType;

  /// Lab batch this period applies to ('A', 'B', ...). Empty = whole class.
  final String batch;

  final bool isFree;

  /// draft
  /// pending
  /// approved
  /// rejected
  final String status;

  const PeriodModel({
    required this.periodNo,
    required this.startTime,
    required this.endTime,
    required this.subject,
    required this.facultyId,
    required this.facultyName,
    required this.room,
    required this.classType,
    this.batch = '',
    required this.isFree,
    required this.status,
  });

  factory PeriodModel.fromMap(Map<String, dynamic> json) {
    return PeriodModel(
      periodNo: json["periodNo"] ?? 0,
      startTime: json["startTime"] ?? "",
      endTime: json["endTime"] ?? "",
      subject: json["subject"] ?? "",
      facultyId: json["facultyId"] ?? "",
      facultyName: json["facultyName"] ?? "",
      room: json["room"] ?? "",
      classType: json["classType"] ?? json["type"] ?? "Theory",
      batch: json["batch"] ?? "",
      isFree: json["isFree"] ?? true,
      status: json["status"] ?? "draft",
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "periodNo": periodNo,
      "startTime": startTime,
      "endTime": endTime,
      "subject": subject,
      "facultyId": facultyId,
      "facultyName": facultyName,
      "room": room,
      "classType": classType,
      "batch": batch,
      "isFree": isFree,
      "status": status,
    };
  }

  PeriodModel copyWith({
    int? periodNo,
    String? startTime,
    String? endTime,
    String? subject,
    String? facultyId,
    String? facultyName,
    String? room,
    String? classType,
    String? batch,
    bool? isFree,
    String? status,
  }) {
    return PeriodModel(
      periodNo: periodNo ?? this.periodNo,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      subject: subject ?? this.subject,
      facultyId: facultyId ?? this.facultyId,
      facultyName: facultyName ?? this.facultyName,
      room: room ?? this.room,
      classType: classType ?? this.classType,
      batch: batch ?? this.batch,
      isFree: isFree ?? this.isFree,
      status: status ?? this.status,
    );
  }
}
