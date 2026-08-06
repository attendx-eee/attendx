/// Who is marking attendance, and what they're allowed to touch.
///
/// Both the directory and the calendar need the same handful of facts
/// about the signed-in user, and both are opened from two different
/// places (admin Master Data, CR dashboard). Bundling them keeps the
/// screen constructors honest — a caller can't accidentally build a CR
/// view without saying which year they're limited to.
class AttendanceMarker {
  final String uid;
  final String name;

  /// 'hod' | 'office' | 'cr'
  final String role;

  /// Admins see all four years and can mark any day outright.
  /// CRs see only [lockedYear] and need a per-month grant.
  final bool isAdmin;

  /// The only year a CR may look at. Null for admins.
  final int? lockedYear;

  const AttendanceMarker({
    required this.uid,
    required this.name,
    required this.role,
    required this.isAdmin,
    this.lockedYear,
  });

  const AttendanceMarker.admin({
    required this.uid,
    required this.name,
    this.role = 'hod',
  })  : isAdmin = true,
        lockedYear = null;

  const AttendanceMarker.cr({
    required this.uid,
    required this.name,
    required int year,
  })  : role = 'cr',
        isAdmin = false,
        lockedYear = year;

  /// Years this marker may browse.
  List<int> get visibleYears =>
      isAdmin ? const [1, 2, 3, 4] : [lockedYear ?? 1];
}
