# ascanvas

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
- Optional mouse reporting for clicks, drags, motion, and wheel events.
- Incremental rendering: only changed cells are written to the terminal.
- No runtime dependencies.

## Quick start

```dart
import 'package:ascanvas/ascanvas.dart';

Future<void> main() async {
  final terminal = Terminal();
  await terminal.open();

  try {
    final canvas = Canvas(terminal.columns, terminal.rows);

    canvas.text(2, 1, 'Hello, ascanvas!', fg: Colour.brightCyan);
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

Run the demos:

```sh
dart run example/paint.dart
dart run example/mouse.dart
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

## Mouse input

Mouse reporting is opt-in because it intercepts normal click-drag text
selection. Choose how much motion the terminal should report:

```dart
final terminal = Terminal(mouseMode: MouseMode.drag);
```

| Mode | Reports |
| --- | --- |
| `MouseMode.off` | Nothing (default) |
| `MouseMode.click` | Button presses and releases |
| `MouseMode.drag` | Presses, releases, and motion while a button is held |
| `MouseMode.motion` | All mouse movement |

Mouse events arrive through `terminal.mouse`, or together with key events on
`terminal.events`:

```dart
await for (final event in terminal.mouse) {
  print('${event.action} ${event.button} at ${event.column},${event.row}');
  print('shift=${event.shift} alt=${event.alt} ctrl=${event.ctrl}');
}
```

`MouseEvent.column` and `row` are zero-based terminal cells, matching `Canvas`
coordinates. If you draw a canvas inset from the terminal edges, subtract its
origin before painting. Presses, releases, moves, drags, and wheel scrolling are
distinguished by `MouseAction`; `MouseButton` includes the wheel directions and
back/forward buttons.

The terminal is switched to SGR mouse encoding (`1006`) plus the selected
tracking mode (`1000`/`1002`/`1003`) on `open()`, and every mouse mode is
disabled again on `close()`, including clean-up on Ctrl-C/SIGTERM. Hold Shift
while clicking if the terminal normally uses Shift for text selection.

## Tetris

A small Tetris-like game is included as an end-to-end test of the library:

```sh
dart run bin/tetris.dart
# or, after activation:
dart run ascanvas:tetris
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
- Mouse support depends on the terminal implementing ANSI tracking modes. SGR
  and legacy X10 reports are decoded; pixel-precise coordinates are not
  available.
- Output uses ANSI escape sequences, so the terminal must support them.
