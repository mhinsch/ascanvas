import 'dart:async';
import 'dart:io';

import 'package:ascanvas/ascanvas.dart';

/// Paints a trail of mouse events until Q or Escape is pressed.
Future<void> main() async {
  if (!stdout.hasTerminal || !stdin.hasTerminal) {
    stderr.writeln('mouse demo must be run in an interactive terminal.');
    exitCode = 1;
    return;
  }

  final terminal = Terminal(mouseMode: MouseMode.drag);
  await terminal.open();
  try {
    final canvas = Canvas(terminal.columns, terminal.rows);
    final trail = <_TrailPoint>[];
    var status = 'Click, drag, or scroll. Hold Shift to select text.';
    final done = Completer<void>();

    final subscription = terminal.events.listen((event) {
      if (event is KeyEvent) {
        if (event.special == SpecialKey.escape ||
            event.character?.toLowerCase() == 'q') {
          if (!done.isCompleted) done.complete();
        }
        return;
      }

      if (event is! MouseEvent) return;
      if (event.column < canvas.width && event.row < canvas.height) {
        trail.add(_TrailPoint(event));
        if (trail.length > 2000) trail.removeAt(0);
      }
      status = _describe(event);
      _draw(terminal, canvas, trail, status);
    });

    _draw(terminal, canvas, trail, status);
    await done.future;
    await subscription.cancel();
  } finally {
    await terminal.close();
  }
}

void _draw(
  Terminal terminal,
  Canvas canvas,
  List<_TrailPoint> trail,
  String status,
) {
  canvas.clear();

  for (final point in trail) {
    canvas.put(point.column, point.row, point.glyph, fg: point.colour);
  }

  canvas.fill(0, 0, canvas.width, 4);
  canvas.text(1, 0, 'ascanvas mouse demo', fg: Colour.brightCyan);
  canvas.text(
    1,
    1,
    'Click, drag, scroll. Shift+click/drag selects text. Q quits.',
    fg: Colour.brightBlack,
  );
  canvas.text(1, 2, _truncate(status, canvas.width - 2),
      fg: Colour.brightWhite);
  canvas.text(
    1,
    canvas.height - 1,
    'SGR mouse reporting is enabled until exit.',
    fg: Colour.brightBlack,
  );

  unawaited(terminal.present(canvas));
}

String _truncate(String value, int maximum) {
  if (maximum <= 0) return '';
  if (value.length <= maximum) return value;
  return value.substring(0, maximum);
}

String _describe(MouseEvent event) {
  final modifiers = [
    if (event.shift) 'shift',
    if (event.alt) 'alt',
    if (event.ctrl) 'ctrl',
  ].join('+');
  final suffix = modifiers.isEmpty ? '' : ' [$modifiers]';
  return '${event.action.name} ${event.button.name} '
      'at ${event.column},${event.row}$suffix';
}

class _TrailPoint {
  _TrailPoint(MouseEvent event)
      : column = event.column,
        row = event.row,
        glyph = _glyphFor(event),
        colour = _colourFor(event);

  final int column;
  final int row;
  final String glyph;
  final Colour colour;

  static String _glyphFor(MouseEvent event) => switch (event.action) {
        MouseAction.press => '+',
        MouseAction.release => 'o',
        MouseAction.drag => '*',
        MouseAction.move => '.',
        MouseAction.scroll => switch (event.button) {
            MouseButton.wheelUp => '^',
            MouseButton.wheelDown => 'v',
            MouseButton.wheelLeft => '<',
            _ => '>',
          },
      };

  static Colour _colourFor(MouseEvent event) => switch (event.button) {
        MouseButton.left => Colour.brightGreen,
        MouseButton.middle => Colour.brightYellow,
        MouseButton.right => Colour.brightRed,
        MouseButton.wheelUp ||
        MouseButton.wheelDown ||
        MouseButton.wheelLeft ||
        MouseButton.wheelRight =>
          Colour.brightCyan,
        MouseButton.back || MouseButton.forward => Colour.brightMagenta,
        MouseButton.none => Colour.brightBlack,
      };
}
