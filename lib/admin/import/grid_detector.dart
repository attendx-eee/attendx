import 'dart:math' as math;
import 'dart:ui';

import 'document_text.dart';

/// A detected table: the x positions of column boundaries and the y
/// positions of row boundaries.
class TableGrid {
  /// Column edges, left to right. n columns means n+1 edges.
  final List<double> columnEdges;

  /// Row edges, top to bottom.
  final List<double> rowEdges;

  const TableGrid({required this.columnEdges, required this.rowEdges});

  int get columnCount => math.max(0, columnEdges.length - 1);
  int get rowCount => math.max(0, rowEdges.length - 1);

  bool get isUsable => columnCount >= 2 && rowCount >= 2;

  Rect cell(int row, int column) => Rect.fromLTRB(
        columnEdges[column],
        rowEdges[row],
        columnEdges[column + 1],
        rowEdges[row + 1],
      );

  /// Which column an x coordinate falls in, or -1.
  int columnAt(double x) {
    for (var i = 0; i < columnCount; i++) {
      if (x >= columnEdges[i] && x < columnEdges[i + 1]) return i;
    }
    return -1;
  }

  int rowAt(double y) {
    for (var i = 0; i < rowCount; i++) {
      if (y >= rowEdges[i] && y < rowEdges[i + 1]) return i;
    }
    return -1;
  }
}

/// Finds a table's structure from the position of its text.
///
/// Written from scratch, and deliberately *not* by detecting drawn
/// lines. A photographed timetable has warped, broken and faint rules,
/// and some tables have no lines at all — but the text itself is always
/// laid out in columns, and that's a stronger signal than the ink.
///
/// The method is a projection profile: collect where text does and
/// doesn't appear along each axis, and treat the empty channels running
/// the full height (or width) of the block as the boundaries. It's the
/// classic document-layout approach and needs no training data, which
/// is what makes it work on the first photograph rather than the
/// thousandth.
class GridDetector {
  const GridDetector._();

  static const GridDetector instance = GridDetector._();

  /// A gap must be at least this fraction of the page to count as a
  /// column separator rather than a word space.
  static const double _minColumnGapRatio = 0.012;

  /// Likewise for rows — smaller, because line spacing is tighter than
  /// column spacing.
  static const double _minRowGapRatio = 0.008;

  /// Detects a grid over [area], or the whole page when null.
  TableGrid detect(DocumentText doc, {Rect? area}) {
    final region = area ??
        Rect.fromLTWH(0, 0, doc.pageSize.width, doc.pageSize.height);

    final blocks = doc.blocks.where((b) {
      final o = b.bounds.intersect(region);
      return o.width > 0 && o.height > 0;
    }).toList();

    if (blocks.isEmpty) {
      return const TableGrid(columnEdges: [], rowEdges: []);
    }

    final columnEdges = _edges(
      spans: blocks.map((b) => (b.bounds.left, b.bounds.right)).toList(),
      from: region.left,
      to: region.right,
      minGap: doc.pageSize.width * _minColumnGapRatio,
    );

    final rowEdges = _edges(
      spans: blocks.map((b) => (b.bounds.top, b.bounds.bottom)).toList(),
      from: region.top,
      to: region.bottom,
      minGap: doc.pageSize.height * _minRowGapRatio,
    );

    return TableGrid(columnEdges: columnEdges, rowEdges: rowEdges);
  }

  /// Boundaries derived from the empty channels between occupied spans.
  ///
  /// Merges overlapping spans first, then puts a boundary through the
  /// middle of every gap wider than [minGap]. Cutting through the middle
  /// rather than at an edge gives the most tolerance to a neighbouring
  /// cell whose text runs slightly wide.
  List<double> _edges({
    required List<(double, double)> spans,
    required double from,
    required double to,
    required double minGap,
  }) {
    if (spans.isEmpty) return [from, to];

    final sorted = [...spans]..sort((a, b) => a.$1.compareTo(b.$1));

    final merged = <(double, double)>[];
    var currentStart = sorted.first.$1;
    var currentEnd = sorted.first.$2;

    for (final span in sorted.skip(1)) {
      if (span.$1 <= currentEnd) {
        currentEnd = math.max(currentEnd, span.$2);
      } else {
        merged.add((currentStart, currentEnd));
        currentStart = span.$1;
        currentEnd = span.$2;
      }
    }
    merged.add((currentStart, currentEnd));

    final edges = <double>[from];

    for (var i = 0; i < merged.length - 1; i++) {
      final gap = merged[i + 1].$1 - merged[i].$2;
      if (gap >= minGap) {
        edges.add(merged[i].$2 + gap / 2);
      }
    }

    edges.add(to);
    return edges;
  }

  /// Estimates page skew from the baselines of text runs.
  ///
  /// A photographed page is never square to the camera, and a few
  /// degrees is enough to slide a cell's text into the neighbouring
  /// column. Returned in degrees; positive means rotated clockwise.
  ///
  /// Uses the median of pairwise slopes between horizontally adjacent
  /// blocks rather than a least-squares fit: a single wildly misplaced
  /// block — a signature, a stamp — would drag a mean badly, and the
  /// median simply ignores it.
  double estimateSkew(DocumentText doc) {
    final blocks = [...doc.blocks]
      ..sort((a, b) => a.centreY.compareTo(b.centreY));

    if (blocks.length < 4) return 0;

    final slopes = <double>[];

    for (var i = 0; i < blocks.length - 1; i++) {
      final a = blocks[i];
      final b = blocks[i + 1];

      // Only compare blocks that look like they're on the same line.
      final lineHeight = math.max(a.bounds.height, b.bounds.height);
      if ((a.centreY - b.centreY).abs() > lineHeight * 0.6) continue;

      final dx = b.centreX - a.centreX;
      if (dx.abs() < lineHeight) continue; // too close to be reliable

      slopes.add((b.centreY - a.centreY) / dx);
    }

    if (slopes.isEmpty) return 0;

    slopes.sort();
    final median = slopes[slopes.length ~/ 2];
    return math.atan(median) * 180 / math.pi;
  }
}
