import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/auth/account_lookup.dart';
import 'adaptive_face_service.dart';
import 'enrollment/scan_harvester.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// The document holding this account's profile, wherever it lives.
  ///
  /// Face enrollment is the one flow used by students, CRs and faculty
  /// alike, and it writes `faceEnrolled` back onto the profile. Once
  /// faculty moved to their own collection, hard-coding `students` here
  /// meant every faculty enrollment failed at the last step — the scan
  /// had already succeeded, so it surfaced as an unexplained
  /// "storage sync rejected" with no hint that the record was simply
  /// being looked for in the wrong place.
  Future<DocumentReference<Map<String, dynamic>>?> profileRef(
      String uid) async {
    for (final name in const [
      AccountLookup.students,
      AccountLookup.facultyAccounts,
      AccountLookup.admins,
    ]) {
      final ref = _firestore.collection(name).doc(uid);
      if ((await ref.get()).exists) return ref;
    }
    return null;
  }

  Future<void> saveStudent(Map<String, dynamic> data) async {
    await _firestore
        .collection('students')
        .doc(data['uid'])
        .set(data, SetOptions(merge: true));
  }

  /// Which face-template collection holds [uid].
  ///
  /// Faculty templates live apart from student ones. Resolved from the
  /// account rather than passed in, because every caller would otherwise
  /// have to know the answer and one of them would eventually get it
  /// wrong — silently, by writing a template nobody later reads.
  Future<CollectionReference<Map<String, dynamic>>> facesRef(
      String uid) async {
    final account = await AccountLookup.find(uid);
    return _firestore.collection(AccountLookup.facesFor(account.kind));
  }

  Future<void> saveStageEmbeddings(String uid, Map<String, dynamic> data) async {
    final faces = await facesRef(uid);
    await faces.doc(uid).set(data, SetOptions(merge: true));
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getStudent(String uid) async {
    return await _firestore
        .collection('students')
        .doc(uid)
        .get();
  }

  /// One account's template, from wherever it lives.
  ///
  /// Falls back to the other collection if the expected one is empty:
  /// an account whose record moved between collections after enrolling
  /// would otherwise look like it had never enrolled at all.
  Future<DocumentSnapshot<Map<String, dynamic>>> getStageEmbeddings(
      String uid) async {
    final faces = await facesRef(uid);
    final doc = await faces.doc(uid).get();
    if (doc.exists) return doc;

    final other = faces.id == AccountLookup.facultyFaces
        ? AccountLookup.studentFaces
        : AccountLookup.facultyFaces;

    return _firestore.collection(other).doc(uid).get();
  }

  /// Every enrolled face, students and staff together.
  ///
  /// The duplicate check has to span both collections. Splitting them
  /// and then only reading one would mean a lecturer could enroll a
  /// face already registered to a student, which is precisely the case
  /// the check exists for.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      getAllFaceEnrollmentDocs() async {
    final results = await Future.wait([
      _firestore.collection(AccountLookup.studentFaces).get(),
      _firestore.collection(AccountLookup.facultyFaces).get(),
    ]);

    return [for (final snap in results) ...snap.docs];
  }

  /// First-time registration only: writes the student profile AND the face
  /// enrollment data together in one batch, so a signed-in account never
  /// ends up with a saved profile unless face enrollment actually
  /// succeeded. [profile] is the map RegisterScreen collected but held
  /// back from Firestore until now (see FaceEnrollmentScreen, mandatory
  /// flow). Re-enrollment from Account Settings uses [updateFaceEmbeddings]
  /// instead, since the profile already exists there.
  ///
  /// [grade] is the scan's scorecard. Stored with the template so a
  /// later false rejection can be traced to a thin enrollment rather
  /// than guessed at, and so an admin can find weak templates before
  /// they start failing at the gate.
  Future<void> completeRegistrationWithFace({
    required String uid,
    required Map<String, dynamic> profile,
    required Map<String, List<double>> fusedEmbeddings,
    EnrollmentGrade? grade,
    /// Where the profile belongs. Students and CRs land in `students`,
    /// faculty in `faculty_accounts` — same atomic write either way, so
    /// a faculty sign-up can't leave a pending account behind when the
    /// face turns out to be someone else's.
    String collection = AccountLookup.students,
  }) async {
    if (fusedEmbeddings.isEmpty) {
      throw Exception(
        "Cannot save enrollment: supplied fused embeddings are empty.",
      );
    }

    // A failed scan must never reach storage. The screen already blocks
    // this, but enrollment is the one write where a bad record is
    // expensive and silent — it doesn't break until someone can't get
    // into class weeks later.
    if (grade != null && !grade.passed) {
      throw Exception(
        "Cannot save enrollment: ${grade.reason ?? 'scan quality too low'}",
      );
    }

    final Map<String, dynamic> verifiedEmbeddings = {};
    fusedEmbeddings.forEach((stage, embeddings) {
      verifiedEmbeddings[stage] = embeddings.map((e) => e.toDouble()).toList();
    });

    final int totalImages = verifiedEmbeddings.values.fold<int>(
      0,
      (acc, list) => acc + (list as List).length,
    );

    final centroid = AdaptiveFaceService.fuse(fusedEmbeddings.values.toList());

    final Map<String, dynamic> anchorEmbeddings = {};
    verifiedEmbeddings.forEach((stage, value) {
      anchorEmbeddings[stage] = List<double>.from(value as List);
    });

    final batch = _firestore.batch();

    final studentRef = _firestore.collection(collection).doc(uid);
    batch.set(
      studentRef,
      {
        ...profile,
        'uid': uid,
        'faceEnrolled': true,
        'faceImagesCaptured': totalImages,
        'faceEnrolledAt': FieldValue.serverTimestamp(),
        // Denormalised onto the student doc so the admin's student list
        // can flag weak enrollments without reading a second collection
        // for every row.
        if (grade != null) 'faceQualityBand': grade.band,
        if (grade != null)
          'faceQualityScore':
              double.parse(grade.meanQuality.toStringAsFixed(2)),
      },
      SetOptions(merge: true),
    );

    // The template follows the profile. `collection` already says which
    // kind of account this is, so there's no lookup to get wrong — and
    // no lookup to fail, which matters because at this point the
    // profile document doesn't exist yet.
    final enrollmentRef = _firestore
        .collection(collection == AccountLookup.facultyAccounts
            ? AccountLookup.facultyFaces
            : AccountLookup.studentFaces)
        .doc(uid);
    batch.set(enrollmentRef, {
      'uid': uid,
      'name': profile['name'] ?? '',
      'regNo': profile['regNo'] ?? '',
      'embeddingDimension': 192,
      // 3 = harvested from a continuous scan, quality-weighted, with a
      // scorecard. Version 2 templates came from counted per-pose photos
      // and remain valid to match against.
      'enrollmentVersion': 3,
      'embeddings': verifiedEmbeddings,
      'anchorEmbeddings': anchorEmbeddings,
      'centroid': centroid,
      'adaptationCount': 0,
      'verificationCount': 0,
      'avgMatchScore': 0.0,
      'reenrollRecommended': false,
      if (grade != null) 'quality': grade.toMap(),
      'enrolledAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Full account deletion ("delete everything about this person"):
  /// removes the profile, face templates, attendance history and
  /// notifications tied to [uid]. Firestore only — the caller (see
  /// AccountSettingsScreen) is responsible for also deleting the
  /// Firebase Auth account and the Cloudinary photo afterward.
  ///
  /// Order matters: call this BEFORE deleting the Auth user. These
  /// deletes need an authenticated `request.auth.uid == uid` to pass
  /// Firestore's security rules — once the Auth account is gone there's
  /// no session left to authorize them.
  Future<void> deleteStudentAccount(String uid) async {
    await _deleteWhere(collection: 'attendance_events', field: 'uid', uid: uid);
    await _deleteWhere(
        collection: 'notifications', field: 'studentUid', uid: uid);
    // Manual corrections are attendance data about this person too —
    // leaving them behind would keep a deleted student's record alive in
    // every monthly report.
    await _deleteWhere(collection: 'attendance_manual', field: 'uid', uid: uid);

    final batch = _firestore.batch();

    // Both template collections unconditionally. Deleting a document
    // that isn't there is free, and working out which one it's in would
    // mean trusting a profile lookup during the one operation whose
    // whole job is to remove that profile.
    batch.delete(
        _firestore.collection(AccountLookup.studentFaces).doc(uid));
    batch.delete(
        _firestore.collection(AccountLookup.facultyFaces).doc(uid));

    final profile = await profileRef(uid);
    if (profile != null) batch.delete(profile);

    await batch.commit();
  }

  /// Deletes every doc in [collection] where [field] == [uid], paging
  /// through in batches so accounts with long attendance histories
  /// (hundreds of daily docs) never exceed Firestore's 500-write batch
  /// limit.
  Future<void> _deleteWhere({
    required String collection,
    required String field,
    required String uid,
  }) async {
    const pageSize = 400;
    while (true) {
      final snapshot = await _firestore
          .collection(collection)
          .where(field, isEqualTo: uid)
          .limit(pageSize)
          .get();

      if (snapshot.docs.isEmpty) break;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < pageSize) break;
    }
  }

  Future<void> updateFaceEmbeddings(
    String uid,
    Map<String, List<double>> fusedEmbeddings, {
    EnrollmentGrade? grade,
  }) async {
    if (fusedEmbeddings.isEmpty) {
      throw Exception(
        "Cannot update embeddings: Supplied fused embeddings are empty.",
      );
    }

    // Re-enrollment replaces a working template, so a failed scan here
    // is worse than at registration: it would trade something usable for
    // something that isn't.
    if (grade != null && !grade.passed) {
      throw Exception(
        "Cannot update embeddings: ${grade.reason ?? 'scan quality too low'}",
      );
    }

    // Whichever collection this account lives in — student, faculty or
    // admin. All three can enroll a face.
    final ref = await profileRef(uid);

    if (ref == null) {
      throw Exception(
        'No profile found for this account in students, '
        '${AccountLookup.facultyAccounts} or ${AccountLookup.admins}.',
      );
    }

    final profileData = (await ref.get()).data() ?? const <String, dynamic>{};

    final String name = profileData['name'] ?? '';
    final String regNo = profileData['regNo'] ?? '';

    // Normalize embeddings
    final Map<String, dynamic> verifiedEmbeddings = {};

    fusedEmbeddings.forEach((stage, embeddings) {
      verifiedEmbeddings[stage] = embeddings
          .map((e) => e.toDouble())
          .toList();
    });

    final int totalImages = verifiedEmbeddings.values.fold<int>(
      0,
      (acc, list) => acc + (list as List).length,
    );

    // Fused all-pose centroid for fast prefiltering during identification.
    final centroid = AdaptiveFaceService.fuse(
      fusedEmbeddings.values.toList(),
    );

    // Immutable anchor copies: adaptive learning may nudge `embeddings`
    // over time, but can never drift far from these enrollment-day vectors.
    final Map<String, dynamic> anchorEmbeddings = {};
    verifiedEmbeddings.forEach((stage, value) {
      anchorEmbeddings[stage] = List<double>.from(value as List);
    });

    // Store biometric data separately (v2 adaptive schema).
    // A fresh enrollment resets adaptation history and aging flags.
    final faces = await facesRef(uid);

    await faces.doc(uid).set({
      'uid': uid,
      'name': name,
      'regNo': regNo,
      'embeddingDimension': 192,
      'enrollmentVersion': 3,
      'embeddings': verifiedEmbeddings,
      'anchorEmbeddings': anchorEmbeddings,
      'centroid': centroid,
      'adaptationCount': 0,
      'verificationCount': 0,
      'avgMatchScore': 0.0,
      'reenrollRecommended': false,
      if (grade != null) 'quality': grade.toMap(),
      'enrolledAt': FieldValue.serverTimestamp(),
    });

    // Update only enrollment status on the profile
    await ref.update({
      'faceEnrolled': true,
      'faceImagesCaptured': totalImages,
      'faceEnrolledAt': FieldValue.serverTimestamp(),
      if (grade != null) 'faceQualityBand': grade.band,
      if (grade != null)
        'faceQualityScore':
            double.parse(grade.meanQuality.toStringAsFixed(2)),
    });
  }
}
