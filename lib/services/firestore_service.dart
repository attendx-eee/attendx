import 'package:cloud_firestore/cloud_firestore.dart';

import 'adaptive_face_service.dart';
import 'enrollment/scan_harvester.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> saveStudent(Map<String, dynamic> data) async {
    await _firestore
        .collection('students')
        .doc(data['uid'])
        .set(data, SetOptions(merge: true));
  }

  Future<void> saveStageEmbeddings(String uid, Map<String, dynamic> data) async {
    await _firestore
        .collection("student_face_enrollments")
        .doc(uid)
        .set(data, SetOptions(merge: true));
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getStudent(String uid) async {
    return await _firestore
        .collection('students')
        .doc(uid)
        .get();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getStageEmbeddings(String uid) async {
    return await _firestore
        .collection("student_face_enrollments")
        .doc(uid)
        .get();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> getAllFaceEnrollments() async {
    return await _firestore
        .collection("student_face_enrollments")
        .get();
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

    final studentRef = _firestore.collection('students').doc(uid);
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

    final enrollmentRef =
        _firestore.collection('student_face_enrollments').doc(uid);
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
    batch.delete(_firestore.collection('student_face_enrollments').doc(uid));
    batch.delete(_firestore.collection('students').doc(uid));
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

    // Read student details
    final studentDoc =
        await _firestore.collection('students').doc(uid).get();

    if (!studentDoc.exists) {
      throw Exception("Student record not found.");
    }

    final studentData = studentDoc.data()!;

    final String name = studentData['name'] ?? '';
    final String regNo = studentData['regNo'] ?? '';

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
    await _firestore
        .collection('student_face_enrollments')
        .doc(uid)
        .set({
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

    // Update only enrollment status in student profile
    await _firestore
        .collection('students')
        .doc(uid)
        .update({
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
