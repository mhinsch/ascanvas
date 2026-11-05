import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:asciiv/asciiv.dart';

/// A deliberately small Tetris-like game used to exercise asciiv.
Future<void> main() async {
  if (!stdout.hasTerminal || !stdin.hasTerminal) {
    stderr.writeln('tetris must be run in an interactive terminal.');
    exitCode = 1;
    return;
  }

  final terminal = Terminal();
  await terminal.open();
  try {
    await _Tetris(terminal).run();
  } finally {
    await terminal.close();
  }
}

class _Piece {
  _Piece(this.name, this.colour, List<String> rows)
      : rotations = _buildRotations(rows);

  final String name;
  final Colour colour;

  /// Four 4x4 bitmaps, one per rotation.
  final List<List<bool>> rotations;

  static List<List<bool>> _buildRotations(List<String> rows) {
    var matrix = [
      for (final row in rows) [for (final rune in row.runes) rune == 0x23],
    ];
    final result = <List<bool>>[];
    for (var i = 0; i < 4; i++) {
      result.add([for (final row in matrix) ...row]);
      matrix = [
        for (var y = 0; y < 4; y++)
          [for (var x = 0; x < 4; x++) matrix[3 - x][y]],
      ];
    }
    return result;
  }
}

final List<_Piece> _pieces = [
  _Piece('I', const Colour.rgb(40, 220, 220), [
    '....',
    '####',
    '....',
    '....',
  ]),
  _Piece('O', const Colour.rgb(235, 215, 40), [
    '....',
    '.##.',
    '.##.',
    '....',
  ]),
  _Piece('T', const Colour.rgb(185, 85, 225), [
    '....',
    '###.',
    '.#..',
    '....',
  ]),
  _Piece('S', const Colour.rgb(80, 220, 90), [
    '....',
    '.##.',
    '##..',
    '....',
  ]),
  _Piece('Z', const Colour.rgb(235, 70, 80), [
    '....',
    '##..',
    '.##.',
    '....',
  ]),
  _Piece('J', const Colour.rgb(70, 115, 240), [
    '....',
    '###.',
    '#...',
    '....',
  ]),
  _Piece('L', const Colour.rgb(240, 150, 45), [
    '....',
    '###.',
    '..#.',
    '....',
  ]),
];

class _Tetris {
  _Tetris(this.terminal);

  static const int boardWidth = 10;
  static const int boardHeight = 20;
  static const int cellWidth = 2;
  static const int borderWidth = boardWidth * cellWidth + 2;
  static const int borderHeight = boardHeight + 2;
  static const int sidebarWidth = 16;
  static const int totalWidth = borderWidth + 2 + sidebarWidth;
  static const int totalHeight = borderHeight;

  static const _emptyBackground = Colour.rgb(16, 18, 24);
  static const _overlayBackground = Colour.rgb(8, 8, 12);

  final Terminal terminal;
  final Random _random = Random();

  late final Canvas _canvas;
  late List<List<Colour?>> _board;
  late _Piece _current;
  late _Piece _next;

  int _x = 3;
  int _y = 0;
  int _rotation = 0;
  int _score = 0;
  int _lines = 0;
  int _level = 1;
  bool _paused = false;
  bool _gameOver = false;
  bool _quit = false;
  Timer? _gravity;

  int _originX = 0;
  int _originY = 0;
  int _sidebarX = 0;

  Future<void> run() async {
    final canvas = Canvas(terminal.columns, terminal.rows);
    _canvas = canvas;

    if (terminal.columns < totalWidth || terminal.rows < totalHeight) {
      canvas.text(
        1,
        0,
        'Terminal too small: asciiv tetris needs at least '
        '${totalWidth}x$totalHeight cells.',
        fg: Colour.brightRed,
      );
      canvas.text(1, 2, 'Press Q to quit.', fg: Colour.brightWhite);
      await terminal.present(canvas);
      await for (final event in terminal.keys) {
        if (_isQuitKey(event)) break;
      }
      return;
    }

    _layout();
    _reset();

    final finished = Completer<void>();
    final subscription = terminal.keys.listen((event) {
      _handleKey(event);
      if (_quit && !finished.isCompleted) finished.complete();
    });

    _startGravity();
    _draw();
    await finished.future;

    await subscription.cancel();
    _gravity?.cancel();
  }

  bool _isQuitKey(KeyEvent event) =>
      event.special == SpecialKey.escape ||
      event.character?.toLowerCase() == 'q';

  void _layout() {
    _originX = max(1, (terminal.columns - totalWidth) ~/ 2);
    _originY = max(0, (terminal.rows - totalHeight) ~/ 2);
    _sidebarX = _originX + borderWidth + 2;
  }

  void _reset() {
    _board = List.generate(
      boardHeight,
      (_) => List<Colour?>.filled(boardWidth, null),
    );
    _score = 0;
    _lines = 0;
    _level = 1;
    _paused = false;
    _gameOver = false;
    _next = _randomPiece();
    _spawn();
  }

  _Piece _randomPiece() => _pieces[_random.nextInt(_pieces.length)];

  void _spawn() {
    _current = _next;
    _next = _randomPiece();
    _x = 3;
    _y = 0;
    _rotation = 0;
    if (_collides(_x, _y, _rotation)) {
      _gameOver = true;
      _gravity?.cancel();
    }
  }

  bool _collides(int pieceX, int pieceY, int rotation) {
    final mask = _current.rotations[rotation];
    for (var row = 0; row < 4; row++) {
      for (var column = 0; column < 4; column++) {
        if (!mask[row * 4 + column]) continue;
        final x = pieceX + column;
        final y = pieceY + row;
        if (x < 0 || x >= boardWidth || y >= boardHeight) return true;
        if (y >= 0 && _board[y][x] != null) return true;
      }
    }
    return false;
  }

  void _startGravity() {
    _gravity?.cancel();
    if (_paused || _gameOver || _quit) return;

    final interval = max(100, 700 - (_level - 1) * 60);
    _gravity = Timer.periodic(Duration(milliseconds: interval), (_) {
      if (_paused || _gameOver || _quit) return;
      _stepDown();
      _draw();
    });
  }

  void _stepDown() {
    if (!_collides(_x, _y + 1, _rotation)) {
      _y++;
    } else {
      _lockPiece();
    }
  }

  void _lockPiece() {
    final mask = _current.rotations[_rotation];
    for (var row = 0; row < 4; row++) {
      for (var column = 0; column < 4; column++) {
        if (!mask[row * 4 + column]) continue;
        final x = _x + column;
        final y = _y + row;
        if (y >= 0 && y < boardHeight) _board[y][x] = _current.colour;
      }
    }

    _clearLines();
    _spawn();
    _startGravity();
  }

  void _clearLines() {
    var cleared = 0;
    for (var y = boardHeight - 1; y >= 0;) {
      if (_board[y].every((colour) => colour != null)) {
        _board.removeAt(y);
        _board.insert(0, List<Colour?>.filled(boardWidth, null));
        cleared++;
      } else {
        y--;
      }
    }
    if (cleared == 0) return;

    const scores = [0, 100, 300, 500, 800];
    _score += scores[cleared] * _level;
    _lines += cleared;
    _level = 1 + _lines ~/ 10;
  }

  void _moveHorizontally(int delta) {
    if (_paused || _gameOver) return;
    if (!_collides(_x + delta, _y, _rotation)) _x += delta;
  }

  void _rotate(int direction) {
    if (_paused || _gameOver) return;
    final rotation = (_rotation + direction + 4) % 4;
    for (final offset in [0, -1, 1, -2, 2]) {
      if (!_collides(_x + offset, _y, rotation)) {
        _x += offset;
        _rotation = rotation;
        return;
      }
    }
  }

  void _softDrop() {
    if (_paused || _gameOver) return;
    if (!_collides(_x, _y + 1, _rotation)) {
      _y++;
      _score++;
    } else {
      _lockPiece();
    }
  }

  void _hardDrop() {
    if (_paused || _gameOver) return;
    var distance = 0;
    while (!_collides(_x, _y + 1, _rotation)) {
      _y++;
      distance++;
    }
    _score += distance * 2;
    _lockPiece();
  }

  void _togglePause() {
    if (_gameOver) return;
    _paused = !_paused;
    _startGravity();
  }

  void _restart() {
    _reset();
    _startGravity();
  }

  void _handleKey(KeyEvent event) {
    if (_quit) return;

    if (_isQuitKey(event)) {
      _quit = true;
      _gravity?.cancel();
      return;
    }

    final character = event.character?.toLowerCase();
    switch (event.special) {
      case SpecialKey.left:
        _moveHorizontally(-1);
      case SpecialKey.right:
        _moveHorizontally(1);
      case SpecialKey.up:
        _rotate(1);
      case SpecialKey.down:
        _softDrop();
      case SpecialKey.enter:
        _hardDrop();
      default:
        break;
    }

    switch (character) {
      case 'a':
        _moveHorizontally(-1);
      case 'd':
        _moveHorizontally(1);
      case 'w':
        _rotate(1);
      case 's':
        _softDrop();
      case 'x':
        _rotate(1);
      case 'z':
        _rotate(-1);
      case ' ':
        _hardDrop();
      case 'p':
        _togglePause();
      case 'r':
        _restart();
      default:
        break;
    }

    _draw();
  }

  void _draw() {
    final canvas = _canvas;
    canvas.clear();

    if (_originY > 0) {
      canvas.text(
        _originX + 3,
        0,
        'ASCIIV TETRIS',
        fg: Colour.brightCyan,
      );
    }

    for (var y = 0; y < boardHeight; y++) {
      for (var x = 0; x < boardWidth; x++) {
        final colour = _board[y][x];
        _paintBlock(
          canvas,
          _originX + 1 + x * cellWidth,
          _originY + 1 + y,
          colour,
        );
      }
    }

    if (!_gameOver) _drawPiece(_current, _x, _y, _rotation);

    canvas.box(
      _originX,
      _originY,
      borderWidth,
      borderHeight,
      fg: _paused ? Colour.brightYellow : Colour.brightBlack,
    );

    _drawSidebar(canvas);

    if (_gameOver || _paused) _drawOverlay(canvas);

    unawaited(terminal.present(canvas));
  }

  void _paintBlock(Canvas canvas, int x, int y, Colour? colour) {
    if (colour == null) {
      canvas.put(x, y, ' ', bg: _emptyBackground);
      canvas.put(x + 1, y, ' ', bg: _emptyBackground);
    } else {
      canvas.put(x, y, '█', fg: colour);
      canvas.put(x + 1, y, '█', fg: colour);
    }
  }

  void _drawPiece(_Piece piece, int pieceX, int pieceY, int rotation) {
    final mask = piece.rotations[rotation];
    for (var row = 0; row < 4; row++) {
      for (var column = 0; column < 4; column++) {
        if (!mask[row * 4 + column]) continue;
        final y = pieceY + row;
        if (y < 0) continue;
        _paintBlock(
          _canvas,
          _originX + 1 + (pieceX + column) * cellWidth,
          _originY + 1 + y,
          piece.colour,
        );
      }
    }
  }

  void _drawSidebar(Canvas canvas) {
    final x = _sidebarX;
    final y = _originY;

    canvas.text(x, y, 'NEXT', fg: Colour.brightBlack);
    canvas.fill(x, y + 2, 8, 4, bg: _emptyBackground);
    final nextMask = _next.rotations[0];
    for (var row = 0; row < 4; row++) {
      for (var column = 0; column < 4; column++) {
        if (!nextMask[row * 4 + column]) continue;
        _paintBlock(
          canvas,
          x + column * cellWidth,
          y + 2 + row,
          _next.colour,
        );
      }
    }

    canvas.text(x, y + 7, 'SCORE', fg: Colour.brightBlack);
    canvas.text(x, y + 8, '$_score', fg: Colour.brightWhite);

    canvas.text(x, y + 10, 'LINES', fg: Colour.brightBlack);
    canvas.text(x, y + 11, '$_lines', fg: Colour.brightWhite);

    canvas.text(x, y + 13, 'LEVEL', fg: Colour.brightBlack);
    canvas.text(x, y + 14, '$_level', fg: Colour.brightWhite);

    const controls = [
      '<- ->  move',
      'Up/X   rotate',
      'Down   soft',
      'Space  drop',
      'P pause',
      'R reset  Q quit',
    ];
    for (var i = 0; i < controls.length; i++) {
      canvas.text(x, y + 16 + i, controls[i], fg: Colour.brightBlack);
    }
  }

  void _drawOverlay(Canvas canvas) {
    const width = 20;
    const height = 5;
    final x = _originX + 1;
    final y = _originY + 9;
    final colour = _gameOver ? Colour.brightRed : Colour.brightYellow;
    final title = _gameOver ? 'GAME OVER' : 'PAUSED';
    final hint = _gameOver ? 'R restart  Q quit' : 'P resume';

    canvas.fill(x, y, width, height, bg: _overlayBackground);
    canvas.box(x, y, width, height, fg: colour, bg: _overlayBackground);
    canvas.text(
      x + (width - title.length) ~/ 2,
      y + 1,
      title,
      fg: colour,
      bg: _overlayBackground,
    );
    canvas.text(
      x + (width - hint.length) ~/ 2,
      y + 3,
      hint,
      fg: Colour.brightWhite,
      bg: _overlayBackground,
    );
  }
}
