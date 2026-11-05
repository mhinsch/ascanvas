import 'package:ascanvas/ascanvas.dart';
import 'package:test/test.dart';

void main() {
  group('ColourMode.detect', () {
    test('detects true colour from COLORTERM', () {
      expect(
        ColourMode.detect(
          environment: {'TERM': 'xterm-256color', 'COLORTERM': 'truecolor'},
        ),
        ColourMode.trueColour,
      );
    });

    test('detects 256 colours from TERM', () {
      expect(
        ColourMode.detect(environment: {'TERM': 'screen-256color'}),
        ColourMode.indexed,
      );
    });

    test('falls back to basic colours', () {
      expect(
        ColourMode.detect(environment: {'TERM': 'xterm'}),
        ColourMode.basic,
      );
      expect(
        ColourMode.detect(
            environment: {'TERM': 'dumb', 'COLORTERM': 'truecolor'}),
        ColourMode.basic,
      );
    });
  });

  group('Colour', () {
    test('emits basic foreground and background SGR codes', () {
      expect(Colour.red.foregroundCode(ColourMode.basic), '31');
      expect(Colour.brightRed.foregroundCode(ColourMode.basic), '91');
      expect(Colour.red.backgroundCode(ColourMode.basic), '41');
      expect(Colour.brightRed.backgroundCode(ColourMode.basic), '101');
    });

    test('emits 256-colour SGR codes', () {
      expect(
        Colour.indexed(200).foregroundCode(ColourMode.indexed),
        '38;5;200',
      );
      expect(
        Colour.indexed(200).backgroundCode(ColourMode.indexed),
        '48;5;200',
      );
    });

    test('emits true-colour SGR codes', () {
      expect(
        Colour.rgb(1, 2, 3).foregroundCode(ColourMode.trueColour),
        '38;2;1;2;3',
      );
      expect(
        Colour.rgb(1, 2, 3).backgroundCode(ColourMode.trueColour),
        '48;2;1;2;3',
      );
    });

    test('passes palette colours through in true-colour mode', () {
      expect(
        Colour.indexed(200).foregroundCode(ColourMode.trueColour),
        '38;5;200',
      );
    });

    test('downsamples RGB to the 256-colour palette', () {
      expect(
          Colour.rgb(255, 0, 0).foregroundCode(ColourMode.indexed), '38;5;196');
      expect(Colour.rgb(0, 0, 0).foregroundCode(ColourMode.indexed), '38;5;16');
      expect(
        Colour.rgb(255, 255, 255).foregroundCode(ColourMode.indexed),
        '38;5;231',
      );
    });

    test('downsamples RGB to the sixteen ANSI colours', () {
      expect(Colour.rgb(255, 0, 0).foregroundCode(ColourMode.basic), '91');
      expect(Colour.rgb(0, 0, 0).foregroundCode(ColourMode.basic), '30');
    });

    test('palette colours below sixteen are exact, others are mapped', () {
      expect(Colour.indexed(3).foregroundCode(ColourMode.basic), '33');
      expect(Colour.indexed(196).foregroundCode(ColourMode.basic), '91');
    });

    test('value equality covers palette and RGB colours', () {
      expect(const Colour.rgb(1, 2, 3), const Colour.rgb(1, 2, 3));
      expect(const Colour.rgb(1, 2, 3), isNot(const Colour.rgb(1, 2, 4)));
      expect(const Colour.indexed(9), Colour.brightRed);
    });
  });
}
