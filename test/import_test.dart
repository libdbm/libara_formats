import 'dart:math';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:libara_formats/src/convert.dart' show Linked, projected;
import 'package:libara_formats/src/import/assemble.dart';
import 'package:libara_formats/src/import/styles.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// What every importer shares: content and ranges made into the LMNL
/// document an import gives.
void main() {
  /// A span from [start] to [end], in code points, called [name].
  Span span(
    int start,
    int end,
    String name, [
    Map<String, String> said = const {},
  ]) => (start: start, end: end, name: name, said: said);

  /// [document]'s elements, each as its name, what it says, and the content
  /// it covers, sorted.
  List<String> elements(Layered<int> document) {
    final (:content, :offsets, :elements) = projected(document);
    return [
      for (final element in elements)
        '${element.name} ${element.said} '
            '"${content.substring(offsets[element.first], offsets[element.last])}"',
    ]..sort();
  }

  /// [spans] over [content] as [elements] gives them.
  List<String> expected(String content, List<Span> spans) {
    final points = content.runes.toList();
    return [
      for (final one in spans)
        '${one.name} ${one.said} '
            '"${String.fromCharCodes(points.sublist(one.start, one.end))}"',
    ]..sort();
  }

  group('Assembling', () {
    final cases = <String, (String, List<Span>)>{
      'spans that nest': ('aabbcc', [span(0, 6, 'p'), span(2, 4, 'em')]),
      'spans that cross': ('aabbcc', [span(0, 4, 'em'), span(2, 6, 'strong')]),
      'two spans of one name that cross': (
        'aabbcc',
        [span(0, 4, 'em'), span(2, 6, 'em')],
      ),
      'an empty span': ('aabb', [span(0, 4, 'p'), span(2, 2, 'br')]),
      'a span over the whole content': ('aabb', [span(0, 4, 'p')]),
      'markup characters in the content': (
        r'a[b]c{d}e\f',
        [span(0, 11, 'p'), span(1, 4, 'em')],
      ),
      'characters past the BMP': (
        'a😀b😀c',
        [span(0, 5, 'p'), span(1, 4, 'em')],
      ),
    };
    for (final MapEntry(key: name, value: (content, spans)) in cases.entries) {
      test(name, () {
        final document = value(assemble('test', content, spans));
        expect(elements(document), expected(content, spans));
        expect(problems(document, 3), isEmpty);
      });
    }

    test('an attribute holding markup characters reads back as it was', () {
      // LMNL resolves the escapes the writer puts in an annotation.
      final document = value(
        assemble('test', 'a', [
          span(0, 1, 'p', {'class': r'x[y]{z}\w'}),
        ]),
      );
      expect(elements(document), [r'p {class: x[y]{z}\w} "a"']);
    });

    test('spans that start together are placed the longer first', () {
      final document = value(
        assemble('test', 'aabb', [span(0, 2, 'em'), span(0, 4, 'p')]),
      );
      expect(string(document.items), '[p}[em}aa{em]bb{p]');
    });
  });

  group('Lists', () {
    /// An item of a [list] at [level], over [start] to [end].
    Span item(int start, int end, String list, [int? level]) =>
        span(start, end, 'li', {'list': list, 'level': ?level?.toString()});

    /// [document]'s elements, each with how deep it is, in pre-order.
    List<String> tree(Layered<int> document) {
      final (:content, :offsets, :elements) = projected(document);
      return [
        for (final element in elements)
          '${element.depth} ${element.name} ${element.said} '
              '"${content.substring(offsets[element.first], offsets[element.last])}"',
      ];
    }

    test('items of one list in a row are one list', () {
      final document = value(
        assemble('test', 'a\nb\nc\n', [
          item(0, 2, 'ul'),
          item(2, 4, 'ul'),
          item(4, 6, 'ul'),
        ]),
      );
      expect(tree(document), [
        '0 ul {} "a\nb\nc\n"',
        '1 li {} "a\n"',
        '1 li {} "b\n"',
        '1 li {} "c\n"',
      ]);
    });

    test('an item of another kind starts another list', () {
      final document = value(
        assemble('test', 'a\nb\n', [item(0, 2, 'ul'), item(2, 4, 'ol')]),
      );
      expect(tree(document), [
        '0 ul {} "a\n"',
        '1 li {} "a\n"',
        '0 ol {} "b\n"',
        '1 li {} "b\n"',
      ]);
    });

    test('a paragraph between items ends the list', () {
      final document = value(
        assemble('test', 'a\nb\nc\n', [
          item(0, 2, 'ul'),
          span(2, 4, 'p'),
          item(4, 6, 'ul'),
        ]),
      );
      expect(tree(document), [
        '0 ul {} "a\n"',
        '1 li {} "a\n"',
        '0 p {} "b\n"',
        '0 ul {} "c\n"',
        '1 li {} "c\n"',
      ]);
    });

    test('deeper items are a list held by the item before them', () {
      final document = value(
        assemble('test', 'a\nb\nc\nd\n', [
          item(0, 2, 'ul', 1),
          item(2, 4, 'ul', 2),
          item(4, 6, 'ul', 2),
          item(6, 8, 'ul', 1),
        ]),
      );
      expect(tree(document), [
        '0 ul {} "a\nb\nc\nd\n"',
        '1 li {} "a\nb\nc\n"',
        '2 ul {} "b\nc\n"',
        '3 li {} "b\n"',
        '3 li {} "c\n"',
        '1 li {} "d\n"',
      ]);
    });
  });

  group('Revisions', () {
    // "aa bb cc" in a paragraph, with an em over "bb": in LMNL,
    // "[p}aa [em}bb{em] cc{p]".
    const content = 'aa bb cc';
    final spans = [span(0, 8, 'p'), span(3, 5, 'em')];

    /// [document]'s annotations over its text, each as its name, what else
    /// it says, and the text it covers.
    List<String> noted(Layered<int> document) => [
      for (final (_, range) in document.annotations(1))
        '${said(range, '')} ${said(range, 'author')} '
            '"${string(document.items.slice(range.start, range.length))}"',
    ];

    test('each is an annotation over the characters it concerns', () {
      final document = value(
        assemble(
          'test',
          content,
          spans,
          revisions: [
            span(0, 2, 'ins', {'author': 'Ann'}),
            span(6, 8, 'del', {'author': 'Bob'}),
          ],
        ),
      );
      expect(string(document.items), '[p}aa [em}bb{em] cc{p]');
      expect(noted(document), ['ins Ann "aa"', 'del Bob "cc"']);
    });

    test('one across a tag covers the tag as well', () {
      final document = value(
        assemble(
          'test',
          content,
          spans,
          revisions: [
            span(1, 4, 'ins', {'author': 'Ann'}),
          ],
        ),
      );
      expect(noted(document), ['ins Ann "a [em}b"']);
    });

    test('one moves with its characters when text is typed before it', () {
      final document = value(
        assemble(
          'test',
          content,
          spans,
          revisions: [
            span(6, 8, 'del', {'author': 'Bob'}),
          ],
        ),
      );
      final typed = value(document.apply(Edit(1, Insert(4, Text.of('x')))))
          .document;
      expect(noted(typed), ['del Bob "cc"']);
    });

    test('none is written when the document is', () {
      final document = value(
        assemble(
          'test',
          content,
          spans,
          revisions: [
            span(0, 2, 'ins', {'author': 'Ann'}),
          ],
        ),
      );
      expect(
        string(value(const XML().encode(document))),
        '<p>aa <em>bb</em> cc</p>',
      );
    });

    test('one over no characters is refused', () {
      expect(
        assemble('test', content, spans, revisions: [span(2, 2, 'ins')]),
        isA<Failure<Layered<int>>>()
            .having((failure) => failure.kind, 'kind', Kind.invalid)
            .having((failure) => failure.message, 'message', contains('ins')),
      );
    });
  });

  group('Styles', () {
    test('each row of the table, case and spaces ignored', () {
      const rows = {
        'heading 1': ('h1', null),
        'Heading3': ('h3', null),
        'HEADING 6': ('h6', null),
        'Title': ('h1', null),
        'Normal': ('p', null),
        'Body': ('p', null),
        'Body Text': ('p', null),
        'Default': ('p', null),
        'List Bullet': ('li', 'ul'),
        'Bulleted': ('li', 'ul'),
        'List Number': ('li', 'ol'),
        'Numbered': ('li', 'ol'),
        'Quote': ('blockquote', null),
        'Block Text': ('blockquote', null),
        'Code': ('pre', null),
        'Preformatted': ('pre', null),
        'HTML Preformatted': ('pre', null),
        'Horizontal Line': ('hr', null),
      };
      for (final MapEntry(key: style, value: (name, list)) in rows.entries) {
        expect(styled(style), (name: name, list: list), reason: style);
      }
    });

    test('an outline level from 1 to 6 is a heading of that level', () {
      expect(styled('Normal', level: 2), (name: 'h2', list: null));
      expect(styled('Quote', level: 6), (name: 'h6', list: null));
      expect(styled('Normal', level: 7), (name: 'p', list: null));
      expect(styled('Normal', level: 0), (name: 'p', list: null));
    });

    test('a name the table does not know is a paragraph', () {
      expect(styled('Fancy Caption'), (name: 'p', list: null));
    });
  });

  test('a document not stored in reading order is not written', () {
    final document = value(Layered.of(Text.of('ab'), const _Stored()));
    for (final MapEntry(:key, :value) in {
      'xml': const XML(),
      'html': const HTML(),
      'markdown': const Markdown(),
      'latex': const LaTeX(),
      'man': const Man(),
      'lmnl': const LMNL(),
    }.entries) {
      expect(
        value.encode(document),
        isA<Failure<Sequence<int>>>()
            .having((failure) => failure.kind, 'kind', Kind.invalid)
            .having(
              (failure) => failure.message,
              'message',
              allOf(startsWith('$key: '), contains('import')),
            ),
        reason: key,
      );
    }
  });

  test('an importer whose file is not in reading order, end to end', () {
    // Its second paragraph is stored first, and an em runs from the end of
    // the first into the second.
    const file = 'P2 cc dd\nP1 aa bb\nEM 3 8\n';
    final document = value(const _Ordered().decode(Text.of(file)));
    expect(string(document.items), '[p}aa [em}bb\n{p][p}cc{em] dd\n{p]');
    expect(
      string(value(const HTML().encode(document))),
      '<p>aa <em>bb\n</em></p><p><em>cc</em> dd\n</p>',
    );
  });

  group('Refusals', () {
    Matcher refused(String why) => isA<Failure<Layered<int>>>()
        .having((failure) => failure.kind, 'kind', Kind.invalid)
        .having(
          (failure) => failure.message,
          'message',
          allOf(startsWith('test: '), contains(why)),
        );

    test('a span past the end of the content', () {
      expect(assemble('test', 'aa', [span(0, 3, 'p')]), refused('past'));
    });

    test('a span ending before it starts', () {
      expect(assemble('test', 'aa', [span(2, 1, 'p')]), refused('before'));
    });

    test('a name a tag cannot hold', () {
      expect(assemble('test', 'aa', [span(0, 2, 'a b')]), refused('a b'));
    });

    test('content past the limit', () {
      expect(
        assemble('test', 'aaaa', [], limits: const Limits(items: 3)),
        refused('limit'),
      );
    });
  });

  test('random content and spans read back as their spans', () {
    for (var seed = 0; seed < 200; seed++) {
      final random = Random(seed);
      const letters = r'ab [{\}]😀';
      final points = letters.runes.toList();
      final content = String.fromCharCodes([
        for (var at = random.nextInt(20); at > 0; at--)
          points[random.nextInt(points.length)],
      ]);
      final length = content.runes.length;
      final spans = [
        for (var count = random.nextInt(6); count > 0; count--)
          if (random.nextInt(length + 1) case final start)
            span(
              start,
              start + random.nextInt(length - start + 1),
              ['p', 'em', 'strong'][random.nextInt(3)],
            ),
      ];
      final document = value(assemble('test', content, spans));
      expect(
        elements(document),
        expected(content, spans),
        reason: 'seed $seed: $content $spans',
      );
    }
  });
}

/// A syntax whose content is not stored in reading order: one run of text,
/// and one paragraph over it.
final class _Stored implements Grammar<int>, Linked {
  const _Stored();

  @override
  int get depth => 3;

  @override
  Derived derive(Layered<int> document, int layer, Range region) => (
    ranges: [
      ARange.from(
        value(
          Range.create(
            0,
            layer == 2 ? document.items.length : document.layer(2).length,
          ),
        ),
        {'': Str(Text.of(layer == 2 ? '#text' : 'p'))},
      ),
    ],
    diagnostics: const [],
  );

  @override
  Range affected(Layered<int> document, int layer, Range changed) => value(
    Range.create(
      0,
      layer == 2 ? document.items.length : document.layer(2).length,
    ),
  );

  @override
  Result<Derivation<int>> edit(Layered<int> document, Edit<int> change) =>
      const Failure(Kind.invalid, 'stored: no structural edits');

  @override
  Result<Change<int>> valid(Layered<int> document, Edit<int> change) =>
      const Failure(Kind.invalid, 'stored: no edits');

  @override
  List<int> escaped(List<int> text, {bool raw = false}) => text;

  @override
  Crossing crossing(Layered<int> document, int layer, ARange range) =>
      Crossing.refuse;
}

/// An importer for a made-up format: lines `P2 cc dd`, a paragraph to be
/// read second, in any order, and `EM 3 8`, emphasis over those characters
/// of the content in reading order.
final class _Ordered implements Readable {
  const _Ordered();

  @override
  Result<Layered<int>> decode(Sequence<int> form) {
    final lines = String.fromCharCodes(form.items).trim().split('\n');
    final paragraphs = [
      for (final line in lines)
        if (line.startsWith('P'))
          (int.parse(line.substring(1, line.indexOf(' '))), line),
    ]..sort((one, other) => one.$1 - other.$1);
    final content = StringBuffer();
    final spans = <Span>[];
    for (final (_, line) in paragraphs) {
      final start = content.length;
      content.write('${line.substring(line.indexOf(' ') + 1)}\n');
      spans.add((start: start, end: content.length, name: 'p', said: const {}));
    }
    for (final line in lines) {
      if (line.startsWith('EM ')) {
        final [_, start, end] = line.split(' ');
        spans.add((
          start: int.parse(start),
          end: int.parse(end),
          name: 'em',
          said: const {},
        ));
      }
    }
    return assemble('ordered', content.toString(), spans);
  }
}
