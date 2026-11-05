import 'dart:io';

import 'package:ascanvas/ascanvas.dart';

/// Paints a palette and a colour gradient, then waits for a key press.
Future<void> main() async {
  if (!stdout.hasTerminal || !stdin.hasTerminal) {
    stderr.writeln('paint must be run in an interactive terminal.');
    exitCode = 1;
    return;
  }

  final terminal = Terminal();
  await terminal.open();
  try {
    final canvas = Canvas(terminal.columns, terminal.rows);
    _paint(canvas);

    canvas.text(
      1,
      terminal.rows - 2,
      'Press any key to exit.',
      fg: Colour.brightBlack,
    );

    await terminal.present(canvas);
    await terminal.keys.first;
  } finally {
    await terminal.close();
  }
}

void _paint(Canvas canvas) {
  canvas.text(1, 0, 'ascanvas', fg: Colour.brightCyan);
  canvas.text(8, 0, 'terminal painting demo', fg: Colour.brightBlack);

  // The sixteen ANSI colours.
  canvas.text(1, 2, 'ANSI 16', fg: Colour.brightBlack);
  for (var i = 0; i < 16; i++) {
    final colour = Colour.basic(i);
    final x = 1 + (i % 8) * 4;
    final y = 3 + (i ~/ 8) * 2;
    canvas.text(
      x,
      y,
      i.toString().padLeft(2),
      fg: i < 8 ? Colour.brightWhite : Colour.black,
      bg: colour,
    );
  }

  // The xterm 256-colour palette, one column per colour.
  final paletteTop = 8;
  canvas.text(1, paletteTop - 1, 'xterm 256', fg: Colour.brightBlack);
  for (var i = 0; i < 256; i++) {
    if (paletteTop + i ~/ 16 >= canvas.height - 2) break;
    canvas.put(
      1 + i % 16,
      paletteTop + i ~/ 16,
      ' ',
      bg: Colour.indexed(i),
    );
  }

  // A true-colour gradient; it is downsampled automatically on terminals that
  // cannot display 24-bit colour.
  final gradientX = 36;
  final gradientWidth = (canvas.width - gradientX - 2).clamp(1, 40);
  final gradientSpan = gradientWidth > 1 ? gradientWidth - 1 : 1;
  canvas.text(gradientX, 2, 'RGB gradient', fg: Colour.brightBlack);
  for (var row = 0; row < 8; row++) {
    for (var column = 0; column < gradientWidth; column++) {
      final red = (255 * column / gradientSpan).round();
      final green = (255 * row / 7).round();
      final blue = 255 - red;
      canvas.put(
        gradientX + column,
        3 + row,
        ' ',
        fg: Colour.rgb(red, green, blue),
        bg: Colour.rgb(red, green, blue),
      );
    }
  }

  if (canvas.width >= 58 && canvas.height >= 20) {
    canvas.box(gradientX, 12, 20, 7, fg: Colour.brightMagenta);
    canvas.text(gradientX + 2, 14, 'fg / bg painting',
        fg: Colour.brightMagenta);
    canvas.text(gradientX + 2, 15, 'at any position', fg: Colour.brightWhite);
    canvas.text(gradientX + 2, 17, 'unicode: ● ◆ ╬', fg: Colour.brightCyan);
  }
}
