import 'dart:math' as math;
import 'dart:ui';

/// One run of text found on a page, with where it sits.
///
/// Position is everything for a timetable: "IoT (KRS, AP)" means nothing
/// until you know it sits in the Monday row under the 9:00 column. The
/// recogniser's job ends at producing these; every layer above works on
/// geometry, not pixels.
class TextBlock {
  final String text;
  final Rect bounds;

  /// 0-1 where the engine reports it; 1 when it doesn't.
  final double confidence;

  const TextBlock({
    required this.text,
    required this.bounds,
    this.confidence = 1,
  });

  double get centreX => bounds.center.dx;
  double get centreY => bounds.center.dy;

  String get normalised => text.replaceAll(RegExp(r'\s+'), ' ').trim();

  @override
  String toString() =>
      '"$text" @ (${bounds.left.toInt()},${bounds.top.toInt()})';
}

/// A whole page of recognised text.
class DocumentText {
  final List<TextBlock> blocks;
  final Size pageSize;

  const DocumentText({required this.blocks, required this.pageSize});

  bool get isEmpty => blocks.isEmpty;

  /// Blocks whose vertical centre falls inside [top]..[bottom].
  List<TextBlock> inRows(double top, double bottom) => blocks
      .where((b) => b.centreY >= top && b.centreY <= bottom)
      .toList()
    ..sort((a, b) => a.centreX.compareTo(b.centreX));

  /// Blocks inside a rectangle, reading order (top-to-bottom, then
  /// left-to-right within a line).
  List<TextBlock> inside(Rect area) {
    final hits = blocks.where((b) {
      final o = b.bounds.intersect(area);
      if (o.width <= 0 || o.height <= 0) return false;
      // Majority overlap, so a block straddling a grid line is claimed
      // by the cell it mostly sits in rather than by both.
      final blockArea = b.bounds.width * b.bounds.height;
      return blockArea > 0 && (o.width * o.height) / blockArea > 0.5;
    }).toList();

    hits.sort((a, b) {
      // Same line if their vertical centres are within half a line
      // height — OCR rarely aligns baselines exactly.
      final lineHeight = math.max(a.bounds.height, b.bounds.height);
      if ((a.centreY - b.centreY).abs() < lineHeight * 0.5) {
        return a.centreX.compareTo(b.centreX);
      }
      return a.centreY.compareTo(b.centreY);
    });

    return hits;
  }

  /// Joined text of a rectangle.
  String textIn(Rect area) =>
      inside(area).map((b) => b.normalised).where((t) => t.isNotEmpty).join(' ');

  /// The first block whose text matches, case-insensitively.
  TextBlock? find(Pattern pattern) {
    for (final b in blocks) {
      if (b.normalised.toLowerCase().contains(
          pattern is String ? pattern.toLowerCase() : pattern)) {
        return b;
      }
    }
    return null;
  }
}

/// Turns an image into positioned text.
///
/// Deliberately an interface with no implementation here. The character
/// recognition step is the one part of this pipeline that genuinely
/// wants a model trained on millions of documents, and swapping which
/// engine provides it — an on-device one today, a custom-trained one
/// later — shouldn't touch a line of the parsing above it.
///
/// Everything else in this folder is written from scratch and works on
/// [DocumentText] alone, so it can be tested without a camera, an
/// image, or an engine.
abstract class TextRecogniser {
  /// [imagePath] is a file on disk.
  Future<DocumentText> recognise(String imagePath);
}
