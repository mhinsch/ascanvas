import 'dart:async';
import 'dart:io';

import 'package:asciiv/asciiv.dart';
import 'package:test/test.dart';

void main() {
  test('serialises presents and restores the screen', () async {
    final directory = await Directory.systemTemp.createTemp('asciiv_test_');
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
}
