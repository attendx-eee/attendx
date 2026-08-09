import 'package:firebase_auth/firebase_auth.dart';

import '../notifications/services/push_service.dart';

class AuthService {

  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Signs in anonymously so the registration form can run pre-signup
  /// availability checks — Firestore rules require `signedIn()` for any
  /// read, and no real account exists yet while someone's still filling
  /// out the form. No-ops if already signed in (as anyone). Returns null
  /// on success, or an error if anonymous sign-in isn't available (e.g.
  /// the Anonymous provider isn't enabled in the Firebase Console yet) —
  /// callers must treat that as "live checks unavailable" and fail
  /// silently, never block registration on it.
  Future<String?> signInAnonymouslyForPreCheck() async {
    if (_auth.currentUser != null) return null;
    try {
      await _auth.signInAnonymously();
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return e.toString();
    }
  }

  /// Creates the permanent account. If the caller already holds an
  /// anonymous session (from [signInAnonymouslyForPreCheck]), this
  /// upgrades it in place via linkWithCredential — same uid, now a real
  /// email/password account — instead of creating a second user.
  /// Otherwise falls back to a fresh sign-up, so registration still
  /// works even when anonymous sign-in was never available.
  Future<String?> registerUser({
    required String email,
    required String password,
  }) async {

    try {

      final current = _auth.currentUser;

      if (current != null && current.isAnonymous) {
        final credential = EmailAuthProvider.credential(
          email: email,
          password: password,
        );
        await current.linkWithCredential(credential);
      } else {
        await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

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
    // Drop this device's push token before the credentials go, or the
    // next person to sign in on a shared department phone keeps getting
    // the previous student's absence notifications.
    final uid = _auth.currentUser?.uid;
    if (uid != null) await PushService.instance.stop(uid);

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