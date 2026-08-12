class SubjectModel {
  final String id;
  final String name;
  final String code;
  final int year; // 1, 2, 3, or 4
  final String semester; // Odd or Even

  /// Classes the syllabus needs before the subject is complete.
  ///
  /// A term is planned around a number like this — the usual figure is
  /// [defaultTarget] for a theory subject — and then days disappear to
  /// holidays, exams and staff absence. Whether the count will actually
  /// be reached is the question this exists to answer, early enough that
  /// extra classes can be arranged rather than discovered as a shortfall
  /// in the last week.
  ///
  /// Not a hard limit. Finishing in fewer is fine, and running a few
  /// over is normal.
  final int targetClasses;

  static const int defaultTarget = 64;

  const SubjectModel({
    required this.id,
    required this.name,
    required this.code,
    required this.year,
    required this.semester,
    this.targetClasses = defaultTarget,
  });

  factory SubjectModel.fromMap(String id, Map<String, dynamic> json) {
    return SubjectModel(
      id: id,
      name: json["name"] ?? "",
      code: json["code"] ?? "",
      year: json["year"] ?? 1,
      semester: json["semester"] ?? "Odd",
      // Subjects created before this field existed fall back to the
      // standard count rather than to zero, which would read as
      // "already complete" everywhere.
      targetClasses: (json["targetClasses"] as num?)?.toInt() ??
          defaultTarget,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "name": name,
      "code": code,
      "year": year,
      "semester": semester,
      "targetClasses": targetClasses,
    };
  }

  SubjectModel copyWith({
    String? id,
    String? name,
    String? code,
    int? year,
    String? semester,
    int? targetClasses,
  }) {
    return SubjectModel(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      year: year ?? this.year,
      semester: semester ?? this.semester,
      targetClasses: targetClasses ?? this.targetClasses,
    );
  }
}

/// How far a subject has got through its planned classes.
class SubjectProgress {
  final String subject;

  /// Registered by somebody — a scan, a CR, or an admin.
  final int held;

  final int target;

  const SubjectProgress({
    required this.subject,
    required this.held,
    required this.target,
  });

  int get remaining => target - held > 0 ? target - held : 0;

  double get fraction => target == 0 ? 0 : (held / target).clamp(0.0, 1.0);

  bool get complete => held >= target;

  /// Ran past the plan. Not a problem in itself — worth showing so the
  /// count doesn't silently look stuck at 100%.
  bool get overrun => held > target;

  /// Whether [remaining] classes can still fit in [collegeDaysLeft]
  /// days, assuming this subject gets at most one class a day.
  ///
  /// The pessimistic assumption on purpose: a subject that needs two a
  /// day to finish is already in trouble, and saying so in October is
  /// worth more than being exactly right in December.
  bool atRisk(int collegeDaysLeft) =>
      !complete && remaining > collegeDaysLeft;
}
