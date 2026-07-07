import 'period_model.dart';

class TimetableModel {
  final String id;

  final String department;

  final String academicYear;

  final int year;

  final String semester;

  final String section;

  /// draft
  /// pending
  /// approved
  /// rejected
  final String status;

  /// `Monday -> List<PeriodModel>`
  /// `Tuesday -> List<PeriodModel>`
  final Map<String, List<PeriodModel>> periods;

  const TimetableModel({
    required this.id,
    required this.department,
    required this.academicYear,
    required this.year,
    required this.semester,
    required this.section,
    required this.status,
    required this.periods,
  });

  factory TimetableModel.empty({
    required String department,
    required String academicYear,
    required int year,
    required String semester,
    required String section,
  }) {
    return TimetableModel(
      id: "",
      department: department,
      academicYear: academicYear,
      year: year,
      semester: semester,
      section: section,
      status: "draft",
      periods: {
        "Monday": [],
        "Tuesday": [],
        "Wednesday": [],
        "Thursday": [],
        "Friday": [],
        "Saturday": [],
      },
    );
  }

  factory TimetableModel.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
    final Map<String, List<PeriodModel>> schedule = {};

    const days = [
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday",
    ];

    for (final day in days) {
      final list = data[day] as List<dynamic>? ?? [];

      schedule[day] = list
          .map(
            (e) => PeriodModel.fromMap(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList()
        ..sort(
          (a, b) => a.periodNo.compareTo(b.periodNo),
        );
    }

    return TimetableModel(
      id: id,
      department: data["department"] ?? "",
      academicYear: data["academicYear"] ?? "",
      year: data["year"] ?? 1,
      semester: data["semester"] ?? "1",
      section: data["section"] ?? "A",
      status: data["status"] ?? "draft",
      periods: schedule,
    );
  }

  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      "department": department,
      "academicYear": academicYear,
      "year": year,
      "semester": semester,
      "section": section,
      "status": status,
    };

    periods.forEach((day, value) {
      map[day] = value.map((e) => e.toMap()).toList();
    });

    return map;
  }

  List<PeriodModel> getDay(String day) {
    return periods[day] ?? [];
  }

  TimetableModel copyWith({
    String? id,
    String? department,
    String? academicYear,
    int? year,
    String? semester,
    String? section,
    String? status,
    Map<String, List<PeriodModel>>? periods,
  }) {
    return TimetableModel(
      id: id ?? this.id,
      department: department ?? this.department,
      academicYear: academicYear ?? this.academicYear,
      year: year ?? this.year,
      semester: semester ?? this.semester,
      section: section ?? this.section,
      status: status ?? this.status,
      periods: periods ?? this.periods,
    );
  }
}