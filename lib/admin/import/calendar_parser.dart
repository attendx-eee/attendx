import '../models/holiday_model.dart';
import 'document_text.dart';

/// A dated thing found on an academic calendar.
class ParsedCalendarEntry {
  final String label;

  /// yyyy-MM-dd
  final String from;

  /// yyyy-MM-dd — same as [from] for a single day.
  final String to;

  /// True when this closes the college; false for exam windows, which
  /// are dated but still working days.
  final bool isClosure;

  const ParsedCalendarEntry({
    required this.label,
    required this.from,
    required this.to,
    required this.isClosure,
  });

  int get dayCount {
    final a = DateTime.tryParse(from);
    final b = DateTime.tryParse(to);
    if (a == null || b == null) return 0;
    return b.difference(a).inDays + 1;
  }

  HolidayRange toRange() => HolidayRange(
        from: from,
        to: to,
        name: label,
        reason: 'From the academic calendar',
      );
}

/// Reads dates off an academic calendar page.
///
/// Written from scratch against the shape AU actually prints: a table of
/// labelled rows where the right-hand column carries either a single
/// date or a "from to" pair, in `dd-mm-yyyy`.
///
/// The hard part isn't finding dates — it's knowing which ones close the
/// college. "Dussehra Vacation 15-10-2026 to 21-10-2026" is a closure;
/// "Commencement of End Semester Examinations 9-11-2026" very much
/// isn't, and importing it as a holiday would wipe out attendance for
/// exam week. So the label decides, and anything unrecognised is
/// reported without being treated as a closure.
class CalendarParser {
  const CalendarParser._();

  static const CalendarParser instance = CalendarParser._();

  /// `15-10-2026`, `15/10/2026`, `4-11-2026`.
  static final RegExp _date =
      RegExp(r'(\d{1,2})\s*[-/.]\s*(\d{1,2})\s*[-/.]\s*(\d{4})');

  /// Labels that mean the college is shut.
  static final RegExp _closureLabel = RegExp(
    r'\b(vacation|holiday|holidays|break|recess|closed)\b',
    caseSensitive: false,
  );

  /// Labels that are dated but are still working days.
  static final RegExp _workingLabel = RegExp(
    r'\b(examination|examinations|exam|commencement|classwork|class work|'
    r'starting|closing|submission|marks|semester)\b',
    caseSensitive: false,
  );

  /// Everything dated on the page.
  List<ParsedCalendarEntry> parse(DocumentText doc) {
    final out = <ParsedCalendarEntry>[];

    for (final block in doc.blocks) {
      final line = block.normalised;
      final dates = _date.allMatches(line).toList();
      if (dates.isEmpty) continue;

      final label = _labelFor(line, doc, block);
      if (label.isEmpty) continue;

      final isClosure = _closureLabel.hasMatch(label) &&
          !_workingLabel.hasMatch(label);

      final from = _iso(dates.first);
      // A second date on the same line is the end of a range. More than
      // two means the line is a table row of unrelated dates, and
      // guessing a range across them would invent a closure.
      final to = dates.length == 2 ? _iso(dates[1]) : from;

      if (from == null || to == null) continue;

      out.add(ParsedCalendarEntry(
        label: label,
        from: from,
        to: to,
        isClosure: isClosure,
      ));
    }

    return out;
  }

  /// Just the closures, ready to import as holidays.
  List<HolidayRange> closures(DocumentText doc) => parse(doc)
      .where((e) => e.isClosure)
      .map((e) => e.toRange())
      .toList();

  /// The text describing a dated line.
  ///
  /// Usually on the same line, to the left of the dates. When the line
  /// is only dates — common in a table where the label sits in its own
  /// column — the nearest text to the left on the same row is used
  /// instead.
  String _labelFor(String line, DocumentText doc, TextBlock block) {
    final beforeFirstDate = line.split(_date).first.trim();
    if (beforeFirstDate.length >= 4) return beforeFirstDate;

    // Look leftward on the same row.
    final rowTop = block.bounds.top - block.bounds.height * 0.4;
    final rowBottom = block.bounds.bottom + block.bounds.height * 0.4;

    final leftwards = doc
        .inRows(rowTop, rowBottom)
        .where((b) => b.bounds.right <= block.bounds.left)
        .toList();

    if (leftwards.isEmpty) return beforeFirstDate;

    // Nearest first — the label is the thing immediately beside it.
    leftwards.sort((a, b) => b.bounds.right.compareTo(a.bounds.right));
    final candidate = leftwards.first.normalised.trim();

    return candidate.length >= 4 ? candidate : beforeFirstDate;
  }

  String? _iso(RegExpMatch m) {
    final day = int.tryParse(m.group(1) ?? '');
    final month = int.tryParse(m.group(2) ?? '');
    final year = int.tryParse(m.group(3) ?? '');

    if (day == null || month == null || year == null) return null;
    if (day < 1 || day > 31 || month < 1 || month > 12) return null;
    if (year < 2000 || year > 2100) return null;

    return '$year-${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }
}
