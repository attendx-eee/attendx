import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Where an account's record lives.
///
/// Three roles, three collections. They used to share `students`, which
/// meant an admin account with `role: 'hod'` appeared in the Year 1
/// student list, counted towards class sizes, and turned up in
/// attendance analysis. Separating them makes "who is a student" a
/// question the database can answer instead of a filter every screen has
/// to remember to apply.
enum AccountKind { admin, faculty, student, none }

/// One account, and which collection it came from.
class Account {
  final String uid;
  final AccountKind kind;
  final String role;
  final Map<String, dynamic> data;

  /// True when the record was found in `students` but isn't a student —
  /// a leftover from before the split. Everything still works; it just
  /// wants migrating.
  final bool legacy;

  const Account({
    required this.uid,
    required this.kind,
    required this.role,
    required this.data,
    this.legacy = false,
  });

  static const Account none = Account(
    uid: '',
    kind: AccountKind.none,
    role: '',
    data: {},
  );

  bool get exists => kind != AccountKind.none;

  bool get isAdmin => kind == AccountKind.admin;
  bool get isFaculty => kind == AccountKind.faculty;
  bool get isStudent => kind == AccountKind.student;
  bool get isCr => role == 'cr';

  String get name => (data['name'] ?? '').toString();
}

/// Finds an account across the three collections.
class AccountLookup {
  AccountLookup._();

  static const String admins = 'admins';
  static const String facultyAccounts = 'faculty_accounts';
  static const String students = 'students';

  /// Kept only so accounts created before the split still sign in.
  static const String legacyUsers = 'users';

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Roles that mean "runs the department".
  static bool isAdminRole(String role) =>
      role == 'hod' || role == 'office';

  /// Resolves [uid] to an account.
  ///
  /// Order matters: admins first, because an admin who also has a
  /// leftover student record should reach the console rather than a
  /// dashboard. Students last, because that's the collection the old
  /// scheme piled everything into and the least trustworthy signal of
  /// what an account actually is.
  static Future<Account> find(String uid) async {
    if (uid.isEmpty) return Account.none;

    try {
      final admin = await _db.collection(admins).doc(uid).get();
      if (admin.exists) {
        final data = admin.data() ?? const <String, dynamic>{};
        return Account(
          uid: uid,
          kind: AccountKind.admin,
          role: (data['role'] ?? 'hod').toString().toLowerCase(),
          data: data,
        );
      }

      final faculty = await _db.collection(facultyAccounts).doc(uid).get();
      if (faculty.exists) {
        return Account(
          uid: uid,
          kind: AccountKind.faculty,
          role: 'faculty',
          data: faculty.data() ?? const <String, dynamic>{},
        );
      }

      final student = await _db.collection(students).doc(uid).get();
      if (student.exists) {
        final data = student.data() ?? const <String, dynamic>{};
        final role = (data['role'] ?? 'student').toString().toLowerCase();

        // A record still sitting in `students` with an admin or faculty
        // role predates the split. Honour it — locking someone out
        // because their document is in the old place would be a poor
        // trade — but flag it so the console can say so.
        if (isAdminRole(role)) {
          return Account(
            uid: uid,
            kind: AccountKind.admin,
            role: role,
            data: data,
            legacy: true,
          );
        }

        if (role == 'faculty') {
          return Account(
            uid: uid,
            kind: AccountKind.faculty,
            role: role,
            data: data,
            legacy: true,
          );
        }

        return Account(
          uid: uid,
          kind: AccountKind.student,
          role: role,
          data: data,
        );
      }

      // Pre-`students` accounts.
      final legacy = await _db.collection(legacyUsers).doc(uid).get();
      if (legacy.exists) {
        final data = legacy.data() ?? const <String, dynamic>{};
        final role = (data['role'] ?? 'student').toString().toLowerCase();
        return Account(
          uid: uid,
          kind: isAdminRole(role) ? AccountKind.admin : AccountKind.student,
          role: role,
          data: data,
          legacy: true,
        );
      }
    } catch (e) {
      debugPrint('Account lookup failed for $uid: $e');
    }

    return Account.none;
  }

  /// Whether a `students` document describes an actual student.
  ///
  /// Every screen that lists or counts students runs its rows through
  /// this. After migration it's a no-op; before it, it's what keeps an
  /// admin record out of the Year 1 list and out of the attendance
  /// percentages.
  static bool isStudentDoc(Map<String, dynamic> data) {
    final role = (data['role'] ?? 'student').toString().toLowerCase();
    return role == 'student' || role == 'cr' || role.isEmpty;
  }
}
