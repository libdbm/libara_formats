import 'dart:io';
import 'dart:math';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// Markdown's structural edits: each is the text it writes or takes away,
/// read again, so every one leaves the layers a fresh read gives.
void main() {
  const markdown = Markdown();

  Layered<int> read(String text) => decoded(markdown, text);

  group('Layer 2: markup', () {
    test('emphasis is written a delimiter at a time', () {
      var document = read('a b c\n');
      document = edited(markdown, document, Edit(2, Mark(Close(3, 'em'))));
      expect(tokens(document).where((token) => token.$1 == 'em'), isEmpty);
      document = edited(markdown, document, Edit(2, Mark(Open(2, 'em'))));
      expect(string(document.items), 'a *b* c\n');
      expect(tokens(document)[1], ('em', '*'));
    });

    test('a link closes with where it goes', () {
      var document = read('a b c\n');
      document = edited(
        markdown,
        document,
        Edit(2, Mark(Close(3, 'a', {'href': '/u', 'title': 'T'}))),
      );
      document = edited(markdown, document, Edit(2, Mark(Open(2, 'a'))));
      expect(string(document.items), 'a [b](/u "T") c\n');
    });

    test('a block is written at the head of its words', () {
      final document = edited(
        markdown,
        read('para\n'),
        Edit(2, Mark(Open(0, 'h2'))),
      );
      expect(string(document.items), '## para\n');
    });

    test('markup written inside a token reads what holds it again', () {
      final document = edited(
        markdown,
        read('a\n\n```js\ncode\n```\n'),
        Edit(2, Mark(Open(8, 'a'))),
      );
      final code = document.layer(3).items.last as ARange;
      expect(said(code, 'class'), 'language-js[');
    });

    test('deleting tokens takes their markup away', () {
      final document = read('a *b* c\n');
      final next = edited(
        markdown,
        document,
        Edit(2, Delete(value(Range.create(at(document, '*'), 1)))),
      );
      expect(string(next.items), 'a b* c\n');
    });

    test('a name Markdown has no representation for is refused', () {
      refused(
        read('a\n'),
        Edit(2, Mark(Open(0, 'span'))),
        'no representation for',
      );
      refused(read('a\n'), Edit(2, Mark(Close(1, 'a'))), 'where it goes');
    });

    test('nothing is unmarked or renamed at layer 2', () {
      final document = read('a *b* c\n');
      final token = document.markers(2)[1].$1;
      refused(document, Edit(2, Unmark(token)), 'layer 3');
      refused(
        document,
        Edit(2, Update(token, {'': Str(Text.of('strong'))})),
        'layer 3',
      );
    });
  });

  group('Layer 3: wrapping', () {
    for (final (name, extra, written) in [
      ('em', <String, String>{}, '*a b c*\n'),
      ('strong', <String, String>{}, '**a b c**\n'),
      ('code', <String, String>{}, '`a b c`\n'),
      ('a', {'href': '/u'}, '[a b c](/u)\n'),
    ]) {
      test('words in $name', () {
        final document = read('a b c\n');
        final marker = Marker();
        final next = edited(
          markdown,
          document,
          Edit(
            3,
            Mark.of(
              marker,
              over(at(document, 'a b c'), 1, {'': name, ...extra}),
            ),
          ),
        );
        expect(string(next.items), written);
        expect(said(marked(next, marker), ''), name);
      });
    }

    for (final (name, written) in [
      ('h2', '## a\n'),
      ('blockquote', '> a\n'),
      ('ul', '- a\n'),
      ('ol', '1. a\n'),
      ('pre', '```\na\n```\n'),
    ]) {
      test('a paragraph in $name', () {
        final document = read('a\n');
        final marker = Marker();
        final next = edited(
          markdown,
          document,
          Edit(3, Mark.of(marker, over(0, 1, {'': name}))),
        );
        expect(string(next.items), written);
        expect(said(marked(next, marker), ''), name);
      });
    }

    test('two paragraphs in a quote, every line of them', () {
      final document = read('a\n\nb\n');
      final next = edited(
        markdown,
        document,
        Edit(3, Mark(over(0, 3, {'': 'blockquote'}))),
      );
      expect(string(next.items), '> a\n> \n> b\n');
    });

    test('inside a quote, the quote carries on around what is written', () {
      final document = read('> a b c\n');
      final words = at(document, 'a b c');
      var next = edited(
        markdown,
        document,
        Edit(3, Mark(over(words, 1, {'': 'pre'}))),
      );
      expect(string(next.items), '> ```\n> a b c\n> ```\n');
      next = edited(
        markdown,
        read('> a\n> b\n'),
        Edit(3, Mark(over(1, 3, {'': 'blockquote'}))),
      );
      expect(string(next.items), '> > a\n> > b\n');
    });

    test('a numbered list says where it starts', () {
      final next = edited(
        markdown,
        read('a\n'),
        Edit(3, Mark(over(0, 1, {'': 'ol', 'start': '3'}))),
      );
      expect(string(next.items), '3. a\n');
    });

    test('a name with no representation is refused', () {
      refused(
        read('a\n'),
        Edit(3, Mark(over(0, 1, {'': 'span'}))),
        'no representation for',
      );
    });
  });

  group('Layer 3: lists', () {
    /// The new list of [name] over [document]'s elements from [first] to
    /// [last], and the marker it is made under.
    (Layered<int>, Marker) listed(
      Layered<int> document,
      String name,
      ARange first, [
      ARange? last,
    ]) {
      final marker = Marker();
      final end = (last ?? first).end;
      return (
        edited(
          markdown,
          document,
          Edit(
            3,
            Mark.of(marker, over(first.start, end - first.start, {'': name})),
          ),
        ),
        marker,
      );
    }

    ARange nth(Layered<int> document, String name, [int index = 0]) =>
        marked(document, element(document, name, index));

    for (final (name, text, written) in [
      ('ul', 'one\n\ntwo\n', '- one\n- two\n'),
      ('ol', 'one\n\ntwo\n', '1. one\n1. two\n'),
      ('ul', 'one\nmore\n\ntwo\n', '- one\n  more\n- two\n'),
      ('ul', '> one\n>\n> two\n', '> - one\n> - two\n'),
    ]) {
      test('blocks made items of a $name, a marker on each', () {
        final document = read(text);
        final (next, marker) = listed(
          document,
          name,
          nth(document, 'p'),
          nth(document, 'p', 1),
        );
        expect(string(next.items), written);
        expect(said(marked(next, marker), ''), name);
      });
    }

    for (final (text, index, written) in [
      ('- one\n- two\n', 1, '- one\n  - two\n'),
      ('- one\n- two\n  - three\n', 1, '- one\n  - two\n    - three\n'),
      ('- a\n- b\n  - c\n    - d\n', 1, '- a\n  - b\n    - c\n      - d\n'),
      ('1. one\n2. two\n', 1, '1. one\n   2. two\n'),
      ('> - one\n> - two\n', 1, '> - one\n>   - two\n'),
    ]) {
      test('items after an item held in under it: "$text"', () {
        final document = read(text);
        final item = nth(document, 'li', index);
        final (next, marker) = listed(
          document,
          text.startsWith('1') ? 'ol' : 'ul',
          item,
        );
        expect(string(next.items), written);
        expect(
          said(marked(next, marker), ''),
          text.startsWith('1') ? 'ol' : 'ul',
        );
      });
    }

    test('a list made over one item holds it, as a fresh read has it', () {
      final document = read('- one\n- two\n');
      final item = element(document, 'li', 1);
      final (next, marker) = listed(document, 'ul', marked(document, item));
      expect(
        [
          for (final one in structure(next))
            '${one.depth}:${said(one.element, '')}',
        ],
        ['0:ul', '1:li', '2:ul', '3:li'],
      );
      expect(said(marked(next, item), ''), 'li', reason: 'the item kept');
      expect(said(marked(next, marker), ''), 'ul');
    });

    for (final (text, written) in [
      ('- one\n  - two\n', '- one\n- two\n'),
      ('- one\n  - two\n    - three\n', '- one\n- two\n  - three\n'),
      ('> - one\n>   - two\n', '> - one\n> - two\n'),
    ]) {
      test('a list inside an item taken out a level: "$text"', () {
        final document = read(text);
        final next = edited(
          markdown,
          document,
          Edit(3, Unmark(element(document, 'ul', 1))),
        );
        expect(string(next.items), written);
      });
    }

    for (final (text, index, written) in [
      ('- one\n- two\n- three\n', 1, '- one\n\ntwo\n\n- three\n'),
      ('- one\n  - two\n', 0, 'one\n\n- two\n'),
      ('> - one\n> - two\n', 1, '> - one\n>\n> two\n'),
    ]) {
      test('an item freed, blank lines parting it: "$text"', () {
        final document = read(text);
        final next = edited(
          markdown,
          document,
          Edit(3, Unmark(element(document, 'li', index))),
        );
        expect(string(next.items), written);
      });
    }
  });

  group('Layer 3: unwrapping, renaming and deleting', () {
    for (final (text, name, written) in [
      ('a *b* c\n', 'em', 'a b c\n'),
      ('a [b](/u) c\n', 'a', 'a b c\n'),
      ('## a ##\n', 'h2', 'a\n'),
      ('a\n---\n', 'h2', 'a\n\n'),
      ('> a\n> b\n', 'blockquote', 'a\nb\n'),
      ('- a\n- b\n', 'ul', 'a\n\nb\n'),
      ('- a\n', 'ul', 'a\n'),
      ('```js\na\n```\n', 'pre', 'a\n\n'),
      ('- a\n\n  > b\n', 'blockquote', '- a\n\n  b\n'),
    ]) {
      test('$name unwrapped from "$text"', () {
        final document = read(text);
        final next = edited(
          markdown,
          document,
          Edit(3, Unmark(element(document, name))),
        );
        expect(string(next.items), written);
      });
    }

    test('a paragraph has no representation of its own to take away', () {
      final document = read('a\n');
      refused(
        document,
        Edit(3, Unmark(element(document, 'p'))),
        'representation',
      );
    });

    for (final (text, from, to, written) in [
      ('a *b* c\n', 'em', 'strong', 'a **b** c\n'),
      ('# a\n', 'h1', 'h3', '### a\n'),
      ('- a\n- b\n', 'ul', 'ol', '1. a\n1. b\n'),
    ]) {
      test('$from renamed $to, keeping its marker', () {
        final document = read(text);
        final marker = element(document, from);
        final next = edited(
          markdown,
          document,
          Edit(3, Update(marker, {'': Str(Text.of(to))})),
        );
        expect(string(next.items), written);
        expect(said(marked(next, marker), ''), to);
      });
    }

    test('a rename to another kind rewrites the element around its words', () {
      final document = read('a\n');
      final marker = element(document, 'p');
      final next = edited(
        markdown,
        document,
        Edit(3, Update(marker, {'': Str(Text.of('h1'))})),
      );
      expect(string(next.items), '# a\n');
      expect(said(marked(next, marker), ''), 'h1');
    });

    test('elements are deleted with what they hold', () {
      final document = read('a *b* c\n\nd\n');
      final index = document
          .layer(3)
          .items
          .toList()
          .indexWhere((range) => said(range as ARange, '') == 'em');
      final next = edited(
        markdown,
        document,
        Edit(3, Delete(value(Range.create(index, 1)))),
      );
      expect(string(next.items), 'a  c\n\nd\n');
    });
  });

  group('At random', () {
    for (final name in ['markwrite', 'ranges', 'htpasswd']) {
      test('structural edits of $name.md leave what a fresh read gives', () {
        structural(
          markdown,
          File('test/samples/$name.md').readAsStringSync(),
          proposed,
          seed: name.hashCode,
          edits: 150,
        );
      });
    }
  });
}

/// A random structural edit of [document], at layer 2 or 3.
Edit<int>? proposed(Layered<int> document, Random random) {
  final tokens = document.markers(2);
  final elements = document.markers(3);
  final length = document.items.length;
  const names = [
    'em', 'strong', 'code', 'a', 'h1', 'h3', //
    'blockquote', 'ul', 'ol', 'pre',
  ];
  final name = names[random.nextInt(names.length)];
  final said = {'': name, if (name == 'a') 'href': '/u'};
  switch (random.nextInt(7)) {
    case 0:
      return Edit(2, Mark(Open(random.nextInt(length + 1), name)));
    case 1 when name != 'a':
      return Edit(2, Mark(Close(random.nextInt(length + 1), name)));
    case 2 when tokens.isNotEmpty:
      final start = random.nextInt(tokens.length);
      return Edit(
        2,
        Delete(
          value(
            Range.create(
              start,
              1 + random.nextInt(min(3, tokens.length - start)),
            ),
          ),
        ),
      );
    case 3:
      final start = random.nextInt(tokens.length + 1);
      return Edit(
        3,
        Mark(
          value(
            ARange.create(
              start,
              random.nextInt(min(6, tokens.length - start + 1)),
              attributes: {
                for (final MapEntry(:key, :value) in said.entries)
                  key: Str(Text.of(value)),
              },
            ),
          ),
        ),
      );
    case 4 when elements.isNotEmpty:
      return Edit(3, Unmark(elements[random.nextInt(elements.length)].$1));
    case 5 when elements.isNotEmpty:
      return Edit(
        3,
        Update(elements[random.nextInt(elements.length)].$1, {
          for (final MapEntry(:key, :value) in said.entries)
            key: Str(Text.of(value)),
        }),
      );
    case 6 when elements.isNotEmpty:
      return Edit(
        3,
        Delete(value(Range.create(random.nextInt(elements.length), 1))),
      );
  }
  return null;
}
