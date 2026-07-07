import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/period_model.dart';

class TimetableService {
  TimetableService._();

  static final TimetableService instance = TimetableService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _periodCollection({
    required String department,
    required String academicYear,
    required int year,
    required String day,
  }) {
    return _firestore
        .collection("timetables")
        .doc(department)
        .collection(academicYear)
        .doc(year.toString())
        .collection(day);
  }

  Future<bool> timetableExists({
    required String department,
    required String academicYear,
    required int year,
  }) async {
    final snapshot = await _firestore
        .collection("timetables")
        .doc(department)
        .collection(academicYear)
        .doc(year.toString())
        .get();

    return snapshot.exists;
  }

  Future<List<PeriodModel>> getDaySchedule({
    required String department,
    required String academicYear,
    required int year,
    required String day,
  }) async {
    final snapshot = await _periodCollection(
      department: department,
      academicYear: academicYear,
      year: year,
      day: day,
    ).orderBy("periodNo").get();

    return snapshot.docs
        .map((e) => PeriodModel.fromMap(e.data()))
        .toList();
  }

  Future<String> getTimetableStatus({
    required String department,
    required String academicYear,
    required int year,
  }) async {
    final snapshot = await _firestore
        .collection("timetables")
        .doc(department)
        .collection(academicYear)
        .doc(year.toString())
        .get();

    if (snapshot.exists) {
      final data = snapshot.data();
      if (data != null && data.containsKey("status")) {
        return data["status"] as String;
      }
    }

    return "draft";
  }

  Stream<List<PeriodModel>> watchDaySchedule({
    required String department,
    required String academicYear,
    required int year,
    required String day,
  }) {
    return _periodCollection(
      department: department,
      academicYear: academicYear,
      year: year,
      day: day,
    )
        .orderBy("periodNo")
        .snapshots()
        .map((event) =>
            event.docs.map((e) => PeriodModel.fromMap(e.data())).toList());
  }

  Future<void> updatePeriod({
    required String department,
    required String academicYear,
    required int year,
    required String day,
    required PeriodModel period,
  }) async {
    await _periodCollection(
      department: department,
      academicYear: academicYear,
      year: year,
      day: day,
    )
        .doc(period.periodNo.toString())
        .set(period.toMap());
  }

  Future<void> deletePeriod({
    required String department,
    required String academicYear,
    required int year,
    required String day,
    required int periodNo,
  }) async {
    await _periodCollection(
      department: department,
      academicYear: academicYear,
      year: year,
      day: day,
    )
        .doc(periodNo.toString())
        .delete();
  }

  Future<void> submitForApproval({
    required String department,
    required String academicYear,
    required int year,
  }) async {
    await _firestore
        .collection("timetables")
        .doc(department)
        .collection(academicYear)
        .doc(year.toString())
        .set({
      "status": "pending",
      "submittedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> approve({
    required String department,
    required String academicYear,
    required int year,
  }) async {
    await _firestore
        .collection("timetables")
        .doc(department)
        .collection(academicYear)
        .doc(year.toString())
        .update({
      "status": "approved",
      "approvedAt": FieldValue.serverTimestamp(),
    });
  }

  Future<void> reject({
    required String department,
    required String academicYear,
    required int year,
    required String reason,
  }) async {
    await _firestore
        .collection("timetables")
        .doc(department)
        .collection(academicYear)
        .doc(year.toString())
        .update({
      "status": "rejected",
      "reason": reason,
    });
  }


Future<void> createBlankWeek({
  required String department,
  required String academicYear,
  required int year,
}) async {
  const days = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
  ];

  const periods = [
  ["09:00","10:40"],
  ["10:50","12:30"],
  ["13:30","15:10"],
  ["15:20","17:00"],
];

 for(final day in days){

   for(int i=0;i<periods.length;i++){

      final model = PeriodModel(
        periodNo: i + 1,
        startTime: periods[i][0],
        endTime: periods[i][1],
        subject: "",
        facultyId: "",
        facultyName: "",
        room: "",
        classType: "Theory",
        isFree: true,
        status: "draft",
      );

      await updatePeriod(
          department:department,
          academicYear:academicYear,
          year:year,
          day:day,
          period:model,
      );

   }

}
}
}