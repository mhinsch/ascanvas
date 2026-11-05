import 'dart:async';
import 'dart:io';

import 'canvas.dart';
import 'colour.dart';
import 'keys.dart';

/// A full-screen ANSI terminal with raw keyboard input.
///
/// [open] switches to the alternate screen, hides the cursor and turns off
/// line buffering/echo. [close] restores all of that. The raw-mode setup is
/// POSIX-specific; on other platforms input may remain line-buffered.
class Terminal {
  /// Creates a terminal.
  ///
  /// [output] and [input] default to [stdout] and [stdin]. [columns] and
  /// [rows] override the detected size, which is useful for tests. Set
  /// [installSignalHandlers] to `false` if the application wants to manage
  /// Ctrl-C and SIGTERM itself.
  Terminal({
    IOSink? output,
    Stream<List<int>>? input,
    ColourMode? colourMode,
    int? columns,
    int? rows,
    bool installSignalHandlers = true,
  })  : _output = output ?? stdout,
        _input = input ?? stdin,
        _columnsOverride = columns,
        _rowsOverride = rows,
        _installSignalHandlers = installSignalHandlers,
        colourMode = colourMode ?? ColourMode.detect();

  final IOSink _output;
  final Stream<List<int>> _input;
  final int? _columnsOverride;
  final int? _rowsOverride;
  final bool _installSignalHandlers;

  /// The colour mode used when presenting canvases.
  final ColourMode colourMode;

  final KeyParser _parser = KeyParser();
  final StreamController<KeyEvent> _keys =
      StreamController<KeyEvent>.broadcast();

  StreamSubscription<List<int>>? _inputSubscription;
  final List<StreamSubscription<ProcessSignal>> _signalSubscriptions = [];
  Timer? _escapeTimer;
  bool _isOpen = false;
  bool _wasOpened = false;
  bool _lineMode = true;
  bool _echoMode = true;
  int? _detectedRows;
  Future<void> _writeQueue = Future<void>.value();

  /// The width of the terminal in columns.
  int get columns {
    final override = _columnsOverride;
    if (override != null) return override;
    if (_output is Stdout) {
      try {
        final value = _output.terminalColumns;
        if (value > 0) return value;
      } on StdoutException {
        // Not attached to a terminal; fall through to the default.
      }
    }
    return 80;
  }

  /// The height of the terminal in rows.
  int get rows {
    final override = _rowsOverride;
    if (override != null) return override;
    final detected = _detectedRows;
    if (detected != null) return detected;

    final environment = Platform.environment;
    final fromEnvironment = int.tryParse(environment['LINES'] ?? '');
    _detectedRows = _queryTerminalSize()?.$2 ??
        ((fromEnvironment != null && fromEnvironment > 0)
            ? fromEnvironment
            : 24);
    return _detectedRows!;
  }

  (int, int)? _queryTerminalSize() {
    if (!identical(_output, stdout)) return null;
    if (!Platform.isLinux && !Platform.isMacOS) return null;
    try {
      if (!stdout.hasTerminal) return null;
      // dart:io exposes terminalColumns but not terminalRows. Ask stty, using
      // /dev/tty so that the query still works when stdin is redirected.
      final result = Process.runSync('sh', ['-c', 'stty size < /dev/tty']);
      if (result.exitCode != 0) return null;
      final parts = (result.stdout as String).trim().split(RegExp(r'\s+'));
      if (parts.length != 2) return null;
      final rowCount = int.tryParse(parts[0]);
      final columnCount = int.tryParse(parts[1]);
      if (rowCount == null || columnCount == null) return null;
      if (rowCount <= 0 || columnCount <= 0) return null;
      return (columnCount, rowCount);
    } catch (_) {
      return null;
    }
  }

  /// Key presses from the terminal.
  ///
  /// This is a broadcast stream, so it may have multiple listeners.
  Stream<KeyEvent> get keys => _keys.stream;

  /// Enters the alternate screen and starts reading raw key input.
  Future<void> open() async {
    if (_isOpen) return;
    if (_wasOpened) {
      throw StateError('A Terminal cannot be reopened after close().');
    }
    _wasOpened = true;
    _isOpen = true;

    if (identical(_input, stdin)) {
      try {
        _lineMode = stdin.lineMode;
        _echoMode = stdin.echoMode;
        stdin.echoMode = false;
        stdin.lineMode = false;
      } on StdinException {
        // Input is not a terminal (for example a pipe); bytes still arrive.
      }
    }

    _output.write('\x1b[?1049h\x1b[?25l\x1b[2J\x1b[H');
    _inputSubscription = _input.listen(
      _onInput,
      onError: (Object error, StackTrace stackTrace) {
        if (!_keys.isClosed) _keys.addError(error, stackTrace);
      },
    );

    if (_installSignalHandlers &&
        identical(_output, stdout) &&
        identical(_input, stdin)) {
      _installSignals(ProcessSignal.sigint, 130);
      try {
        _installSignals(ProcessSignal.sigterm, 143);
      } on SignalException {
        // SIGTERM is not available on every platform.
      }
    }

    await _output.flush();
  }

  /// Restores the terminal and stops reading input.
  Future<void> close() async {
    if (!_isOpen) return;
    _isOpen = false;

    _escapeTimer?.cancel();
    _escapeTimer = null;
    await _inputSubscription?.cancel();
    _inputSubscription = null;
    for (final subscription in _signalSubscriptions) {
      await subscription.cancel();
    }
    _signalSubscriptions.clear();

    if (identical(_input, stdin)) {
      try {
        stdin.echoMode = _echoMode;
        stdin.lineMode = _lineMode;
      } on StdinException {
        // Nothing to restore.
      }
    }

    // Wait for any queued frames so that restoring the screen cannot race
    // with an in-progress flush.
    await _writeQueue;
    _output.write('\x1b[0m\x1b[?25h\x1b[?1049l');
    await _output.flush();

    if (!_keys.isClosed) await _keys.close();
  }

  /// Writes the difference between [canvas] and the terminal, then flushes.
  ///
  /// Calls are serialised, so a slow flush never blocks or corrupts a later
  /// frame. The returned future completes once all queued frames are written.
  Future<void> present(Canvas canvas) {
    final output = canvas.renderDiff(colourMode);
    if (output.isEmpty) return _writeQueue;
    return _enqueue(() => _output.write(output));
  }

  /// Clears the terminal and moves the cursor to the top-left corner.
  Future<void> clear() => _enqueue(() => _output.write('\x1b[2J\x1b[H'));

  Future<void> _enqueue(void Function() write) {
    final next = _writeQueue.then((_) async {
      write();
      await _output.flush();
    });
    _writeQueue = next.catchError((Object _, StackTrace __) {
      // Keep the queue usable after a write error. The caller receives [next],
      // so it can still observe the failure if it wants to.
    });
    return next;
  }

  void _onInput(List<int> bytes) {
    final events = _parser.add(bytes);
    for (final event in events) {
      if (!_keys.isClosed) _keys.add(event);
    }

    _escapeTimer?.cancel();
    if (_parser.hasPendingEscape) {
      _escapeTimer = Timer(const Duration(milliseconds: 25), () {
        final event = _parser.flushPendingEscape();
        if (event != null && !_keys.isClosed) _keys.add(event);
      });
    }
  }

  void _installSignals(ProcessSignal signal, int exitCode) {
    try {
      _signalSubscriptions.add(
        signal.watch().listen((_) {
          unawaited(
            close().whenComplete(() => exit(exitCode)),
          );
        }),
      );
    } on SignalException {
      // Signal handling is unavailable; the app still works without it.
    }
  }
}
