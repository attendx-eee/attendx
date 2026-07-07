import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/faculty_model.dart';
import '../models/subject_model.dart';
import '../models/lab_model.dart';
import '../models/room_model.dart';
import '../models/time_slot_model.dart';

class MasterDataService {
  MasterDataService._();

  static final MasterDataService instance = MasterDataService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// ------------------------------
  /// Collections
  /// ------------------------------

  CollectionReference<Map<String, dynamic>> get facultyCollection =>
      _firestore.collection('faculty');

  CollectionReference<Map<String, dynamic>> get subjectCollection =>
      _firestore.collection('subjects');

  CollectionReference<Map<String, dynamic>> get roomCollection =>
      _firestore.collection('rooms');

  CollectionReference<Map<String, dynamic>> get labCollection =>
      _firestore.collection('labs');

  CollectionReference<Map<String, dynamic>> get timeSlotCollection =>
      _firestore.collection('time_slots');

  /// ==============================
  /// FACULTY
  /// ==============================

  Stream<List<FacultyModel>> getFaculty() {
    return facultyCollection.snapshots().map(
      (snapshot) => snapshot.docs
          .map(
            (doc) => FacultyModel.fromMap(
              doc.id,
              doc.data(),
            ),
          )
          .toList(),
    );
  }

  Future<void> addFaculty(FacultyModel faculty) async {
    await facultyCollection.add(faculty.toMap());
  }

  Future<void> updateFaculty(FacultyModel faculty) async {
    await facultyCollection
        .doc(faculty.id)
        .update(faculty.toMap());
  }

  Future<void> deleteFaculty(String id) async {
    await facultyCollection.doc(id).delete();
  }

  /// ==============================
  /// SUBJECTS
  /// ==============================

  Stream<List<SubjectModel>> getSubjects() {
    return subjectCollection.snapshots().map(
      (snapshot) => snapshot.docs
          .map(
            (doc) => SubjectModel.fromMap(
              doc.id,
              doc.data(),
            ),
          )
          .toList(),
    );
  }

  Stream<List<SubjectModel>> getSubjectsByYear(int year) {
    return subjectCollection
        .where('year', isEqualTo: year)
        .snapshots()
        .map(
      (snapshot) => snapshot.docs
          .map(
            (doc) => SubjectModel.fromMap(
              doc.id,
              doc.data(),
            ),
          )
          .toList(),
    );
  }

  Future<void> addSubject(SubjectModel subject) async {
    await subjectCollection.add(subject.toMap());
  }

  Future<void> updateSubject(SubjectModel subject) async {
    await subjectCollection.doc(subject.id).update(subject.toMap());
  }

  Future<void> deleteSubject(String id) async {
    await subjectCollection.doc(id).delete();
  }

  /// ==============================
  /// LABS
  /// ==============================

  Stream<List<LabModel>> getLabs() {
    return labCollection.snapshots().map(
      (snapshot) => snapshot.docs
          .map(
            (doc) => LabModel.fromMap(
              doc.id,
              doc.data(),
            ),
          )
          .toList(),
    );
  }

  Stream<List<LabModel>> getLabsByYear(int year) {
    return labCollection
        .where('year', isEqualTo: year)
        .snapshots()
        .map(
      (snapshot) => snapshot.docs
          .map(
            (doc) => LabModel.fromMap(
              doc.id,
              doc.data(),
            ),
          )
          .toList(),
    );
  }

  Future<void> addLab(LabModel lab) async {
    await labCollection.add(lab.toMap());
  }

  Future<void> updateLab(LabModel lab) async {
    await labCollection.doc(lab.id).update(lab.toMap());
  }

  Future<void> deleteLab(String id) async {
    await labCollection.doc(id).delete();
  }

  /// ==============================
  /// ROOMS
  /// ==============================

  Stream<List<RoomModel>> getRooms() {
    return roomCollection.snapshots().map(
      (snapshot) => snapshot.docs
          .map(
            (doc) => RoomModel.fromMap(
              doc.id,
              doc.data(),
            ),
          )
          .toList(),
    );
  }

  Future<void> addRoom(RoomModel room) async {
    await roomCollection.add(room.toMap());
  }

  Future<void> updateRoom(RoomModel room) async {
    await roomCollection.doc(room.id).update(room.toMap());
  }

  Future<void> deleteRoom(String id) async {
    await roomCollection.doc(id).delete();
  }

  /// ==============================
  /// TIME SLOTS
  /// ==============================

  Stream<List<TimeSlotModel>> getTimeSlots() {
    return timeSlotCollection
        .orderBy('slotNumber')
        .snapshots()
        .map(
      (snapshot) => snapshot.docs
          .map(
            (doc) => TimeSlotModel.fromMap(
              doc.id,
              doc.data(),
            ),
          )
          .toList(),
    );
  }

  Future<void> addTimeSlot(TimeSlotModel timeSlot) async {
    await timeSlotCollection.add(timeSlot.toMap());
  }

  Future<void> updateTimeSlot(TimeSlotModel timeSlot) async {
    await timeSlotCollection.doc(timeSlot.id).update(timeSlot.toMap());
  }

  Future<void> deleteTimeSlot(String id) async {
    await timeSlotCollection.doc(id).delete();
  }
}