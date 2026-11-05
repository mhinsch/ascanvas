import 'dart:convert';

/// Non-printable keys recognised by [KeyParser].
enum SpecialKey {
  left,
  right,
  up,
  down,
  home,
  end,
  pageUp,
  pageDown,
  insert,
  delete,
  enter,
  backspace,
  tab,
  escape,
}

/// A key press received from the terminal.
class KeyEvent {
  const KeyEvent._({this.special, this.character});

  /// Creates an event for a named key.
  const KeyEvent.special(SpecialKey key) : this._(special: key);

  /// Creates an event for a printable character.
  const KeyEvent.char(String value) : this._(character: value);

  /// The named key, or `null` for a printable character.
  final SpecialKey? special;

  /// The printable character, or `null` for a named key.
  final String? character;

  /// Whether this event represents a printable character.
  bool get isCharacter => character != null;

  @override
  String toString() {
    if (special != null) return 'KeyEvent(${special!.name})';
    return 'KeyEvent(${jsonEncode(character)})';
  }
}

/// Incrementally converts terminal input bytes into [KeyEvent]s.
///
/// The parser accepts the normal ANSI CSI/SS3 cursor sequences as well as
/// UTF-8 text. Input may be split at arbitrary byte boundaries; incomplete
/// sequences are retained until more bytes arrive.
class KeyParser {
  final List<int> _buffer = [];

  /// Whether the buffer ends with a lone escape byte.
  ///
  /// Callers should wait a short moment before calling [flushPendingEscape] so
  /// that the rest of an escape sequence can arrive.
  bool get hasPendingEscape => _buffer.length == 1 && _buffer[0] == 0x1b;

  /// Adds [bytes] and returns any complete key events.
  List<KeyEvent> add(List<int> bytes) {
    if (bytes.isEmpty) return const [];
    _buffer.addAll(bytes);
    return _parse();
  }

  /// Handles an escape key that was not followed by anything.
  ///
  /// This is needed because a real escape key and the beginning of a cursor key
  /// sequence are indistinguishable without a timeout.
  KeyEvent? flushPendingEscape() {
    if (!hasPendingEscape) return null;
    _buffer.clear();
    return const KeyEvent.special(SpecialKey.escape);
  }

  List<KeyEvent> _parse() {
    final events = <KeyEvent>[];
    var position = 0;

    while (position < _buffer.length) {
      final byte = _buffer[position];

      if (byte == 0x1b) {
        if (position + 1 >= _buffer.length) break;

        final next = _buffer[position + 1];
        if (next == 0x5b) {
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
          final key = _csiKey(_buffer[finalPosition], parameters);
          if (key != null) events.add(KeyEvent.special(key));
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
