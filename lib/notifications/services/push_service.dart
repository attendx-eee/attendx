import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../core/auth/account_lookup.dart';
import 'local_notification_service.dart';

/// Handles the device's FCM registration and incoming pushes.
///
/// The Firestore listener in [LocalNotificationService] only runs while
/// the app is alive. That's fine for someone staring at the screen and
/// useless for everyone else — a student marked absent at 2pm finds out
/// when they next open the app, which defeats the point of telling them
/// the same day. Push is the only mechanism that reaches a phone in a
/// pocket, and it has to be sent by something holding server
/// credentials, so a Cloud Function does the sending (see functions/).
///
/// This side of it is small: register the token, keep it fresh, and
/// decide what to draw when a message lands.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  /// Tokens live on the account document, as an array.
  ///
  /// An array rather than a single field because one person legitimately
  /// has two devices — a phone and the department tablet — and storing
  /// one token silently stops notifying whichever they signed into
  /// first.
  static const String tokenField = 'fcmTokens';

  bool _started = false;
  String? _currentToken;

  /// Registers this device and starts listening.
  ///
  /// Safe to call on every sign-in; it no-ops after the first success.
  Future<void> start(String uid) async {
    if (kIsWeb || _started || uid.isEmpty) return;

    try {
      final messaging = FirebaseMessaging.instance;

      // On Android 13+ this is the same POST_NOTIFICATIONS grant the
      // local notifications already asked for, so it usually returns
      // immediately without a second prompt.
      final settings = await messaging.requestPermission();

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Push permission denied; skipping token registration.');
        return;
      }

      final token = await messaging.getToken();
      if (token != null) await _saveToken(uid, token);

      // Tokens rotate — on reinstall, on restore to a new phone, and
      // occasionally for no visible reason. Without this the account
      // keeps a dead token and silently stops receiving anything.
      messaging.onTokenRefresh.listen((fresh) => _saveToken(uid, fresh));

      FirebaseMessaging.onMessage.listen(_show);

      _started = true;
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }

  /// What to draw for a message that lands while the app is open.
  ///
  /// Usually nothing. Every push has a Firestore document behind it, and
  /// while the app is running [LocalNotificationService]'s listener is
  /// watching that collection — so both paths were firing for one event
  /// and the student got the same alert twice, seconds apart. The
  /// listener is the better of the two: it has the whole document, it
  /// fires the moment the write lands rather than up to a minute later,
  /// and it works whether or not a push token was ever registered.
  ///
  /// So while the listener is live, push stays quiet in the foreground
  /// and does the job it is actually needed for — reaching a phone whose
  /// app is closed, where nothing else can.
  ///
  /// If the listener is not running, this draws after all. Signed out,
  /// permission refused, the stream dropped — a missing notification
  /// would be worse than a duplicated one.
  Future<void> _show(RemoteMessage message) async {
    if (LocalNotificationService.instance.realtimeActive) return;

    final title = message.data['title'] ?? message.notification?.title;
    final body = message.data['body'] ?? message.notification?.body;

    if (title == null && body == null) return;

    // The document id, where the sender supplied one, so this lands on
    // the same notification the listener would have drawn instead of
    // beside it. Falls back to the message id.
    final docId = (message.data['id'] ?? '').toString();

    await LocalNotificationService.instance.showNow(
      id: docId.isNotEmpty
          ? LocalNotificationService.notificationIdFor(docId)
          : 500000 + (message.messageId.hashCode % 400000).abs(),
      tag: docId.isEmpty ? null : docId,
      title: title ?? 'AttendX',
      body: body ?? '',
    );
  }

  Future<void> _saveToken(String uid, String token) async {
    if (_currentToken == token) return;

    try {
      final ref = await _accountRef(uid);
      if (ref == null) return;

      await ref.set({
        tokenField: FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));

      _currentToken = token;
    } catch (e) {
      debugPrint('Saving push token failed: $e');
    }
  }

  /// Removes this device's token on sign-out.
  ///
  /// Without it the next person to sign in on a shared department phone
  /// keeps receiving the previous user's absence notifications, which is
  /// both confusing and a small privacy leak.
  Future<void> stop(String uid) async {
    _started = false;

    if (kIsWeb) return;

    final token = _currentToken;
    _currentToken = null;
    if (token == null || uid.isEmpty) return;

    try {
      final ref = await _accountRef(uid);
      await ref?.update({
        tokenField: FieldValue.arrayRemove([token]),
      });
    } catch (e) {
      debugPrint('Clearing push token failed: $e');
    }
  }

  Future<DocumentReference<Map<String, dynamic>>?> _accountRef(
      String uid) async {
    final db = FirebaseFirestore.instance;

    for (final name in const [
      AccountLookup.students,
      AccountLookup.facultyAccounts,
      AccountLookup.admins,
    ]) {
      final ref = db.collection(name).doc(uid);
      if ((await ref.get()).exists) return ref;
    }

    return null;
  }
}

/// Runs in its own isolate when a message arrives with the app killed.
///
/// Must be a top-level function annotated for AOT, or the entry point is
/// tree-shaken out of release builds and background messages are dropped
/// with no error anywhere.
///
/// Deliberately does almost nothing. Android already draws the
/// notification from the payload; this exists so the isolate has a valid
/// handler and so there's somewhere to add background bookkeeping later.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background push: ${message.messageId}');
}
