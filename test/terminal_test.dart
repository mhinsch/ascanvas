import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ascanvas/ascanvas.dart';
import 'package:test/test.dart';

void main() {
  test('serialises presents and restores the screen', () async {
    final directory = await Directory.systemTemp.createTemp('ascanvas_test_');
    final file = File('${directory.path}/output.ansi');
    final sink = file.openWrite();
    final input = StreamController<List<int>>();
    final terminal = Terminal(
      output: sink,
      input: input.stream,
      colourMode: ColourMode.basic,
      columns: 10,
      rows: 3,
      installSignalHandlers: false,
    );

    try {
      await terminal.open();

      final canvas = Canvas(10, 3);
      canvas.text(0, 0, 'first', fg: Colour.brightRed);
      final first = terminal.present(canvas);

      canvas.text(0, 1, 'second');
      final second = terminal.present(canvas);

      // Ignoring these futures used to make a second write race an earlier
      // flush. Both frames must be serialised without an exception.
      await Future.wait([first, second]);
      await terminal.close();
    } finally {
      await sink.close();
      await input.close();
    }

    final output = await file.readAsString();
    expect(output, contains('\x1b[?1049h'));
    expect(output, contains('\x1b[?1049l'));
    expect(output.indexOf('first'), lessThan(output.indexOf('second')));
    expect(output, contains('\x1b[0;91mfirst'));

    await directory.delete(recursive: true);
  });

  test('enables mouse reporting and routes mouse events', () async {
    final directory = await Directory.systemTemp.createTemp('ascanvas_test_');
    final file = File('${directory.path}/output.ansi');
    final sink = file.openWrite();
    final input = StreamController<List<int>>();
    final terminal = Terminal(
      output: sink,
      input: input.stream,
      columns: 20,
      rows: 5,
      mouseMode: MouseMode.drag,
      installSignalHandlers: false,
    );
    final events = <InputEvent>[];
    final keys = <KeyEvent>[];
    StreamSubscription<InputEvent>? eventSubscription;
    StreamSubscription<KeyEvent>? keySubscription;

    try {
      await terminal.open();
      eventSubscription = terminal.events.listen(events.add);
      keySubscription = terminal.keys.listen(keys.add);

      input.add(utf8.encode('\x1b[<0;4;3M'));
      input.add(utf8.encode('a'));
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(2));
      final mouse = events.first as MouseEvent;
      expect(mouse.button, MouseButton.left);
      expect(mouse.action, MouseAction.press);
      expect(mouse.column, 3);
      expect(mouse.row, 2);

      // The keys stream filters out mouse events.
      expect(keys, hasLength(1));
      expect(keys.single.character, 'a');

      await terminal.close();
    } finally {
      await eventSubscription?.cancel();
      await keySubscription?.cancel();
      await sink.close();
      await input.close();
    }

    final output = await file.readAsString();
    expect(output, contains('\x1b[?1006h\x1b[?1002h'));
    expect(
      output,
      contains('\x1b[?1006l\x1b[?1003l\x1b[?1002l\x1b[?1000l'),
    );

    await directory.delete(recursive: true);
  });
}
