import 'colour.dart';

/// One character cell on a [Canvas].
class Cell {
  /// Creates a cell containing [glyph], painted in [fg] and [bg].
  const Cell(this.glyph, {this.fg, this.bg});

  /// The glyph to display. It should occupy a single terminal cell.
  final String glyph;

  /// Foreground colour, or `null` for the terminal default.
  final Colour? fg;

  /// Background colour, or `null` for the terminal default.
  final Colour? bg;

  /// A plain space using the terminal's default colours.
  static const blank = Cell(' ');

  /// Whether this is a plain space with default colours.
  bool get isBlank => glyph == ' ' && fg == null && bg == null;

  @override
  bool operator ==(Object other) =>
      other is Cell && other.glyph == glyph && other.fg == fg && other.bg == bg;

  @override
  int get hashCode => Object.hash(glyph, fg, bg);

  @override
  String toString() => 'Cell(${glyph.codeUnits}, fg: $fg, bg: $bg)';
}

/// A double-buffered grid of characters.
///
/// Paint into the canvas with [put], [text], [fill] or [box], then call
/// [renderDiff] (usually through `Terminal.present`) to obtain only the ANSI
/// output needed to update the terminal.
class Canvas {
  /// Creates a canvas of [width] columns and [height] rows.
  Canvas(this.width, this.height)
      : assert(width > 0, 'width must be positive'),
        assert(height > 0, 'height must be positive'),
        _cells = List.filled(width * height, Cell.blank),
        _presented = List.filled(width * height, Cell.blank);

  /// Width in terminal columns.
  final int width;

  /// Height in terminal rows.
  final int height;

  final List<Cell> _cells;
  final List<Cell> _presented;
  bool _forceRepaint = false;

  /// Returns the cell at [x], [y], or `null` when outside the canvas.
  Cell? cellAt(int x, int y) {
    if (!_contains(x, y)) return null;
    return _cells[y * width + x];
  }

  /// Replaces the whole canvas with blank cells.
  ///
  /// If [bg] is given, the entire canvas is painted with that background.
  void clear({Colour? bg}) {
    final blank = bg == null ? Cell.blank : Cell(' ', bg: bg);
    _cells.fillRange(0, _cells.length, blank);
  }

  /// Paints [glyph] at [x], [y].
  ///
  /// Coordinates outside the canvas are ignored. [glyph] is expected to occupy
  /// a single terminal cell; multi-codepoint glyphs are written as-is but the
  /// cursor advance is still assumed to be one cell.
  void put(int x, int y, String glyph, {Colour? fg, Colour? bg}) {
    if (!_contains(x, y) || glyph.isEmpty) return;
    _cells[y * width + x] = Cell(glyph, fg: fg, bg: bg);
  }

  /// Paints [text] starting at [x], [y].
  ///
  /// Characters that fall outside the canvas are clipped. Each rune is given
  /// one cell, which is correct for ASCII and most Latin text.
  void text(int x, int y, String text, {Colour? fg, Colour? bg}) {
    var column = x;
    for (final rune in text.runes) {
      put(column, y, String.fromCharCode(rune), fg: fg, bg: bg);
      column++;
    }
  }

  /// Fills a rectangle with [glyph].
  ///
  /// The rectangle is clipped to the canvas.
  void fill(
    int x,
    int y,
    int rectangleWidth,
    int rectangleHeight, {
    String glyph = ' ',
    Colour? fg,
    Colour? bg,
  }) {
    if (rectangleWidth <= 0 || rectangleHeight <= 0 || glyph.isEmpty) return;
    final left = x < 0 ? 0 : x;
    final top = y < 0 ? 0 : y;
    final right = (x + rectangleWidth).clamp(0, width);
    final bottom = (y + rectangleHeight).clamp(0, height);
    for (var row = top; row < bottom; row++) {
      for (var column = left; column < right; column++) {
        put(column, row, glyph, fg: fg, bg: bg);
      }
    }
  }

  /// Draws a rectangular border.
  ///
  /// [rectangleWidth] and [rectangleHeight] count terminal cells. Set
  /// [doubleLine] to use double-line box drawing characters. The border is
  /// clipped to the canvas.
  void box(
    int x,
    int y,
    int rectangleWidth,
    int rectangleHeight, {
    Colour? fg,
    Colour? bg,
    bool doubleLine = false,
  }) {
    if (rectangleWidth <= 0 || rectangleHeight <= 0) return;
    final characters = doubleLine
        ? const ['╔', '╗', '╚', '╝', '═', '║']
        : const ['┌', '┐', '└', '┘', '─', '│'];

    if (rectangleWidth == 1 || rectangleHeight == 1) {
      fill(
        x,
        y,
        rectangleWidth,
        rectangleHeight,
        glyph: characters[4],
        fg: fg,
        bg: bg,
      );
      return;
    }

    put(x, y, characters[0], fg: fg, bg: bg);
    put(x + rectangleWidth - 1, y, characters[1], fg: fg, bg: bg);
    put(x, y + rectangleHeight - 1, characters[2], fg: fg, bg: bg);
    put(
      x + rectangleWidth - 1,
      y + rectangleHeight - 1,
      characters[3],
      fg: fg,
      bg: bg,
    );
    for (var column = x + 1; column < x + rectangleWidth - 1; column++) {
      put(column, y, characters[4], fg: fg, bg: bg);
      put(column, y + rectangleHeight - 1, characters[4], fg: fg, bg: bg);
    }
    for (var row = y + 1; row < y + rectangleHeight - 1; row++) {
      put(x, row, characters[5], fg: fg, bg: bg);
      put(x + rectangleWidth - 1, row, characters[5], fg: fg, bg: bg);
    }
  }

  /// Forces the next [renderDiff] to repaint every cell.
  void invalidate() {
    _forceRepaint = true;
  }

  /// Produces the ANSI output needed to bring the terminal up to date.
  ///
  /// Only cells that changed since the previous call are written. The internal
  /// front buffer is updated, so calling this again without changes returns an
  /// empty string. The returned string ends with an SGR reset.
  String renderDiff(ColourMode mode) {
    final buffer = StringBuffer();
    Colour? activeFg;
    Colour? activeBg;
    var wroteAnything = false;

    for (var y = 0; y < height; y++) {
      var x = 0;
      while (x < width) {
        if (!_isChanged(x, y)) {
          x++;
          continue;
        }

        final runStart = x;
        while (x < width && _isChanged(x, y)) {
          x++;
        }
        final runEnd = x;

        buffer.write('\x1b[${y + 1};${runStart + 1}H');

        for (var column = runStart; column < runEnd; column++) {
          final index = y * width + column;
          final cell = _cells[index];
          _presented[index] = cell;
          wroteAnything = true;

          if (cell.fg != activeFg || cell.bg != activeBg) {
            buffer.write('\x1b[0');
            final fg = cell.fg;
            if (fg != null) buffer.write(';${fg.foregroundCode(mode)}');
            final bg = cell.bg;
            if (bg != null) buffer.write(';${bg.backgroundCode(mode)}');
            buffer.write('m');
            activeFg = cell.fg;
            activeBg = cell.bg;
          }

          buffer.write(cell.glyph);
        }
      }
    }

    _forceRepaint = false;
    if (!wroteAnything) return '';

    // Return the terminal to a known state after the update.
    buffer.write('\x1b[0m');
    return buffer.toString();
  }

  bool _isChanged(int x, int y) {
    final index = y * width + x;
    return _forceRepaint || _cells[index] != _presented[index];
  }

  bool _contains(int x, int y) => x >= 0 && x < width && y >= 0 && y < height;
}
