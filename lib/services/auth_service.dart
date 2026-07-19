import 'package:firebase_auth/firebase_auth.dart';

class AuthService {

  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<String?> registerUser({
    required String email,
    required String password,
  }) async {

    try {

      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      return null;

    } on FirebaseAuthException catch (e) {

      return e.message;

    } catch (e) {

      return e.toString();

    }
  }

  Future<String?> loginUser({
    required String email,
    required String password,
  }) async {

    try {

      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      return null;

    } on FirebaseAuthException catch (e) {

      return e.message;

    } catch (e) {

      return e.toString();

    }
  }

  Future<void> logoutUser() async {
    await _auth.signOut();
  }

  /// Sends Firebase's password-reset email. Returns null on success or the
  /// FirebaseAuth error CODE (e.g. 'user-not-found') so the UI can branch.
  Future<String?> sendPasswordReset({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.code;
    } catch (_) {
      return 'unknown';
    }
  }

  /// Confirms the signed-in user's identity by re-entering their password.
  /// Returns null on success or a human-readable error.
  Future<String?> reauthenticate({required String password}) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) return 'Not signed in.';
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(cred);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        return 'Incorrect password.';
      }
      return e.message ?? e.code;
    } catch (e) {
      return e.toString();
    }
  }

  /// Changes the password of the signed-in user (call reauthenticate first).
  Future<String?> changePassword({required String newPassword}) async {
    try {
      await _auth.currentUser!.updatePassword(newPassword);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return e.toString();
    }
  }
}