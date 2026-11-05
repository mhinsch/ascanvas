import 'dart:io';

/// How many colours the terminal can display.
enum ColourMode {
  /// The sixteen traditional ANSI colours.
  basic,

  /// The xterm 256-colour palette.
  indexed,

  /// 24-bit RGB colour.
  trueColour;

  /// Detects a sensible colour mode from the environment.
  ///
  /// [environment] defaults to [Platform.environment]. Pass a map in tests to
  /// avoid depending on the machine running them.
  static ColourMode detect({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final term = (env['TERM'] ?? '').toLowerCase();

    if (term == 'dumb') return ColourMode.basic;

    final colorTerm = (env['COLORTERM'] ?? '').toLowerCase();
    if (colorTerm == 'truecolor' || colorTerm == '24bit') {
      return ColourMode.trueColour;
    }
    if (term.contains('truecolor') || term.contains('24bit')) {
      return ColourMode.trueColour;
    }
    if (term.contains('256color')) return ColourMode.indexed;

    return ColourMode.basic;
  }
}

/// A terminal colour.
///
/// A colour is either an entry in the xterm palette (including the first
/// sixteen ANSI colours) or a 24-bit RGB value. When the terminal cannot show
/// the requested colour, the renderer picks the closest colour it can show.
class Colour {
  /// Creates a colour from the first sixteen ANSI palette entries.
  const Colour.basic(int value)
      : assert(value >= 0 && value < 16, 'basic colour must be 0..15'),
        index = value,
        r = null,
        g = null,
        b = null;

  /// Creates a colour from the xterm 256-colour palette.
  const Colour.indexed(int value)
      : assert(value >= 0 && value < 256, 'indexed colour must be 0..255'),
        index = value,
        r = null,
        g = null,
        b = null;

  /// Creates a 24-bit RGB colour.
  const Colour.rgb(int red, int green, int blue)
      : assert(red >= 0 && red < 256, 'red must be 0..255'),
        assert(green >= 0 && green < 256, 'green must be 0..255'),
        assert(blue >= 0 && blue < 256, 'blue must be 0..255'),
        index = -1,
        r = red,
        g = green,
        b = blue;

  /// Palette index, or `-1` for an RGB colour.
  final int index;

  /// Red component, or `null` for a palette colour.
  final int? r;

  /// Green component, or `null` for a palette colour.
  final int? g;

  /// Blue component, or `null` for a palette colour.
  final int? b;

  static const black = Colour.basic(0);
  static const red = Colour.basic(1);
  static const green = Colour.basic(2);
  static const yellow = Colour.basic(3);
  static const blue = Colour.basic(4);
  static const magenta = Colour.basic(5);
  static const cyan = Colour.basic(6);
  static const white = Colour.basic(7);
  static const brightBlack = Colour.basic(8);
  static const brightRed = Colour.basic(9);
  static const brightGreen = Colour.basic(10);
  static const brightYellow = Colour.basic(11);
  static const brightBlue = Colour.basic(12);
  static const brightMagenta = Colour.basic(13);
  static const brightCyan = Colour.basic(14);
  static const brightWhite = Colour.basic(15);

  /// Whether this is a 24-bit RGB colour.
  bool get isRgb => index < 0;

  /// The SGR parameters for this colour as a foreground.
  String foregroundCode(ColourMode mode) => _code(mode, background: false);

  /// The SGR parameters for this colour as a background.
  String backgroundCode(ColourMode mode) => _code(mode, background: true);

  String _code(ColourMode mode, {required bool background}) {
    switch (mode) {
      case ColourMode.basic:
        final base = isRgb
            ? nearestBasic(r!, g!, b!)
            : (index < 16 ? index : nearestBasicEntry(index));
        if (base < 8) return '${(background ? 40 : 30) + base}';
        return '${(background ? 100 : 90) + base - 8}';
      case ColourMode.indexed:
        final value = isRgb ? nearestIndexed(r!, g!, b!) : index;
        return '${background ? 48 : 38};5;$value';
      case ColourMode.trueColour:
        if (isRgb) return '${background ? 48 : 38};2;$r;$g;$b';
        return '${background ? 48 : 38};5;$index';
    }
  }

  /// The closest entry in the 256-colour xterm palette for an RGB colour.
  static int nearestIndexed(int red, int green, int blue) {
    final ri = _nearestCubeLevel(red);
    final gi = _nearestCubeLevel(green);
    final bi = _nearestCubeLevel(blue);
    final cubeIndex = 16 + 36 * ri + 6 * gi + bi;
    final cubeDistance = _distance(
      red,
      green,
      blue,
      _cubeLevels[ri],
      _cubeLevels[gi],
      _cubeLevels[bi],
    );

    final grey = ((red + green + blue) / 3).round();
    final greyIndex = ((grey - 8) / 10).round().clamp(0, 23);
    final greyValue = 8 + 10 * greyIndex;
    final greyDistance = _distance(
      red,
      green,
      blue,
      greyValue,
      greyValue,
      greyValue,
    );

    return greyDistance < cubeDistance ? 232 + greyIndex : cubeIndex;
  }

  /// The closest of the sixteen ANSI colours for an RGB colour.
  static int nearestBasic(int red, int green, int blue) {
    var best = 0;
    var bestDistance = 1 << 30;
    for (var i = 0; i < 16; i++) {
      final distance = _distance(
        red,
        green,
        blue,
        _ansi16[i * 3],
        _ansi16[i * 3 + 1],
        _ansi16[i * 3 + 2],
      );
      if (distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// The closest of the sixteen ANSI colours for a palette entry.
  static int nearestBasicEntry(int value) {
    final (red, green, blue) = _paletteRgb(value);
    return nearestBasic(red, green, blue);
  }

  static int _nearestCubeLevel(int value) {
    var best = 0;
    var bestDistance = 256;
    for (var i = 0; i < _cubeLevels.length; i++) {
      final distance = (value - _cubeLevels[i]).abs();
      if (distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    return best;
  }

  static int _distance(int r1, int g1, int b1, int r2, int g2, int b2) {
    final dr = r1 - r2;
    final dg = g1 - g2;
    final db = b1 - b2;
    return dr * dr + dg * dg + db * db;
  }

  static (int, int, int) _paletteRgb(int value) {
    if (value < 16) {
      return (
        _ansi16[value * 3],
        _ansi16[value * 3 + 1],
        _ansi16[value * 3 + 2]
      );
    }
    if (value < 232) {
      final n = value - 16;
      return (
        _cubeLevels[n ~/ 36],
        _cubeLevels[(n % 36) ~/ 6],
        _cubeLevels[n % 6],
      );
    }
    final grey = 8 + (value - 232) * 10;
    return (grey, grey, grey);
  }

  static const List<int> _cubeLevels = [0, 95, 135, 175, 215, 255];

  // Classic xterm values for the first sixteen colours.
  static const List<int> _ansi16 = [
    0,
    0,
    0,
    128,
    0,
    0,
    0,
    128,
    0,
    128,
    128,
    0,
    0,
    0,
    128,
    128,
    0,
    128,
    0,
    128,
    128,
    192,
    192,
    192,
    128,
    128,
    128,
    255,
    0,
    0,
    0,
    255,
    0,
    255,
    255,
    0,
    0,
    0,
    255,
    255,
    0,
    255,
    0,
    255,
    255,
    255,
    255,
    255,
  ];

  @override
  bool operator ==(Object other) =>
      other is Colour &&
      other.index == index &&
      other.r == r &&
      other.g == g &&
      other.b == b;

  @override
  int get hashCode => Object.hash(index, r, g, b);

  @override
  String toString() => isRgb ? 'Colour.rgb($r, $g, $b)' : 'Colour($index)';
}
