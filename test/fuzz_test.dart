import 'dart:math';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// Ported from markwrite's `codec_fuzz_test` and `parse_atomicity_test`:
/// every syntax reads arbitrary text the same way twice, keeps it, tiles
/// it, and derives again after a keystroke what a fresh read gives; and
/// reading leaves what it read as it was, refused or not.
void main() {
  /// The ten syntaxes, each read within the limits given it.
  final syntaxes = <String, Syntax Function(Limits)>{
    'xml': (limits) => XML(limits: limits),
    'html': (limits) => HTML(limits: limits),
    'lmnl': (limits) => LMNL(limits: limits),
    'markdown': (limits) => Markdown(limits: limits),
    'man': (limits) => Man(limits: limits),
    'ms': (limits) => Ms(limits: limits),
    'me': (limits) => Me(limits: limits),
    'latex': (limits) => LaTeX(limits: limits),
    'json': (limits) => JSON(limits: limits),
    'dart': (limits) => Dart(limits: limits),
  };

  const seeds = [
    'plain text',
    '<p a=">">x</p>',
    '<!-- unterminated',
    '[s}[l}overlap{s]x{l]',
    '{"a": [1, "b\\n", true]}',
    r'\[escaped\}',
    '# heading\n*a* **b** `c`',
    '😀é🇺🇸',
  ];
  const alphabet = [
    'a', ' ', '\n', '\t', '<', '>', '/', '"', "'", '[', ']', '{', '}', //
    '*', '_', '`', '#', r'\', '&', '=', '.', '\$', '%', '😀', '́',
  ];

  /// Up to [most] characters drawn at random from [alphabet].
  String drawn(Random random, int most) => [
    for (var index = random.nextInt(most + 1); index > 0; index--)
      alphabet[random.nextInt(alphabet.length)],
  ].join();

  group('Arbitrary text', () {
    for (final (offset, name) in syntaxes.keys.indexed) {
      final syntax = formats[name]!;
      test('$name reads it alike twice, tiles it, and derives it again', () {
        final random = Random(0xC0DEC + offset);
        final inputs = [
          ...seeds,
          for (var sample = 0; sample < 300; sample++) drawn(random, 256),
        ];
        for (final source in inputs) {
          final first = syntax.decode(Text.of(source));
          final second = syntax.decode(Text.of(source));
          switch ((first, second)) {
            case (Failure(:final kind, :final message), Failure()):
              expect(kind, Kind.invalid, reason: source);
              expect(message, isNotEmpty, reason: source);
              continue;
            case (Success(value: final one), Success(value: final other)):
              expect(string(one.items), source);
              expect(layers(one), layers(other), reason: source);
              var at = 0;
              for (final token
                  in one.layer(2).items.cast<ARange>().toList()
                    ..sort((a, b) => a.start.compareTo(b.start))) {
                expect(token.start, at, reason: source);
                at = token.end;
              }
              expect(at, one.items.length, reason: source);
            case _:
              fail('read once and refused once: $source');
          }
        }
        // The keystrokes go into all of them at once, some 40,000
        // characters, so that a window reads less than the whole.
        var document = decoded(syntax, inputs.join('\n\n'));
        for (var step = 0; step < 300; step++) {
          final length = document.items.length;
          final Command<int> command = random.nextBool()
              ? Insert(random.nextInt(length + 1), Text.of(drawn(random, 8)))
              : Delete(
                  value(
                    Range.create(
                      random.nextInt(length),
                      min(length, 1 + random.nextInt(8)),
                    ),
                  ),
                );
          if (command case Delete(:final span) when span.end > length) {
            continue;
          }
          document = edited(syntax, document, Edit(1, command));
        }
      });
    }
  });

  group('Reading leaves what it read as it was', () {
    for (final MapEntry(key: name, value: made) in syntaxes.entries) {
      test(name, () {
        const source = 'safe <p>[p}\\fB# x';
        final form = Text.of(source);
        expect(formats[name]!.decode(form), isA<Success<Layered<int>>>());
        expect(
          made(const Limits(items: 1)).decode(form),
          isA<Failure<Layered<int>>>(),
        );
        expect(string(form), source);
      });
    }
  });
}
