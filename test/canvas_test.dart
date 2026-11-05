import 'package:ascanvas/ascanvas.dart';
import 'package:test/test.dart';

void main() {
  group('Canvas', () {
    test('renders a glyph with colours and then stays quiet', () {
      final canvas = Canvas(4, 2);
      canvas.put(1, 1, 'X', fg: Colour.red, bg: Colour.blue);

      expect(
        canvas.renderDiff(ColourMode.basic),
        '\x1b[2;2H\x1b[0;31;44mX\x1b[0m',
      );
      expect(canvas.renderDiff(ColourMode.basic), '');
    });

    test('only repaints cells that changed', () {
      final canvas = Canvas(3, 1);
      canvas.put(0, 0, 'A');
      canvas.renderDiff(ColourMode.basic);

      canvas.put(1, 0, 'B');
      expect(canvas.renderDiff(ColourMode.basic), '\x1b[1;2HB\x1b[0m');
    });

    test('moves the cursor when a changed run is not adjacent', () {
      final canvas = Canvas(5, 2);
      canvas.put(0, 0, 'A');
      canvas.renderDiff(ColourMode.basic);

      canvas.put(4, 1, 'B');
      expect(canvas.renderDiff(ColourMode.basic), '\x1b[2;5HB\x1b[0m');
    });

    test('invalidate forces a full repaint', () {
      final canvas = Canvas(2, 1);
      canvas.renderDiff(ColourMode.basic);
      canvas.invalidate();
      expect(canvas.renderDiff(ColourMode.basic), '\x1b[1;1H  \x1b[0m');
    });

    test('clips text at the right edge', () {
      final canvas = Canvas(4, 1);
      canvas.text(2, 0, 'abcd');
      expect(canvas.cellAt(2, 0)!.glyph, 'a');
      expect(canvas.cellAt(3, 0)!.glyph, 'b');
      expect(canvas.cellAt(4, 0), isNull);
    });

    test('clips fills on every edge', () {
      final canvas = Canvas(3, 3);
      canvas.fill(-1, -1, 3, 3, glyph: '#');
      expect(canvas.cellAt(0, 0)!.glyph, '#');
      expect(canvas.cellAt(1, 1)!.glyph, '#');
      expect(canvas.cellAt(2, 0)!.isBlank, isTrue);
      expect(canvas.cellAt(0, 2)!.isBlank, isTrue);
    });

    test('draws box borders', () {
      final canvas = Canvas(4, 3);
      canvas.box(0, 0, 4, 3);
      expect(canvas.cellAt(0, 0)!.glyph, '┌');
      expect(canvas.cellAt(3, 0)!.glyph, '┐');
      expect(canvas.cellAt(0, 2)!.glyph, '└');
      expect(canvas.cellAt(3, 2)!.glyph, '┘');
      expect(canvas.cellAt(1, 0)!.glyph, '─');
      expect(canvas.cellAt(0, 1)!.glyph, '│');
    });

    test('clear can apply a background colour', () {
      final canvas = Canvas(2, 2);
      canvas.clear(bg: Colour.blue);
      final cell = canvas.cellAt(0, 0)!;
      expect(cell.glyph, ' ');
      expect(cell.bg, Colour.blue);
    });

    test('ignores out-of-bounds paints', () {
      final canvas = Canvas(2, 2);
      canvas.put(-1, 0, 'X');
      canvas.put(2, 0, 'X');
      canvas.put(0, 2, 'X');
      expect(canvas.renderDiff(ColourMode.basic), '');
    });
  });
}
