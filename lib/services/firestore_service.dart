import 'package:cloud_firestore/cloud_firestore.dart';

import 'adaptive_face_service.dart';

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

  Future<void> updateFaceEmbeddings(
    String uid,
    Map<String, List<double>> fusedEmbeddings,
  ) async {
    if (fusedEmbeddings.isEmpty) {
      throw Exception(
        "Cannot update embeddings: Supplied fused embeddings are empty.",
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
      'enrollmentVersion': 2,
      'embeddings': verifiedEmbeddings,
      'anchorEmbeddings': anchorEmbeddings,
      'centroid': centroid,
      'adaptationCount': 0,
      'verificationCount': 0,
      'avgMatchScore': 0.0,
      'reenrollRecommended': false,
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
    });
  }
}
