import 'dart:io';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:libara_formats/src/lmnl/lmnl.dart' show sawtooth;
import 'package:test/test.dart';

import 'harness.dart';

/// LMNL: sawtooth tags whose ranges may overlap. Ported from markwrite's
/// `lmnl_lex_test`, `lmnl_test` and LMNL's row of `codec_malformed_test`.
void main() {
  const lmnl = LMNL();

  /// The element called [name] in [document], as a range over its tokens.
  ARange element(Layered<int> document, String name) => document
      .layer(3)
      .items
      .cast<ARange>()
      .firstWhere((range) => said(range, '') == name);

  List<String> markup(Layered<int> document) => [
    for (final (name, _) in tokens(document))
      if (name != '#text') name,
  ];

  group('Tokens', () {
    test('the text is kept verbatim', () {
      roundtrip(lmnl, '[p}The [i}quick{i] brown fox.{p]');
    });

    test('a start and an end tag, and the run between them', () {
      expect(tokens(decoded(lmnl, '[p}hi{p]')), [
        ('p', '[p}'),
        ('#text', 'hi'),
        ('p', '{p]'),
      ]);
    });

    test('a start tag carries its annotations, and only the start tag', () {
      final document = decoded(lmnl, '[l [n}144{n] [k}v{k]}one{l]');
      expect(tokens(document).first, ('l', '[l [n}144{n] [k}v{k]}'));
      expect(said(token(document, 0), 'n'), '144');
      expect(said(token(document, 0), 'k'), 'v');
      expect(token(document, 24).attributes.keys, ['']);
    });

    test('an annotation with ranges of its own is kept as it was written', () {
      final document = decoded(lmnl, '[l [n}1[i}4{i]4{n]}a line{l]');
      expect(said(token(document, 0), 'n'), '1[i}4{i]4');
    });

    test('an annotation ends at its end tag, not at one escaped', () {
      final document = decoded(lmnl, r'[l [n}{a\{n]b{n]}x{l]');
      // The escape is resolved in what the annotation says.
      expect(said(token(document, 0), 'n'), '{a{n]b');
      expect(problems(document, 2), isEmpty);
    });

    test('an anonymous tag has the empty name', () {
      expect(tokens(decoded(lmnl, 'a[}b{]c')), [
        ('#text', 'a'),
        ('', '[}'),
        ('#text', 'b'),
        ('', '{]'),
        ('#text', 'c'),
      ]);
    });

    test('an escape is one token, saying the character it escapes', () {
      final document = decoded(lmnl, r'a \[not a tag\} b');
      expect(tokens(document), [
        ('#text', 'a '),
        ('#escape', r'\['),
        ('#text', 'not a tag'),
        ('#escape', r'\}'),
        ('#text', ' b'),
      ]);
      expect(said(token(document, 2), 'shows'), '[');
    });

    for (final marker in ['[', ']', '{', '}', r'\']) {
      test('an escaped $marker is content', () {
        expect(markup(decoded(lmnl, '[p}one \\$marker two{p]')), [
          'p',
          '#escape',
          'p',
        ]);
      });
    }

    test('a comment is a token of its own', () {
      expect(tokens(decoded(lmnl, '[!-- a note --]x')), [
        ('#comment', '[!-- a note --]'),
        ('#text', 'x'),
      ]);
    });

    test('a character outside the BMP is one position', () {
      final document = decoded(lmnl, '[p}a\u{1D11E}b{p]');
      expect(
        [for (final range in document.layer(2).items) range.start],
        [0, 3, 6],
      );
    });
  });

  group('Elements', () {
    test('two that cross rather than nest', () {
      final document = decoded(lmnl, '[a}one [b}two{a] three{b]');
      final a = element(document, 'a');
      final b = element(document, 'b');
      expect((a.start, a.length), (0, 5));
      expect((b.start, b.length), (2, 5));
      expect(a.overlaps(b), isTrue);
      expect(a.contains(b) || b.contains(a), isFalse);
    });

    test('lines and sentences that cut across each other', () {
      final document = decoded(lmnl, '[s}[l}one two{s] three{l]');
      expect(element(document, 's').overlaps(element(document, 'l')), isTrue);
    });

    test('nest where they are written nested', () {
      expect(preorder(decoded(lmnl, '[p}x[a}y{a]z{p]')), [
        '0:#document',
        '1:p',
        '2:a',
      ]);
    });

    test('carry their start tag\'s annotations', () {
      expect(
        said(element(decoded(lmnl, '[l [n}144{n]}one{l]'), 'l'), 'n'),
        '144',
      );
    });

    test('an end tag closes the latest open start tag of its name', () {
      final document = decoded(lmnl, '[a}1[a}2{a]3{a]');
      expect(
        [for (final range in document.layer(3).items) '$range'],
        ['{0,7,:a}', '{2,3,:a}'],
      );
    });

    test('an empty range is an element over its one tag', () {
      final document = decoded(lmnl, 'a[pb [n}4{n]]b');
      expect(tokens(document), [
        ('#text', 'a'),
        ('pb', '[pb [n}4{n]]'),
        ('#text', 'b'),
      ]);
      expect(preorder(document), ['0:#document', '1:pb']);
      expect(said(document.layer(3).items.cast<ARange>().single, 'n'), '4');
    });

    test('an atom is an element over its one tag', () {
      final document = decoded(lmnl, 'a{{br}}b{{x [k}v{k]}}');
      expect(tokens(document), [
        ('#text', 'a'),
        ('br', '{{br}}'),
        ('#text', 'b'),
        ('x', '{{x [k}v{k]}}'),
      ]);
      expect(preorder(document), ['0:#document', '1:br', '1:x']);
    });

    test('a suffix tells apart ranges of one name that overlap', () {
      // a=1 covers "xy", a=2 "yz": by name alone the first end tag would
      // close the second start tag.
      final document = decoded(lmnl, '[a=1}x[a=2}y{a=1]z{a=2]');
      expect(
        [for (final (_, covered) in covering(document)) covered],
        ['[a=1}x[a=2}y{a=1]', '[a=2}y{a=1]z{a=2]'],
      );
      expect(said(token(document, 0), ''), 'a');
    });

    test('an end tag\'s annotations are its element\'s too', () {
      final document = decoded(lmnl, '[l [n}1{n]}x{l [m}2{m]]');
      final element = document.layer(3).items.cast<ARange>().single;
      expect(said(element, 'n'), '1');
      expect(said(element, 'm'), '2');
    });

    test('an anonymous pair is an element with the empty name', () {
      expect(preorder(decoded(lmnl, '[}one{]')), ['0:#document', '1:']);
    });

    test('a close with no open, and an open never closed, are diagnostics', () {
      expect(problems(decoded(lmnl, 'one {em] two'), 3), [
        'end tag {em] closes nothing',
      ]);
      expect(problems(decoded(lmnl, '[p}text'), 3), ['unclosed [p}']);
      expect(decoded(lmnl, '[p}text').layer(3).length, 0);
      expect(problems(decoded(lmnl, '[a=1}x{a=2]'), 3), [
        'unclosed [a=1}',
        'end tag {a=2] closes nothing',
      ]);
    });

    test('and go when the tag pairs after an edit', () {
      final document = decoded(lmnl, '[p}text');
      final next = edited(lmnl, document, Edit(1, Insert(7, Text.of('{p]'))));
      expect(problems(next, 3), isEmpty);
    });
  });

  group('What does not scan', () {
    test('a tag never closed is a diagnostic', () {
      final document = decoded(lmnl, '[p one two');
      expect(problems(document, 2), ['unterminated tag']);
      expect(tokens(document).single, ('#text', '[p one two'));
    });

    test('brackets facing the wrong way are a diagnostic', () {
      final document = decoded(lmnl, '{p}x');
      expect(problems(document, 2), ['brackets facing the wrong way']);
      expect(tokens(document).first, ('#text', '{p}'));
    });

    test('a name beginning with # is a diagnostic', () {
      expect(problems(decoded(lmnl, '[#text}x{#text]'), 2), [
        'a name cannot begin with #',
        'a name cannot begin with #',
      ]);
    });

    // Each input, and whether markwrite's LMNL codec refused it.
    const malformed = {
      'an unterminated start tag': ('<p>one <em two</p>', false),
      'a stray less-than': ('<p>a < b</p>', false),
      'an unterminated character section': ('<p><![CDATA[ a </p>', true),
      'markers and no content': ('<<>><<>>', false),
      'a sawtooth tag never closed': ('[p one [em}two', true),
      'a sawtooth close with no open': ('one {em] two', true),
      'a sawtooth tag with no name': ('[}one{]', false),
      'emphasis never closed': ('one *two three\n', false),
      // markwrite refused this, having no empty ranges; [two] is one.
      'a link never closed': ('one [two](url three\n', false),
      'brackets facing the wrong way': ('one ] two [ three\n', true),
      'nothing at all': ('', false),
    };
    for (final MapEntry(key: name, value: (text, refused))
        in malformed.entries) {
      test(name, () {
        roundtrip(lmnl, text);
        expect(decoded(lmnl, text).valid, !refused);
      });
    }
  });

  group('Edits', () {
    test('typing a tag joins two elements into a crossing', () {
      final document = edited(
        lmnl,
        decoded(lmnl, '[a}one{a] [b}two{b]'),
        Edit(1, Delete(value(Range.create(6, 3)))),
      );
      expect(string(document.items), '[a}one [b}two{b]');
    });

    for (final name in ['markwrite', 'ranges', 'htpasswd']) {
      test('editing $name.lmnl at random derives what a fresh read does', () {
        derivable(
          lmnl,
          File('test/samples/$name.lmnl').readAsStringSync(),
          seed: name.hashCode,
          edits: 300,
        );
      });
    }
  });

  group('Samples', () {
    for (final file
        in Directory('test/samples')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.lmnl'))) {
      test('${file.uri.pathSegments.last} round-trips', () {
        final text = file.readAsStringSync();
        roundtrip(lmnl, text);
        expect(problems(decoded(lmnl, text), 2), isEmpty);
      });
    }
  });

  group('Content and ranges written as LMNL', () {
    /// A range named [name] over tokens [first] to [last].
    ({int first, int last, int depth, String name, Map<String, String> said})
    placed(String name, int first, int last) =>
        (first: first, last: last, depth: 0, name: name, said: const {});

    // The content 'aabbcc', one token per letter pair.
    const content = 'aabbcc';
    const offsets = [0, 2, 4, 6];

    test('two ranges of one name that cross are told apart by a suffix', () {
      final text = string(
        value(
          sawtooth(content, offsets, [placed('em', 0, 2), placed('em', 1, 3)]),
        ),
      );
      expect(text, '[em}aa[em=1}bb{em]cc{em=1]');
      final document = decoded(lmnl, text);
      expect(
        [
          for (final (range, covered) in covering(document))
            (said(range, ''), covered),
        ],
        [('em', '[em}aa[em=1}bb{em]'), ('em', '[em=1}bb{em]cc{em=1]')],
      );
    });

    test('ranges of one name that nest need no suffix', () {
      expect(
        string(
          value(
            sawtooth(content, offsets, [
              placed('em', 0, 3),
              placed('em', 1, 2),
            ]),
          ),
        ),
        '[em}aa[em}bb{em]cc{em]',
      );
    });
  });
}
