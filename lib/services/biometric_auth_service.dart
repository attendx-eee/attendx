import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Fingerprint/biometric login.
///
/// When the user enables it (Account Settings), their credentials are
/// stored in the platform's encrypted keystore (flutter_secure_storage).
/// On the login screen a successful fingerprint scan releases them for a
/// normal Firebase email/password sign-in.
class BiometricAuthService {
  BiometricAuthService._();

  static final BiometricAuthService instance = BiometricAuthService._();

  final LocalAuthentication _localAuth = LocalAuthentication();
  static const _storage = FlutterSecureStorage();

  /// Human-readable reason of the last failure (for the UI to show).
  String? lastError;

  static const _kEnabled = 'biometric_login_enabled';
  static const _kEmail = 'biometric_login_email';
  static const _kPassword = 'biometric_login_password';

  /// Device has a fingerprint/face sensor with something enrolled.
  Future<bool> isDeviceSupported() async {
    try {
      return await _localAuth.isDeviceSupported() &&
          await _localAuth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isEnabled() async {
    try {
      return (await _storage.read(key: _kEnabled)) == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> enable({required String email, required String password}) async {
    await _storage.write(key: _kEmail, value: email);
    await _storage.write(key: _kPassword, value: password);
    await _storage.write(key: _kEnabled, value: 'true');
  }

  Future<void> disable() async {
    await _storage.delete(key: _kEmail);
    await _storage.delete(key: _kPassword);
    await _storage.delete(key: _kEnabled);
  }

  /// Shows the system fingerprint prompt; on success returns the stored
  /// (email, password) — or null if cancelled/failed/not stored.
  Future<(String, String)?> authenticate() async {
    lastError = null;
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Login to AttendX',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!ok) return null; // user cancelled — not an error

      final email = await _storage.read(key: _kEmail);
      final password = await _storage.read(key: _kPassword);
      if (email == null || password == null) {
        lastError = 'No saved credentials — re-enable fingerprint login.';
        return null;
      }
      return (email, password);
    } catch (e) {
      // Typical causes: app not fully rebuilt after install (plugin
      // missing), no fingerprint enrolled, or FragmentActivity missing.
      lastError = e.toString();
      return null;
    }
  }
}
