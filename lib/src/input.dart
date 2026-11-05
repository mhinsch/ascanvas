import 'dart:convert';

/// Base class for input received from the terminal.
sealed class InputEvent {
  const InputEvent();
}

/// Non-printable keys recognised by `KeyParser`.
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
class KeyEvent extends InputEvent {
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

/// How much mouse activity the terminal reports.
enum MouseMode {
  /// Mouse reporting is disabled. This is the default.
  off,

  /// Report button presses and releases.
  click,

  /// Report presses, releases, and motion while a button is held.
  drag,

  /// Report all mouse motion.
  motion,
}

/// The button involved in a [MouseEvent].
enum MouseButton {
  left,
  middle,
  right,

  /// No button, used for pure motion and releases.
  none,
  wheelUp,
  wheelDown,
  wheelLeft,
  wheelRight,
  back,
  forward,
}

/// What happened in a [MouseEvent].
enum MouseAction {
  /// A button was pressed.
  press,

  /// A button was released.
  release,

  /// The mouse moved without a button held.
  move,

  /// The mouse moved while a button was held.
  drag,

  /// A wheel was scrolled.
  scroll,
}

/// A mouse event received from the terminal.
///
/// Coordinates are zero-based terminal cells, matching `Canvas` coordinates.
/// Applications that draw a smaller canvas inside the terminal must translate
/// them by the canvas origin.
class MouseEvent extends InputEvent {
  const MouseEvent({
    required this.column,
    required this.row,
    required this.button,
    required this.action,
    this.shift = false,
    this.alt = false,
    this.ctrl = false,
  });

  /// Column, counted from zero at the left edge of the terminal.
  final int column;

  /// Row, counted from zero at the top edge of the terminal.
  final int row;

  /// The button involved in the event.
  final MouseButton button;

  /// What happened.
  final MouseAction action;

  /// Whether Shift was held.
  final bool shift;

  /// Whether Alt (Meta) was held.
  final bool alt;

  /// Whether Ctrl was held.
  final bool ctrl;

  @override
  String toString() =>
      'MouseEvent(${action.name} ${button.name} at $column,$row'
      '${shift ? ' shift' : ''}${alt ? ' alt' : ''}${ctrl ? ' ctrl' : ''})';
}
