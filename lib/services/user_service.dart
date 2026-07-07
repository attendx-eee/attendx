import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/constants/user_roles.dart';


class UserService {

  final FirebaseFirestore firestore =
      FirebaseFirestore.instance;

  Future<UserModel> getCurrentUser() async {

    final uid =
        FirebaseAuth.instance.currentUser!.uid;

    final doc =
        await firestore.collection("users").doc(uid).get();

    return UserModel.fromMap(doc.data()!);
  }

}