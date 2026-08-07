import 'dart:ui';

// Aliased: ML Kit exports its own `TextBlock`, which collides with ours.
// Ours is the one the parsers are written against, so the package gets
// the prefix rather than the domain type.
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlkit;

import 'document_text.dart';

/// The only part of the import pipeline that uses a pretrained model.
///
/// Turns pixels into positioned characters and stops there. It knows
/// nothing about timetables, days, periods or holidays — all of that is
/// parsed from [DocumentText] by code in this folder that can be tested
/// without an image, a camera, or this package.
///
/// That boundary is deliberate. Character recognition is the one step
/// that genuinely benefits from a model trained on millions of
/// documents, and it's also the step most likely to be replaced. Keeping
/// it behind [TextRecogniser] means swapping engines later touches this
/// file and nothing else.
class MlKitRecogniser implements TextRecogniser {
  MlKitRecogniser();

  final mlkit.TextRecognizer _recogniser =
      mlkit.TextRecognizer(script: mlkit.TextRecognitionScript.latin);

  @override
  Future<DocumentText> recognise(String imagePath) async {
    final input = mlkit.InputImage.fromFilePath(imagePath);
    final result = await _recogniser.processImage(input);

    final blocks = <TextBlock>[];
    var maxRight = 0.0;
    var maxBottom = 0.0;

    // Lines, not blocks. ML Kit's "block" can swallow a whole column of
    // a table into one region, which destroys the row structure the
    // grid detector depends on. A line is the largest unit that's
    // reliably one row of one cell.
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final box = line.boundingBox;
        blocks.add(TextBlock(
          text: line.text,
          bounds: Rect.fromLTRB(
            box.left.toDouble(),
            box.top.toDouble(),
            box.right.toDouble(),
            box.bottom.toDouble(),
          ),
        ));

        if (box.right > maxRight) maxRight = box.right.toDouble();
        if (box.bottom > maxBottom) maxBottom = box.bottom.toDouble();
      }
    }

    // ML Kit doesn't report page dimensions, and the grid detector needs
    // them to scale its minimum-gap thresholds. The furthest extent of
    // any recognised text is a close enough stand-in — a document
    // always has text near its edges.
    return DocumentText(
      blocks: blocks,
      pageSize: Size(maxRight, maxBottom),
    );
  }

  void dispose() => _recogniser.close();
}
