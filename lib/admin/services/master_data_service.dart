import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_config.dart';
import '../models/faculty_model.dart';
import '../models/subject_model.dart';
import '../models/lab_model.dart';
import '../models/room_model.dart';
import '../models/time_slot_model.dart';
import 'master_data_exceptions.dart';

class MasterDataService {
  MasterDataService._();

  static final MasterDataService instance = MasterDataService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Weekday subcollections created by TimetableService.createBlankWeek —
  // kept in sync with that list so the in-use scans below cover every day.
  static const List<String> _weekdays = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
  ];

  // Timetable is nested timetables/{department}/{academicYear}/{year}/{day};
  // years run 1-4 (see the year filter chips in TimetableManagementScreen).
  static const List<int> _years = [1, 2, 3, 4];

  Iterable<CollectionReference<Map<String, dynamic>>> _dayCollectionsForYear(
      int year) sync* {
    for (final day in _weekdays) {
      yield _firestore
          .collection('timetables')
          .doc(AppConfig.department)
          .collection(AppConfig.academicYear)
          .doc(year.toString())
          .collection(day);
    }
  }

  Iterable<CollectionReference<Map<String, dynamic>>> _allDayCollections() sync* {
    for (final year in _years) {
      yield* _dayCollectionsForYear(year);
    }
  }

  /// True if any period across the scanned day-collections has [field]
  /// equal to [value] (and, if given, [classType] equal too). Pass
  /// [onlyYear] to restrict the scan to a single year — subjects/labs
  /// belong to one year, so there's no need to scan the other three.
  Future<bool> _isValueScheduled({
    required String field,
    required String value,
    int? onlyYear,
    String? classType,
  }) async {
    if (value.isEmpty) return false;
    final cols =
        onlyYear != null ? _dayCollectionsForYear(onlyYear) : _allDayCollections();
    for (final col in cols) {
      Query<Map<String, dynamic>> query = col.where(field, isEqualTo: value);
      if (classType != null) {
        query = query.where('classType', isEqualTo: classType);
      }
      final snap = await query.limit(1).get();
      if (snap.docs.isNotEmpty) return true;
    }
    return false;
  }

  /// Updates every period matching [field] == [oldValue] to [field] ==
  /// [newValue], so a rename (faculty name, subject name, room number...)
  /// immediately shows up everywhere the old value was assigned in the
  /// timetable. No-op if nothing actually changed.
  Future<void> _cascadeRename({
    required String field,
    required String oldValue,
    required String newValue,
    int? onlyYear,
    String? classType,
  }) async {
    if (oldValue.isEmpty || oldValue == newValue) return;
    final cols =
        onlyYear != null ? _dayCollectionsForYear(onlyYear) : _allDayCollections();
    for (final col in cols) {
      Query<Map<String, dynamic>> query = col.where(field, isEqualTo: oldValue);
      if (classType != null) {
        query = query.where('classType', isEqualTo: classType);
      }
      final snap = await query.get();
      if (snap.docs.isEmpty) continue;

      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {field: newValue});
      }
      await batch.commit();
    }
  }

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

  /// Edits are always allowed. If the name changed, every timetable period
  /// currently assigned to this faculty is updated so the displayed name
  /// stays in sync (periods store a denormalized `facultyName` alongside
  /// the stable `facultyId` for fast reads).
  Future<void> updateFaculty(FacultyModel faculty) async {
    final oldName =
        (await facultyCollection.doc(faculty.id).get()).data()?['name'] as String?;

    await facultyCollection.doc(faculty.id).update(faculty.toMap());

    // facultyId never changes on edit, so only the denormalized display
    // name can drift — cascade it by id, which is more reliable than
    // matching on the (now stale) old name.
    if (oldName != null && oldName != faculty.name) {
      await _cascadeRenameById(
        idField: 'facultyId',
        id: faculty.id,
        nameField: 'facultyName',
        newName: faculty.name,
      );
    }
  }

  Future<void> _cascadeRenameById({
    required String idField,
    required String id,
    required String nameField,
    required String newName,
  }) async {
    for (final col in _allDayCollections()) {
      final snap = await col.where(idField, isEqualTo: id).get();
      if (snap.docs.isEmpty) continue;

      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {nameField: newName});
      }
      await batch.commit();
    }
  }

  /// True if [facultyId] is assigned to at least one period anywhere in
  /// the current department/academic-year timetable.
  Future<bool> isFacultyScheduled(String facultyId) =>
      _isValueScheduled(field: 'facultyId', value: facultyId);

  /// Deletes the faculty record. Throws [MasterDataInUseException] instead
  /// of deleting if the faculty is still assigned anywhere in the
  /// timetable — the admin must remove/reassign those periods first.
  Future<void> deleteFaculty(String id, {String? facultyName}) async {
    if (await isFacultyScheduled(id)) {
      throw MasterDataInUseException(
        '${facultyName ?? 'This faculty member'} is assigned in the '
        'timetable. Remove or reassign those periods first, then delete '
        '${facultyName ?? 'them'}.',
      );
    }
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

  /// Edits are always allowed. If the name changed, every timetable period
  /// currently showing the old subject name (in the subject's own year —
  /// periods only store the plain name, so the search is scoped to the
  /// year the subject was in before the edit) is updated to the new name.
  Future<void> updateSubject(SubjectModel subject) async {
    final oldDoc = (await subjectCollection.doc(subject.id).get()).data();
    final oldName = oldDoc?['name'] as String?;
    final oldYear = (oldDoc?['year'] as num?)?.toInt() ?? subject.year;

    await subjectCollection.doc(subject.id).update(subject.toMap());

    if (oldName != null && oldName != subject.name) {
      await _cascadeRename(
        field: 'subject',
        oldValue: oldName,
        newValue: subject.name,
        onlyYear: oldYear,
      );
    }
  }

  /// True if [subject] (matched by name, within its own year) is assigned
  /// to at least one period in the timetable.
  Future<bool> isSubjectScheduled(SubjectModel subject) => _isValueScheduled(
        field: 'subject',
        value: subject.name,
        onlyYear: subject.year,
      );

  /// Deletes the subject. Throws [MasterDataInUseException] instead of
  /// deleting if it's still assigned anywhere in the Year [SubjectModel.year]
  /// timetable — the admin must remove/reassign those periods first.
  Future<void> deleteSubject(String id, {SubjectModel? subject}) async {
    if (subject != null && await isSubjectScheduled(subject)) {
      throw MasterDataInUseException(
        '${subject.name} is assigned in the Year ${subject.year} timetable. '
        'Remove or reassign those periods first, then delete ${subject.name}.',
      );
    }
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

  /// Same rename-cascade as [updateSubject] — labs also live in the
  /// period's `subject` field (tagged `classType: 'Lab'`), just scoped to
  /// lab-type periods so a same-named theory subject is never touched.
  Future<void> updateLab(LabModel lab) async {
    final oldDoc = (await labCollection.doc(lab.id).get()).data();
    final oldName = oldDoc?['name'] as String?;
    final oldYear = (oldDoc?['year'] as num?)?.toInt() ?? lab.year;

    await labCollection.doc(lab.id).update(lab.toMap());

    if (oldName != null && oldName != lab.name) {
      await _cascadeRename(
        field: 'subject',
        oldValue: oldName,
        newValue: lab.name,
        onlyYear: oldYear,
        classType: 'Lab',
      );
    }
  }

  /// True if [lab] (matched by name, within its own year, lab periods
  /// only) is assigned to at least one period in the timetable.
  Future<bool> isLabScheduled(LabModel lab) => _isValueScheduled(
        field: 'subject',
        value: lab.name,
        onlyYear: lab.year,
        classType: 'Lab',
      );

  /// Deletes the lab. Throws [MasterDataInUseException] instead of
  /// deleting if it's still assigned anywhere in the Year [LabModel.year]
  /// timetable — the admin must remove/reassign those periods first.
  Future<void> deleteLab(String id, {LabModel? lab}) async {
    if (lab != null && await isLabScheduled(lab)) {
      throw MasterDataInUseException(
        '${lab.name} is assigned in the Year ${lab.year} timetable. Remove '
        'or reassign those lab periods first, then delete ${lab.name}.',
      );
    }
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

  /// Edits are always allowed. If the room number changed, every
  /// timetable period currently pointing at the old room number (any
  /// year — a room isn't tied to one year) is updated to the new one.
  Future<void> updateRoom(RoomModel room) async {
    final oldNumber =
        (await roomCollection.doc(room.id).get()).data()?['roomNumber'] as String?;

    await roomCollection.doc(room.id).update(room.toMap());

    if (oldNumber != null && oldNumber != room.roomNumber) {
      await _cascadeRename(
        field: 'room',
        oldValue: oldNumber,
        newValue: room.roomNumber,
      );
    }
  }

  /// True if [room] (matched by room number, any year) is assigned to at
  /// least one period in the timetable.
  Future<bool> isRoomScheduled(RoomModel room) =>
      _isValueScheduled(field: 'room', value: room.roomNumber);

  /// Deletes the room. Throws [MasterDataInUseException] instead of
  /// deleting if it's still assigned anywhere in the timetable — the
  /// admin must remove/reassign those periods first.
  Future<void> deleteRoom(String id, {RoomModel? room}) async {
    if (room != null && await isRoomScheduled(room)) {
      throw MasterDataInUseException(
        'Room ${room.roomNumber} is assigned in the timetable. Remove or '
        'reassign those periods first, then delete this room.',
      );
    }
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

  /// Edits are always allowed. Periods are matched to a slot by
  /// `periodNo == slotNumber` AND matching start/end times (see
  /// TimetableManagementScreen._getPeriodForDayAndSlot) — so if the start
  /// or end time changes here without updating existing periods, those
  /// periods would silently stop matching their slot in the UI. Every
  /// period with this `periodNo` (free or scheduled) gets the new times.
  Future<void> updateTimeSlot(TimeSlotModel timeSlot) async {
    await timeSlotCollection.doc(timeSlot.id).update(timeSlot.toMap());
    await _cascadeTimeSlotTimes(timeSlot);
  }

  Future<void> _cascadeTimeSlotTimes(TimeSlotModel slot) async {
    for (final col in _allDayCollections()) {
      final snap = await col.where('periodNo', isEqualTo: slot.slotNumber).get();
      if (snap.docs.isEmpty) continue;

      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {
          'startTime': slot.startTime,
          'endTime': slot.endTime,
        });
      }
      await batch.commit();
    }
  }

  /// True if any *actually scheduled* (non-free) period uses this slot's
  /// number anywhere in the timetable.
  Future<bool> isTimeSlotScheduled(TimeSlotModel slot) async {
    for (final col in _allDayCollections()) {
      final snap = await col
          .where('periodNo', isEqualTo: slot.slotNumber)
          .where('isFree', isEqualTo: false)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return true;
    }
    return false;
  }

  /// Deletes the time slot. Throws [MasterDataInUseException] instead of
  /// deleting if classes are still scheduled against it — the admin must
  /// remove those periods from the timetable first.
  Future<void> deleteTimeSlot(String id, {TimeSlotModel? slot}) async {
    if (slot != null && await isTimeSlotScheduled(slot)) {
      throw MasterDataInUseException(
        'Slot ${slot.slotNumber} (${slot.startTime}-${slot.endTime}) has '
        'classes scheduled against it. Remove those periods from the '
        'timetable first, then delete this slot.',
      );
    }
    await timeSlotCollection.doc(id).delete();
  }
}