# asciiv

A small, dependency-free Dart library for painting glyphs in any foreground
and background colour at any position on an ANSI terminal.

It keeps a double-buffered grid and sends only the cells that changed, so
redrawing a screen does not flicker. Colours are automatically reduced to the
palette the terminal supports.

## Features

- Paint any glyph at any row/column with optional foreground and background
  colour.
- Fill rectangles, draw text, and draw single- or double-line boxes.
- ANSI 16, xterm 256, and 24-bit RGB colours, with automatic downsampling.
- Automatic colour-mode detection (`COLORTERM`, `TERM`), with manual override.
- Alternate-screen, hidden cursor, raw single-key input, and clean restore on
  exit (including Ctrl-C/SIGTERM).
- Incremental rendering: only changed cells are written to the terminal.
- No runtime dependencies.

## Quick start

```dart
import 'package:asciiv/asciiv.dart';

Future<void> main() async {
  final terminal = Terminal();
  await terminal.open();

  try {
    final canvas = Canvas(terminal.columns, terminal.rows);

    canvas.text(2, 1, 'Hello, asciiv!', fg: Colour.brightCyan);
    canvas.put(2, 3, 'X', fg: Colour.brightYellow, bg: Colour.blue);
    canvas.fill(2, 5, 20, 3, bg: Colour.rgb(20, 20, 40));
    canvas.box(1, 0, 24, 9, fg: Colour.brightMagenta);

    await terminal.present(canvas);
    await terminal.keys.first; // wait for any key
  } finally {
    await terminal.close();
  }
}
```

Run the demo:

```sh
dart run example/paint.dart
```

## Painting API

`Canvas(width, height)` is a grid of `Cell`s. Coordinates are zero-based,
`x` is the column and `y` is the row.

| Method | Purpose |
| --- | --- |
| `put(x, y, glyph, {fg, bg})` | Paint one glyph. |
| `text(x, y, text, {fg, bg})` | Paint a string, one cell per rune. |
| `fill(x, y, w, h, {glyph, fg, bg})` | Fill a rectangle. |
| `box(x, y, w, h, {fg, bg, doubleLine})` | Draw a border. |
| `clear({bg})` | Reset the canvas, optionally to a background colour. |
| `cellAt(x, y)` | Read a cell (or `null` outside the canvas). |
| `invalidate()` | Force the next render to repaint everything. |

All painting is clipped to the canvas, so off-screen coordinates are harmless.
`fg` and `bg` are `Colour?`; `null` leaves the terminal's default colour.

`renderDiff(mode)` returns the ANSI string that updates the terminal and
advances the internal front buffer. `Terminal.present(canvas)` does that and
flushes stdout.

## Colours

```dart
Colour.red                       // ANSI palette entry 1
Colour.brightBlue                // ANSI palette entry 12
Colour.indexed(200)              // xterm palette entry 200
Colour.rgb(255, 128, 0)          // 24-bit colour
```

`ColourMode.detect()` chooses `trueColour`, `indexed`, or `basic` from the
environment. You can override it:

```dart
final terminal = Terminal(colourMode: ColourMode.indexed);
```

If a colour is unavailable in the selected mode, the closest palette entry is
used. For example, `Colour.rgb(255, 0, 0)` becomes SGR `38;5;196` on a
256-colour terminal and bright red on a 16-colour terminal.

## Key input

`terminal.keys` is a broadcast stream of `KeyEvent`s. Named keys are available
through `SpecialKey`; printable input appears as `KeyEvent.character`.

```dart
await for (final event in terminal.keys) {
  if (event.special == SpecialKey.left) { /* ... */ }
  if (event.character == 'q') break;
}
```

The parser handles CSI and SS3 cursor sequences, fragmented UTF-8, and lone
Escape key presses.

## Tetris

A small Tetris-like game is included as an end-to-end test of the library:

```sh
dart run bin/tetris.dart
# or, after activation:
dart run asciiv:tetris
```

Controls:

| Key | Action |
| --- | --- |
| Left / Right or A / D | Move |
| Up / W / X | Rotate clockwise |
| Z | Rotate counter-clockwise |
| Down / S | Soft drop |
| Space or Enter | Hard drop |
| P | Pause |
| R | Restart |
| Q / Escape | Quit |

It needs a terminal of at least 40x22 cells.

## Tests

```sh
dart pub get
dart test
```

## Limitations

- Glyphs are assumed to occupy exactly one terminal cell. Wide CJK characters,
  emoji, and combining marks are not measured or handled specially.
- Raw keyboard mode and terminal size detection rely on POSIX terminal
  facilities (`stdin.lineMode`, `stdout.terminalColumns`). The library is aimed
  at Linux/macOS terminals; other platforms may work but are untested.
- Changing the terminal size mid-session is not detected. Create a new canvas
  (or call `invalidate()` after clearing) if the size changes.
- Output uses ANSI escape sequences, so the terminal must support them.
