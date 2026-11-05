import 'dart:convert';

import 'package:asciiv/asciiv.dart';
import 'package:test/test.dart';

void main() {
  group('KeyParser', () {
    test('parses CSI arrow keys', () {
      final parser = KeyParser();
      expect(parser.add([0x1b, 0x5b, 0x41]).single.special, SpecialKey.up);
      expect(parser.add([0x1b, 0x5b, 0x42]).single.special, SpecialKey.down);
      expect(parser.add([0x1b, 0x5b, 0x43]).single.special, SpecialKey.right);
      expect(parser.add([0x1b, 0x5b, 0x44]).single.special, SpecialKey.left);
    });

    test('parses SS3 arrow keys', () {
      final parser = KeyParser();
      expect(parser.add([0x1b, 0x4f, 0x41]).single.special, SpecialKey.up);
      expect(parser.add([0x1b, 0x4f, 0x44]).single.special, SpecialKey.left);
    });

    test('parses modified CSI sequences', () {
      final parser = KeyParser();
      final events = parser.add([
        0x1b, 0x5b, 0x31, 0x3b, 0x35, 0x43, // ESC [ 1 ; 5 C
      ]);
      expect(events.single.special, SpecialKey.right);
    });

    test('parses tilde sequences', () {
      final parser = KeyParser();
      expect(
        parser.add([0x1b, 0x5b, 0x33, 0x7e]).single.special,
        SpecialKey.delete,
      );
      expect(
        parser.add([0x1b, 0x5b, 0x35, 0x7e]).single.special,
        SpecialKey.pageUp,
      );
    });

    test('retains fragmented escape sequences', () {
      final parser = KeyParser();
      expect(parser.add([0x1b]), isEmpty);
      expect(parser.add([0x5b]), isEmpty);
      expect(parser.add([0x41]).single.special, SpecialKey.up);
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
      expect(parser.add([0x0d]).single.special, SpecialKey.enter);
      expect(parser.add([0x7f]).single.special, SpecialKey.backspace);
      expect(parser.add([0x20]).single.character, ' ');
      expect(parser.add(utf8.encode('q')).single.character, 'q');
    });

    test('decodes fragmented UTF-8', () {
      final parser = KeyParser();
      final bytes = utf8.encode('é');
      expect(parser.add([bytes.first]), isEmpty);
      expect(parser.add(bytes.sublist(1)).single.character, 'é');
    });

    test('decodes several characters at once', () {
      final parser = KeyParser();
      final events = parser.add(utf8.encode('abc'));
      expect(events.map((event) => event.character), ['a', 'b', 'c']);
    });
  });
}
