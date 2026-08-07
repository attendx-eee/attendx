import 'dart:ui';

import 'document_text.dart';
import 'grid_detector.dart';

/// One class read out of a timetable cell.
class ParsedPeriod {
  final String day;

  /// Column index in the detected grid. Mapped to a real period number
  /// once the time header is understood.
  final int column;

  final String subject;

  /// Faculty initials as printed — "KRS", "CHVVSBR".
  final List<String> facultyCodes;

  /// "A", "B", or empty for the whole class.
  final String batch;

  /// Cell text that didn't parse into anything, kept so a reviewer can
  /// see what was ignored rather than wondering what was lost.
  final String raw;

  const ParsedPeriod({
    required this.day,
    required this.column,
    required this.subject,
    this.facultyCodes = const [],
    this.batch = '',
    this.raw = '',
  });

  bool get isEmpty => subject.isEmpty;
}

/// A row of the "KV: Prof. K.Vaisakh; PMR: Prof P. Mallikarjuna Rao"
/// legend printed under the grid.
class ParsedFaculty {
  final String code;
  final String name;

  const ParsedFaculty({required this.code, required this.name});
}

/// Everything read off one timetable image.
class ParsedTimetable {
  final List<ParsedPeriod> periods;
  final List<ParsedFaculty> faculty;

  /// Column header times, in printed order — "9:00am – 9:50am".
  final List<String> columnTimes;

  /// Columns that turned out to be break or lunch, not classes.
  final Set<int> nonTeachingColumns;

  const ParsedTimetable({
    required this.periods,
    required this.faculty,
    required this.columnTimes,
    required this.nonTeachingColumns,
  });

  bool get isEmpty => periods.isEmpty;
}

/// Reads an AU-style weekly timetable out of recognised page text.
///
/// This is the part that doesn't exist anywhere and can't be bought: an
/// OCR engine returns "IoT (KRS, AP) – Batch A" as a string, and turning
/// that into *subject IoT, taught by K Ramasudha and Abhishek Pintu, for
/// lab batch A* is entirely domain knowledge about how this department
/// prints its timetables.
///
/// Written to be forgiving, because the input is a photograph:
/// - day names are matched on a prefix, so "MONDAY", "Monday" and a
///   half-read "MONDA" all land;
/// - a cell spanning two periods appears in both columns, which is
///   correct — it *is* two periods of the same class;
/// - anything unrecognised is preserved in [ParsedPeriod.raw] rather
///   than dropped, so the review screen can show what was skipped.
class TimetableParser {
  const TimetableParser._();

  static const TimetableParser instance = TimetableParser._();

  static const List<String> _days = [
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY',
  ];

  /// Column headings that mean "no class here".
  static final RegExp _nonTeaching =
      RegExp(r'\b(BREAK|LUNCH|INTERVAL|RECESS)\b', caseSensitive: false);

  /// "9:00am – 9:50am", "9.00 AM - 9.50 AM", "09:00-09:50".
  static final RegExp _timeRange = RegExp(
    r'(\d{1,2})[:.](\d{2})\s*([ap]\.?m\.?)?\s*[–\-—to]+\s*(\d{1,2})[:.](\d{2})\s*([ap]\.?m\.?)?',
    caseSensitive: false,
  );

  /// "(KRS, AP)" or "(PMR)" — the faculty codes inside a cell.
  static final RegExp _codesInBrackets = RegExp(r'\(([^)]*)\)');

  /// "Batch A", "batch-B".
  static final RegExp _batch =
      RegExp(r'batch\s*[-–]?\s*([A-Z])', caseSensitive: false);

  /// "KV: Prof. K.Vaisakh" — one legend entry.
  static final RegExp _legendEntry = RegExp(
    r'([A-Z][A-Z0-9]{1,10})\s*[:\-]\s*((?:Prof|Dr|Mr|Mrs|Ms|Sri|Smt)?\.?\s*[^;,]{2,60})',
  );

  ParsedTimetable parse(DocumentText doc) {
    final grid = GridDetector.instance.detect(doc);

    if (!grid.isUsable) {
      return const ParsedTimetable(
        periods: [],
        faculty: [],
        columnTimes: [],
        nonTeachingColumns: {},
      );
    }

    // ---- which row is which day ----
    final dayRows = <int, String>{};
    for (var row = 0; row < grid.rowCount; row++) {
      final text = doc
          .textIn(Rect.fromLTRB(grid.columnEdges.first, grid.rowEdges[row],
              grid.columnEdges.last, grid.rowEdges[row + 1]))
          .toUpperCase();

      for (final day in _days) {
        // Prefix match: OCR clips the tail of a word far more often than
        // the head, and no two weekday names share four leading letters.
        if (text.contains(day) || text.contains(day.substring(0, 4))) {
          dayRows[row] = day;
          break;
        }
      }
    }

    // ---- column times, from whichever row holds them ----
    final columnTimes = <String>[];
    final nonTeaching = <int>{};
    var headerRow = -1;

    for (var row = 0; row < grid.rowCount; row++) {
      if (dayRows.containsKey(row)) continue;

      final rowText = doc.textIn(Rect.fromLTRB(grid.columnEdges.first,
          grid.rowEdges[row], grid.columnEdges.last, grid.rowEdges[row + 1]));

      if (_timeRange.hasMatch(rowText)) {
        headerRow = row;
        break;
      }
    }

    if (headerRow >= 0) {
      for (var col = 0; col < grid.columnCount; col++) {
        final cell = doc.textIn(grid.cell(headerRow, col));
        final match = _timeRange.firstMatch(cell);
        columnTimes.add(match?.group(0)?.trim() ?? '');
        if (_nonTeaching.hasMatch(cell)) nonTeaching.add(col);
      }
    }

    // ---- the cells themselves ----
    final periods = <ParsedPeriod>[];

    dayRows.forEach((row, day) {
      for (var col = 0; col < grid.columnCount; col++) {
        if (nonTeaching.contains(col)) continue;

        final cell = doc.textIn(grid.cell(row, col));
        if (cell.trim().isEmpty) continue;

        // The day name itself occupies the first column.
        if (_days.any((d) => cell.toUpperCase().contains(d.substring(0, 4)))) {
          continue;
        }
        if (_nonTeaching.hasMatch(cell)) {
          nonTeaching.add(col);
          continue;
        }

        periods.add(_parseCell(day: day, column: col, text: cell));
      }
    });

    return ParsedTimetable(
      periods: periods.where((p) => !p.isEmpty).toList(),
      faculty: parseLegend(doc),
      columnTimes: columnTimes,
      nonTeachingColumns: nonTeaching,
    );
  }

  /// Pulls subject, faculty codes and batch out of one cell.
  ParsedPeriod _parseCell({
    required String day,
    required int column,
    required String text,
  }) {
    var working = text.trim();

    // Batch first, so "– Batch A" doesn't end up in the subject.
    final batchMatch = _batch.firstMatch(working);
    final batch = batchMatch?.group(1)?.toUpperCase() ?? '';
    if (batchMatch != null) {
      working = working.replaceRange(batchMatch.start, batchMatch.end, '');
    }

    // Then the bracketed codes.
    final codes = <String>[];
    final codeMatch = _codesInBrackets.firstMatch(working);
    if (codeMatch != null) {
      final inner = codeMatch.group(1) ?? '';
      for (final part in inner.split(RegExp(r'[,/]'))) {
        final code = part.trim().toUpperCase();
        // Empty brackets are common on a draft timetable where the
        // teacher hasn't been assigned yet.
        if (code.isNotEmpty && RegExp(r'^[A-Z0-9]{1,12}$').hasMatch(code)) {
          codes.add(code);
        }
      }
      working = working.replaceRange(codeMatch.start, codeMatch.end, '');
    }

    // Whatever's left, minus separators, is the subject.
    final subject = working
        .replaceAll(RegExp(r'[–\-—]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return ParsedPeriod(
      day: day,
      column: column,
      subject: subject,
      facultyCodes: codes,
      batch: batch,
      raw: text.trim(),
    );
  }

  /// Reads the "KV: Prof. K.Vaisakh; PMR: ..." legend.
  ///
  /// Worth its own pass because it's what makes the codes in the grid
  /// mean anything — and because it lets the import create the faculty
  /// records rather than asking the admin to type twelve names that are
  /// already printed on the page.
  List<ParsedFaculty> parseLegend(DocumentText doc) {
    final out = <String, String>{};

    for (final block in doc.blocks) {
      final line = block.normalised;
      if (!line.contains(':')) continue;

      for (final match in _legendEntry.allMatches(line)) {
        final code = match.group(1)?.trim().toUpperCase() ?? '';
        var name = match.group(2)?.trim() ?? '';

        name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

        if (code.isEmpty || name.length < 3) continue;
        // A day name followed by a colon isn't a legend entry.
        if (_days.any((d) => d.startsWith(code))) continue;

        out.putIfAbsent(code, () => name);
      }
    }

    return out.entries
        .map((e) => ParsedFaculty(code: e.key, name: e.value))
        .toList()
      ..sort((a, b) => a.code.compareTo(b.code));
  }
}
