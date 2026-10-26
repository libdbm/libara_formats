import 'dart:convert';
import 'dart:io';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// Markdown's blocks: the markers that represent them are tokens named for the
/// block they belong to, the rest of the text is runs of `#text`, and each
/// block is an element over the tokens it covers, a paragraph a range with
/// no tokens of its own.
void main() {
  const markdown = Markdown();

  /// [document]'s elements in pre-order, each as its name and the text it
  /// covers.
  List<(String, String)> elements(Layered<int> document) => [
    for (final (element, text) in covering(document))
      ('${element.get('')}', text),
  ];

  List<String> names(String text) => [
    for (final (name, _) in elements(decoded(markdown, text))) name,
  ];

  group('Blocks', () {
    test('a heading marker is a token of the heading, a paragraph none', () {
      final document = decoded(markdown, '# Title\n\nWords.');
      expect(tokens(document), [
        ('h1', '# '),
        ('#text', 'Title'),
        ('#text', '\n\n'),
        ('#text', 'Words.'),
      ]);
      expect(elements(document), [('h1', '# Title'), ('p', 'Words.')]);
    });

    test('a quote marks every line it carries on', () {
      final document = decoded(markdown, '> a\n> b');
      expect(tokens(document), [
        ('blockquote', '> '),
        ('#text', 'a\n'),
        ('blockquote', '> '),
        ('#text', 'b'),
      ]);
      expect(elements(document), [('blockquote', '> a\n> b'), ('p', 'a\n> b')]);
    });

    test('a heading closed with hashes', () {
      expect(tokens(decoded(markdown, '## T ##')), [
        ('h2', '## '),
        ('#text', 'T'),
        ('h2', ' ##'),
      ]);
    });

    test('a setext heading is the paragraph above its underline', () {
      final document = decoded(markdown, 'para\n---\n');
      expect(elements(document), [('h2', 'para\n---')]);
      expect(tokens(document).last, ('#text', '\n'));
    });

    test(
      'a tight list holds its words in its items, a loose one in paragraphs',
      () {
        expect(elements(decoded(markdown, '- a\n- b\n')), [
          ('ul', '- a\n- b'),
          ('li', '- a'),
          ('li', '- b'),
        ]);
        expect(names('- a\n\n- b\n'), ['ul', 'li', 'p', 'li', 'p']);
      },
    );

    test('a numbered list says where it starts counting', () {
      final document = decoded(markdown, '3. a\n4. b\n');
      final list = document
          .layer(3)
          .items
          .cast<ARange>()
          .firstWhere((range) => said(range, '') == 'ol');
      expect(said(list, ''), 'ol');
      expect(said(list, 'start'), '3');
      expect(
        said(
          decoded(markdown, '1. a\n').layer(3).items.first as ARange,
          'start',
        ),
        isNull,
      );
    });

    test('a fence is a token, and the code between is text', () {
      final document = decoded(markdown, '```js\ncode\n```\n');
      expect(tokens(document), [
        ('pre', '```js\n'),
        ('#text', 'code\n'),
        ('pre', '```'),
        ('#text', '\n'),
      ]);
      final code = document.layer(3).items.single as ARange;
      expect(said(code, 'class'), 'language-js');
    });

    test('indented code and a rule', () {
      expect(tokens(decoded(markdown, '    code\n')).first, ('pre', '    '));
      expect(elements(decoded(markdown, 'a\n\n***\n')), [
        ('p', 'a'),
        ('hr', '***'),
      ]);
    });
  });

  group('A Markdown document written with CRLF line endings', () {
    test('breaks its paragraphs where a blank line stands', () {
      expect(names('a\r\n\r\nb\r\n'), ['p', 'p']);
    });

    test('and reads a setext heading and a rule', () {
      expect(names('para\r\n---\r\n'), ['h2']);
      expect(names('a\r\n\r\n***\r\n'), ['p', 'hr']);
    });

    test('and an ATX heading and a fence', () {
      expect(names('# T\r\n\r\n```\r\ncode\r\n```\r\n'), ['h1', 'pre']);
    });

    test('and a list, the same as the one written without returns', () {
      expect(names('- a\r\n- b\r\n'), names('- a\n- b\n'));
      expect(names('1. a\r\n   b\r\n2. c\r\n'), names('1. a\n   b\n2. c\n'));
    });
  });

  group('Markdown nested past the limit', () {
    test('in its blocks is refused', () {
      final read = const Markdown(limits: Limits(depth: 32))
          .decode(Text.of('${'>' * 100}x'));
      expect(read, isA<Failure<Object?>>());
      expect((read as Failure<Object?>).message, contains('deeper'));
    });

    test('and nesting up to the standard limit is read', () {
      expect(
        markdown.decode(Text.of('${'>' * 4000}x')),
        isA<Success<Layered<int>>>(),
      );
    });
  });

  group('A paragraph', () {
    test('takes a character typed at its head', () {
      final document = edited(
        markdown,
        decoded(markdown, 'second paragraph\n'),
        Edit(1, Insert(0, Text.of('X'))),
      );
      expect(elements(document), [('p', 'Xsecond paragraph')]);
    });

    test('takes a character typed at its head, mid document', () {
      final document = edited(
        markdown,
        decoded(markdown, 'first\n\nsecond\n'),
        Edit(1, Insert(7, Text.of('X'))),
      );
      expect(elements(document), [('p', 'first'), ('p', 'Xsecond')]);
    });
  });

  group('Re-reading after a keystroke', () {
    test('a fence opened in the window runs on past it', () {
      final text = 'a\n\nb\n\nc\n\nd\n\ne\n\nf\n';
      final document = edited(
        markdown,
        decoded(markdown, text),
        Edit(1, Insert(text.indexOf('c'), Text.of('```\n'))),
      );
      expect(names(string(document.items)), ['p', 'p', 'pre']);
    });

    test('a list item carried on past the window by an indented line', () {
      final text = 'a\n\nb\n\nc\n\nd\n\n    e\n';
      edited(
        markdown,
        decoded(markdown, text),
        Edit(1, Insert(text.indexOf('d'), Text.of('- '))),
      );
    });

    test('an item marked as the list before it marks joins that list', () {
      // Changed after the line's first character, so the line still starts
      // a block before the change.
      final text = 'p\n\n1. a\n\n2) c\n';
      final document = edited(
        markdown,
        decoded(markdown, text),
        Edit(
          1,
          Replace(value(Range.create(text.indexOf(')'), 1)), Text.of('.')),
        ),
      );
      expect(names(string(document.items)), ['p', 'ol', 'li', 'p', 'li', 'p']);
    });

    test('a paragraph taken out leaves one run of blank lines', () {
      final text = 'a\n\nb\n\nc\n';
      final document = edited(
        markdown,
        decoded(markdown, text),
        Edit(1, Delete(value(Range.create(text.indexOf('b'), 1)))),
      );
      expect(tokens(document)[1], ('#text', '\n\n\n\n'));
    });

    test('a quote\'s angle taken from its head reads its line again', () {
      final text = 'a\n\n> quote\n';
      final document = edited(
        markdown,
        decoded(markdown, text),
        Edit(1, Delete(value(Range.create(text.indexOf('>'), 1)))),
      );
      expect(names(string(document.items)), ['p', 'p']);
    });

    test('a block typed after the last blank line', () {
      final document = edited(
        markdown,
        decoded(markdown, 'a\n\n'),
        Edit(1, Insert(3, Text.of('b'))),
      );
      expect(names(string(document.items)), ['p', 'p']);
    });

    test('a paragraph indented by a space, once what was above it goes', () {
      edited(
        markdown,
        decoded(markdown, '# T\n x\n\nc\n'),
        Edit(1, Delete(value(Range.create(0, 3)))),
      );
    });

    test('reads again only the blocks around it, indented or not', () {
      for (final head in ['', ' ']) {
        final text = '${head}words\n\n' * 100;
        final document = decoded(markdown, text);
        final window = document.grammar.affected(
          document,
          2,
          value(Range.create(text.length ~/ 2, 1)),
        );
        expect(window.length, lessThan(text.length ~/ 10), reason: '"$head"');
      }
    });

    test('a blank line taken out joins the blocks', () {
      final text = 'a\n\nb\n\nc\n';
      final document = edited(
        markdown,
        decoded(markdown, text),
        Edit(1, Delete(value(Range.create(2, 1)))),
      );
      expect(names(string(document.items)), ['p', 'p']);
    });

    for (final name in ['markwrite', 'ranges', 'htpasswd']) {
      test('editing $name.md at random derives what a fresh read does', () {
        derivable(
          markdown,
          File('test/samples/$name.md').readAsStringSync(),
          seed: name.hashCode,
          edits: 200,
        );
      });
    }
  });

  group('What a keystroke does not make the derivation do again', () {
    test('an element standing before the edit keeps its marker', () {
      const text = 'one\n\ntwo\n\nthree\n\nfour\n';
      final document = decoded(markdown, text);
      final first = document.markers(3).first.$1;
      final next = value(
        document.apply(Edit(1, Insert(text.indexOf('four'), Text.of('x')))),
      ).document;
      expect(next.markers(3).first.$1, first);
    });

    test('and one standing after it says where it stands now', () {
      final document = edited(
        markdown,
        decoded(markdown, 'one\n\ntwo\n'),
        Edit(1, Insert(0, Text.of('xx'))),
      );
      expect(elements(document).last, ('p', 'two'));
      expect(string(document.slice(token(document, 7))), 'two');
    });
  });

  group('Every Markdown file round-trips', () {
    for (final file in Directory(
      'test/samples',
    ).listSync().whereType<File>().where((file) => file.path.endsWith('.md'))) {
      test(file.uri.pathSegments.last, () {
        roundtrip(markdown, file.readAsStringSync());
      });
    }

    test('and every CommonMark example', () {
      final examples = jsonDecode(
        File('test/commonmark/spec.json').readAsStringSync(),
      ) as List;
      for (final example in examples) {
        roundtrip(markdown, (example as Map)['markdown'] as String);
      }
    });
  });
}
