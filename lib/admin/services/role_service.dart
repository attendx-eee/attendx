class RoleService {

  bool isHod(String role) => role == "hod";

  bool isOffice(String role) => role == "office";

  bool isCR(String role) => role == "cr";

  bool isStudent(String role) => role == "student";

  bool canManageFaculty(String role) {
    return role == "hod" || role == "office";
  }

  bool canApproveTimetable(String role) {
    return role == "hod";
  }

  bool canEditTimetable(String role) {
    return role == "hod" ||
           role == "office" ||
           role == "cr";
  }

  bool canSendNotification(String role) {
    return role == "hod" ||
           role == "office" ||
           role == "cr";
  }
}