import 'dart:convert';

import 'package:asciiv/asciiv.dart';
import 'package:test/test.dart';

KeyEvent asKey(InputEvent event) => event as KeyEvent;
MouseEvent asMouse(InputEvent event) => event as MouseEvent;

void main() {
  group('KeyParser keys', () {
    test('parses CSI arrow keys', () {
      final parser = KeyParser();
      expect(
          asKey(parser.add([0x1b, 0x5b, 0x41]).single).special, SpecialKey.up);
      expect(
        asKey(parser.add([0x1b, 0x5b, 0x42]).single).special,
        SpecialKey.down,
      );
      expect(
        asKey(parser.add([0x1b, 0x5b, 0x43]).single).special,
        SpecialKey.right,
      );
      expect(
        asKey(parser.add([0x1b, 0x5b, 0x44]).single).special,
        SpecialKey.left,
      );
    });

    test('parses SS3 arrow keys', () {
      final parser = KeyParser();
      expect(
          asKey(parser.add([0x1b, 0x4f, 0x41]).single).special, SpecialKey.up);
      expect(
        asKey(parser.add([0x1b, 0x4f, 0x44]).single).special,
        SpecialKey.left,
      );
    });

    test('parses modified CSI sequences', () {
      final parser = KeyParser();
      final events = parser.add([
        0x1b, 0x5b, 0x31, 0x3b, 0x35, 0x43, // ESC [ 1 ; 5 C
      ]);
      expect(asKey(events.single).special, SpecialKey.right);
    });

    test('parses tilde sequences', () {
      final parser = KeyParser();
      expect(
        asKey(parser.add([0x1b, 0x5b, 0x33, 0x7e]).single).special,
        SpecialKey.delete,
      );
      expect(
        asKey(parser.add([0x1b, 0x5b, 0x35, 0x7e]).single).special,
        SpecialKey.pageUp,
      );
    });

    test('retains fragmented escape sequences', () {
      final parser = KeyParser();
      expect(parser.add([0x1b]), isEmpty);
      expect(parser.add([0x5b]), isEmpty);
      expect(asKey(parser.add([0x41]).single).special, SpecialKey.up);
    });

    test('flushes a lone escape', () {
      final parser = KeyParser();
      expect(parser.add([0x1b]), isEmpty);
      expect(parser.hasPendingEscape, isTrue);
      expect(parser.flushPendingEscape()!.special, SpecialKey.escape);
      expect(parser.hasPendingEscape, isFalse);
    });

    test('parses control and printable keys', () {
      final parser = KeyParser();
      expect(asKey(parser.add([0x0d]).single).special, SpecialKey.enter);
      expect(asKey(parser.add([0x7f]).single).special, SpecialKey.backspace);
      expect(asKey(parser.add([0x20]).single).character, ' ');
      expect(asKey(parser.add(utf8.encode('q')).single).character, 'q');
    });

    test('decodes fragmented UTF-8', () {
      final parser = KeyParser();
      final bytes = utf8.encode('é');
      expect(parser.add([bytes.first]), isEmpty);
      expect(asKey(parser.add(bytes.sublist(1)).single).character, 'é');
    });

    test('decodes several characters at once', () {
      final parser = KeyParser();
      final events = parser.add(utf8.encode('abc'));
      expect(events.map((event) => asKey(event).character), ['a', 'b', 'c']);
    });
  });

  group('KeyParser mouse', () {
    test('parses SGR button press and release', () {
      final parser = KeyParser();

      final press = asMouse(parser.add(utf8.encode('\x1b[<0;5;7M')).single);
      expect(press.button, MouseButton.left);
      expect(press.action, MouseAction.press);
      expect(press.column, 4);
      expect(press.row, 6);

      final release = asMouse(parser.add(utf8.encode('\x1b[<2;5;7m')).single);
      expect(release.button, MouseButton.right);
      expect(release.action, MouseAction.release);
    });

    test('parses SGR modifiers', () {
      final parser = KeyParser();
      // Middle button (1) plus shift (4), alt (8), and ctrl (16).
      final event = asMouse(parser.add(utf8.encode('\x1b[<29;1;2M')).single);
      expect(event.button, MouseButton.middle);
      expect(event.shift, isTrue);
      expect(event.alt, isTrue);
      expect(event.ctrl, isTrue);
    });

    test('parses SGR drag, move, and wheel events', () {
      final parser = KeyParser();

      final drag = asMouse(parser.add(utf8.encode('\x1b[<32;3;4M')).single);
      expect(drag.action, MouseAction.drag);
      expect(drag.button, MouseButton.left);

      final move = asMouse(parser.add(utf8.encode('\x1b[<35;3;4M')).single);
      expect(move.action, MouseAction.move);
      expect(move.button, MouseButton.none);

      final wheelUp = asMouse(parser.add(utf8.encode('\x1b[<64;3;4M')).single);
      expect(wheelUp.action, MouseAction.scroll);
      expect(wheelUp.button, MouseButton.wheelUp);

      final wheelDown = asMouse(
        parser.add(utf8.encode('\x1b[<65;3;4M')).single,
      );
      expect(wheelDown.button, MouseButton.wheelDown);

      final wheelLeft = asMouse(
        parser.add(utf8.encode('\x1b[<66;3;4M')).single,
      );
      expect(wheelLeft.button, MouseButton.wheelLeft);

      final wheelRight = asMouse(
        parser.add(utf8.encode('\x1b[<67;3;4M')).single,
      );
      expect(wheelRight.button, MouseButton.wheelRight);
    });

    test('parses extended SGR buttons', () {
      final parser = KeyParser();
      expect(
        asMouse(parser.add(utf8.encode('\x1b[<128;1;1M')).single).button,
        MouseButton.back,
      );
      expect(
        asMouse(parser.add(utf8.encode('\x1b[<129;1;1M')).single).button,
        MouseButton.forward,
      );
      expect(
        asMouse(parser.add(utf8.encode('\x1b[<132;1;1M')).single).button,
        MouseButton.back,
      );
    });

    test('retains fragmented SGR mouse sequences', () {
      final parser = KeyParser();
      expect(parser.add(utf8.encode('\x1b[<0;5')), isEmpty);
      final event = asMouse(parser.add(utf8.encode(';7M')).single);
      expect(event.column, 4);
      expect(event.row, 6);
    });

    test('parses legacy X10 mouse events', () {
      final parser = KeyParser();

      final press = asMouse(
        parser.add([0x1b, 0x5b, 0x4d, 32, 33 + 4, 33 + 6]).single,
      );
      expect(press.button, MouseButton.left);
      expect(press.action, MouseAction.press);
      expect(press.column, 4);
      expect(press.row, 6);

      final release = asMouse(
        parser.add([0x1b, 0x5b, 0x4d, 35, 33, 33]).single,
      );
      expect(release.button, MouseButton.none);
      expect(release.action, MouseAction.release);

      final wheel = asMouse(
        parser.add([0x1b, 0x5b, 0x4d, 96, 33, 33]).single,
      );
      expect(wheel.button, MouseButton.wheelUp);
      expect(wheel.action, MouseAction.scroll);

      final drag = asMouse(
        parser.add([0x1b, 0x5b, 0x4d, 64, 33, 33]).single,
      );
      expect(drag.button, MouseButton.left);
      expect(drag.action, MouseAction.drag);
    });

    test('retains fragmented X10 mouse sequences', () {
      final parser = KeyParser();
      expect(parser.add([0x1b, 0x5b, 0x4d, 32]), isEmpty);
      final event = asMouse(parser.add([33 + 2, 33 + 3]).single);
      expect(event.column, 2);
      expect(event.row, 3);
    });

    test('keeps key and mouse events in input order', () {
      final parser = KeyParser();
      final events = parser.add([
        ...utf8.encode('a'),
        ...utf8.encode('\x1b[<0;2;3M'),
        ...utf8.encode('b'),
      ]);
      expect(events.map((event) => event.runtimeType), [
        KeyEvent,
        MouseEvent,
        KeyEvent,
      ]);
    });
  });
}
