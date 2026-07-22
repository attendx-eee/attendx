/// Thrown when a master-data record (faculty, subject, lab, room, time
/// slot, or lab batch) can't be deleted or reduced because it is still
/// referenced by at least one period in the timetable. The admin needs to
/// remove or reassign those periods first.
class MasterDataInUseException implements Exception {
  final String message;
  const MasterDataInUseException(this.message);

  @override
  String toString() => message;
}
