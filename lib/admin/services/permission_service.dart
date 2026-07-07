import '../models/admin_session.dart';

class PermissionService {
  PermissionService._();

  static bool canEdit(AdminSession session) {
    return session.isCR ||
        session.isOffice ||
        session.isHOD;
  }

  static bool canApprove(AdminSession session) {
    return session.isOffice ||
        session.isHOD;
  }

  static bool canDelete(AdminSession session) {
    return session.isHOD;
  }

  static bool canSubmit(AdminSession session) {
    return session.isCR;
  }

  static bool canViewAnalytics(AdminSession session) {
    return session.isOffice ||
        session.isHOD;
  }
}