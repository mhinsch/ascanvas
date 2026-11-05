import 'dart:convert';

import 'input.dart';

/// Incrementally converts terminal input bytes into [InputEvent]s.
///
/// The parser accepts keys (ANSI CSI/SS3 cursor sequences, control keys, and
/// UTF-8 text) as well as SGR and legacy X10 mouse reports. Input may be split
/// at arbitrary byte boundaries; incomplete sequences are retained until more
/// bytes arrive.
class KeyParser {
  final List<int> _buffer = [];

  /// Whether the buffer ends with a lone escape byte.
  ///
  /// Callers should wait a short moment before calling [flushPendingEscape] so
  /// that the rest of an escape sequence can arrive.
  bool get hasPendingEscape => _buffer.length == 1 && _buffer[0] == 0x1b;

  /// Adds [bytes] and returns any complete events.
  List<InputEvent> add(List<int> bytes) {
    if (bytes.isEmpty) return const [];
    _buffer.addAll(bytes);
    return _parse();
  }

  /// Handles an escape key that was not followed by anything.
  ///
  /// This is needed because a real escape key and the beginning of an escape
  /// sequence are indistinguishable without a timeout.
  KeyEvent? flushPendingEscape() {
    if (!hasPendingEscape) return null;
    _buffer.clear();
    return const KeyEvent.special(SpecialKey.escape);
  }

  List<InputEvent> _parse() {
    final events = <InputEvent>[];
    var position = 0;

    while (position < _buffer.length) {
      final byte = _buffer[position];

      if (byte == 0x1b) {
        if (position + 1 >= _buffer.length) break;

        final next = _buffer[position + 1];
        if (next == 0x5b) {
          // Legacy X10 mouse: ESC [ M followed by three encoded bytes.
          if (position + 2 < _buffer.length && _buffer[position + 2] == 0x4d) {
            if (position + 6 > _buffer.length) break;
            final mouse = _x10MouseEvent(
              _buffer[position + 3],
              _buffer[position + 4],
              _buffer[position + 5],
            );
            if (mouse != null) events.add(mouse);
            position += 6;
            continue;
          }

          // CSI: ESC [ parameters final-byte
          var finalPosition = position + 2;
          while (finalPosition < _buffer.length &&
              !(_buffer[finalPosition] >= 0x40 &&
                  _buffer[finalPosition] <= 0x7e)) {
            finalPosition++;
          }
          if (finalPosition >= _buffer.length) break;

          final parameters = latin1.decode(
            _buffer.sublist(position + 2, finalPosition),
            allowInvalid: true,
          );
          if (parameters.startsWith('<')) {
            final mouse = _sgrMouseEvent(parameters, _buffer[finalPosition]);
            if (mouse != null) events.add(mouse);
          } else {
            final key = _csiKey(_buffer[finalPosition], parameters);
            if (key != null) events.add(KeyEvent.special(key));
          }
          position = finalPosition + 1;
          continue;
        }

        if (next == 0x4f) {
          // SS3: ESC O final-byte
          if (position + 2 >= _buffer.length) break;
          final key = _letterKey(_buffer[position + 2]);
          if (key != null) events.add(KeyEvent.special(key));
          position += 3;
          continue;
        }

        // A lone escape followed by an ordinary byte. Treat the escape as a
        // key of its own and let the next byte be parsed normally.
        events.add(const KeyEvent.special(SpecialKey.escape));
        position++;
        continue;
      }

      if (byte < 0x20 || byte == 0x7f) {
        final key = _controlKey(byte);
        if (key != null) events.add(KeyEvent.special(key));
        position++;
        continue;
      }

      final length = _utf8Length(byte);
      if (position + length > _buffer.length) break;

      final sequence = _buffer.sublist(position, position + length);
      final character = length == 1 && byte < 0x80
          ? String.fromCharCode(byte)
          : utf8.decode(sequence, allowMalformed: true);
      events.add(KeyEvent.char(character));
      position += length;
    }

    if (position > 0) _buffer.removeRange(0, position);
    return events;
  }

  static MouseEvent? _sgrMouseEvent(String parameters, int finalByte) {
    if (finalByte != 0x4d && finalByte != 0x6d) return null;
    if (!parameters.startsWith('<')) return null;

    final fields = parameters.substring(1).split(';');
    if (fields.length != 3) return null;

    final code = int.tryParse(fields[0]);
    final x = int.tryParse(fields[1]);
    final y = int.tryParse(fields[2]);
    if (code == null || x == null || y == null || x <= 0 || y <= 0) {
      return null;
    }

    final release = finalByte == 0x6d;
    return MouseEvent(
      column: x - 1,
      row: y - 1,
      button: _buttonFromCode(code),
      action: _actionFromCode(code, release: release),
      shift: (code & 4) != 0,
      alt: (code & 8) != 0,
      ctrl: (code & 16) != 0,
    );
  }

  static MouseEvent? _x10MouseEvent(int buttonByte, int xByte, int yByte) {
    final code = buttonByte - 32;
    final column = xByte - 33;
    final row = yByte - 33;
    if (code < 0 || column < 0 || row < 0) return null;

    final noButton = (code & 3) == 3;
    final release = noButton && (code & 32) == 0 && (code & 64) == 0;
    return MouseEvent(
      column: column,
      row: row,
      button: _buttonFromCode(code),
      action: _actionFromCode(code, release: release),
      shift: (code & 4) != 0,
      alt: (code & 8) != 0,
      ctrl: (code & 16) != 0,
    );
  }

  static MouseButton _buttonFromCode(int code) {
    if ((code & 64) != 0) {
      return switch (code & 3) {
        0 => MouseButton.wheelUp,
        1 => MouseButton.wheelDown,
        2 => MouseButton.wheelLeft,
        _ => MouseButton.wheelRight,
      };
    }
    if ((code & 128) != 0) {
      return switch (code & 3) {
        0 => MouseButton.back,
        1 => MouseButton.forward,
        _ => MouseButton.none,
      };
    }
    return switch (code & 3) {
      0 => MouseButton.left,
      1 => MouseButton.middle,
      2 => MouseButton.right,
      _ => MouseButton.none,
    };
  }

  static MouseAction _actionFromCode(int code, {required bool release}) {
    if ((code & 64) != 0) return MouseAction.scroll;
    if (release) return MouseAction.release;
    if ((code & 32) != 0) {
      return (code & 3) == 3 ? MouseAction.move : MouseAction.drag;
    }
    return MouseAction.press;
  }

  static SpecialKey? _csiKey(int finalByte, String parameters) {
    final letter = _letterKey(finalByte);
    if (letter != null) return letter;
    if (finalByte != 0x7e) return null;

    final firstParameter = parameters.split(';').first;
    return switch (int.tryParse(firstParameter)) {
      1 || 7 => SpecialKey.home,
      2 => SpecialKey.insert,
      3 => SpecialKey.delete,
      4 || 8 => SpecialKey.end,
      5 => SpecialKey.pageUp,
      6 => SpecialKey.pageDown,
      _ => null,
    };
  }

  static SpecialKey? _letterKey(int byte) => switch (byte) {
        0x41 => SpecialKey.up,
        0x42 => SpecialKey.down,
        0x43 => SpecialKey.right,
        0x44 => SpecialKey.left,
        0x48 => SpecialKey.home,
        0x46 => SpecialKey.end,
        _ => null,
      };

  static SpecialKey? _controlKey(int byte) => switch (byte) {
        0x09 => SpecialKey.tab,
        0x0a || 0x0d => SpecialKey.enter,
        0x08 || 0x7f => SpecialKey.backspace,
        _ => null,
      };

  static int _utf8Length(int lead) {
    if (lead < 0x80) return 1;
    if (lead & 0xe0 == 0xc0) return 2;
    if (lead & 0xf0 == 0xe0) return 3;
    if (lead & 0xf8 == 0xf0) return 4;
    return 1;
  }
}
