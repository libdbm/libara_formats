import 'dart:io';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// JSON: tokens as written, values over them, and edits to the characters of
/// strings.
void main() {
  const json = JSON();

  /// [document]'s values, each as its name and the text it covers.
  List<(String, String)> values(Layered<int> document) => [
    for (final (value, text) in covering(document)) (said(value, '')!, text),
  ];

  group('Tokens', () {
    test('the text is kept verbatim', () {
      roundtrip(json, '{ "a" : [1, true, null, "x\\ny"] }\n');
    });

    test('punctuation, strings, whitespace and scalars', () {
      expect(tokens(decoded(json, '{"a b": [-1.5e3, false]}')), [
        ('{', '{'),
        ('#string', '"a b"'),
        (':', ':'),
        ('#space', ' '),
        ('[', '['),
        ('#number', '-1.5e3'),
        (',', ','),
        ('#space', ' '),
        ('#literal', 'false'),
        (']', ']'),
        ('}', '}'),
      ]);
    });

    test('a string shows its characters, a pair of escapes one character', () {
      final document = decoded(json, r'"a\"b\u00e9\ud83d\ude00"');
      expect(tokens(document).map((token) => token.$1), ['#string']);
      expect(said(token(document, 0), 'shows'), 'a"bé😀');
    });

    test('what does not scan is an error, said where it is', () {
      final document = decoded(json, '[01, nul, "a\\qb", "open\n]');
      expect(problems(document, 2), [
        '"01" is not a JSON value',
        '"nul" is not a JSON value',
        'not an escape',
        'unclosed "',
      ]);
    });

    test('a line break ends a string, so the next line reads as it did', () {
      expect(tokens(decoded(json, '"a\n"b"')), [
        ('#string', '"a'),
        ('#space', '\n'),
        ('#string', '"b"'),
      ]);
    });

    test('a backslash before a line break leaves the break to end it', () {
      final document = decoded(json, '["a\\\n"b"]');
      expect(tokens(document), [
        ('[', '['),
        ('#string', '"a\\'),
        ('#space', '\n'),
        ('#string', '"b"'),
        (']', ']'),
      ]);
      expect(problems(document, 2), ['unclosed "']);
    });
  });

  group('Values', () {
    test('each value over its tokens, a member from its name', () {
      expect(values(decoded(json, '{"a": [1, "x"], "b": null}')), [
        ('object', '{"a": [1, "x"], "b": null}'),
        ('member', '"a": [1, "x"]'),
        ('string', '"a"'),
        ('array', '[1, "x"]'),
        ('number', '1'),
        ('string', '"x"'),
        ('member', '"b": null'),
        ('string', '"b"'),
        ('null', 'null'),
      ]);
    });

    test('a member says its name, escapes decoded', () {
      final document = decoded(json, r'{"a\tb": true}');
      final member = document
          .layer(3)
          .items
          .cast<ARange>()
          .firstWhere((range) => said(range, '') == 'member');
      expect(said(member, 'key'), 'a\tb');
      expect(values(document).last, ('boolean', 'true'));
    });

    test('what does not parse is said, and the rest is read', () {
      final cases = {
        '[1 2]': ['expected , or ]'],
        '[1,]': ['a comma before the end'],
        '{"a" 1}': ['expected :'],
        '{"a":}': ['expected a value'],
        '{1}': ['expected a member name'],
        '[1}': ['unclosed array', '} closes nothing'],
        '{"a": [1}': ['unclosed array'],
        '1 2': ['more than one value'],
        '[': ['unclosed array'],
      };
      for (final MapEntry(key: text, value: said) in cases.entries) {
        expect(problems(decoded(json, text), 3), said, reason: text);
      }
      expect(values(decoded(json, '{"a": [1}')).map((value) => value.$1), [
        'object',
        'member',
        'string',
        'array',
        'number',
      ]);
    });

    test('values nested past the limit refuse the read', () {
      const shallow = JSON(limits: Limits(depth: 2));
      expect(shallow.decode(Text.of('[[1]]')), isA<Success<Layered<int>>>());
      expect(shallow.decode(Text.of('[[[1]]]')), isA<Failure<Layered<int>>>());
    });
  });

  group('Editing', () {
    test('the layers after random edits are those a fresh read gives', () {
      final text = File('test/corpora/subset_cases.json').readAsStringSync();
      for (final seed in [1, 2, 3]) {
        derivable(json, text, seed: seed);
      }
    });

    test('the characters of a string are text, and nothing else is', () {
      final document = decoded(json, '{"key": "word", "n": 12}');
      Result<Change<int>> typed(int at, String text) =>
          document.grammar.valid(document, Edit(1, Insert(at, Text.of(text))));
      expect(typed(11, 'x'), isA<Success<Change<int>>>());
      expect(typed(3, 'x'), isA<Success<Change<int>>>());
      expect(typed(11, '"'), isA<Failure<Change<int>>>());
      expect(typed(22, '3'), isA<Failure<Change<int>>>());
      expect(typed(15, 'x'), isA<Failure<Change<int>>>());
    });

    test('escaped text goes into a string as the same characters', () {
      const typed = 'a "quoted" \\ line\nend\u0001';
      final document = decoded(json, '{"": 1}');
      final written = document.grammar.escaped(typed.runes.toList());
      final made = value(
        document.grammar.valid(document, Edit(1, Insert(2, Items.of(written)))),
      ).document;
      final member = made
          .layer(3)
          .items
          .cast<ARange>()
          .firstWhere((range) => said(range, '') == 'member');
      expect(said(member, 'key'), typed);
    });

    test('a structural edit is refused', () {
      final document = decoded(json, '[1, 2]');
      refused(document, Edit(2, Delete(value(Range.create(1, 1)))), 'json');
    });

    test('a document read in another syntax is not written as JSON', () {
      expect(
        json.encode(decoded(const XML(), '<p>x</p>')),
        isA<Failure<Sequence<int>>>(),
      );
    });
  });
}
