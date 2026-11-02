import 'dart:io';
import 'dart:math';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// roff's structural edits: each is the text it writes or takes away, read
/// again, as Markdown's are, so every one leaves the layers a fresh read
/// gives.
void main() {
  const man = Man();

  Layered<int> read(String text) => decoded(man, text);

  group('Layer 2: markup', () {
    test('a face is written an escape at a time', () {
      var document = read('.PP\na b c\n');
      document = edited(man, document, Edit(2, Mark(Close(7, 'strong'))));
      document = edited(man, document, Edit(2, Mark(Open(6, 'strong'))));
      expect(string(document.items), '.PP\na \\fBb\\fP c\n');
    });

    test('a request is written on a line of its own', () {
      final document = edited(
        man,
        read('.PP\na b\n'),
        Edit(2, Mark(Open(6, 'p'))),
      );
      expect(string(document.items), '.PP\na \n.PP\nb\n');
      expect(
        string(edited(man, read('a\n'), Edit(2, Mark(Open(0, 'p')))).items),
        '.PP\na\n',
      );
    });

    test('deleting tokens takes their markup away', () {
      final document = read('.PP\na \\fBb\\fP c\n');
      final next = edited(
        man,
        document,
        Edit(2, Delete(value(Range.create(at(document, '\\fB'), 1)))),
      );
      expect(string(next.items), '.PP\na b\\fP c\n');
    });

    test('a name the package has no representation for is refused', () {
      refused(
        read('a\n'),
        Edit(2, Mark(Open(0, 'span'))),
        'no representation for',
      );
    });

    test('nothing is unmarked or renamed at layer 2', () {
      final document = read('.PP\na\n');
      final token = document.markers(2).first.$1;
      refused(document, Edit(2, Unmark(token)), 'layer 3');
      refused(
        document,
        Edit(2, Update(token, {'': Str(Text.of('h1'))})),
        'layer 3',
      );
    });
  });

  group('Layer 3: wrapping', () {
    for (final (name, written) in [
      ('strong', '.PP\n\\fBa b\\fP\n'),
      ('em', '.PP\n\\fIa b\\fP\n'),
      ('code', '.PP\n\\fCa b\\fP\n'),
    ]) {
      test('words in $name', () {
        final document = read('.PP\na b\n');
        final marker = Marker();
        final next = edited(
          man,
          document,
          Edit(3, Mark.of(marker, over(at(document, 'a b'), 1, {'': name}))),
        );
        expect(string(next.items), written);
        expect(said(marked(next, marker), ''), name);
      });
    }

    for (final (name, said, written) in [
      ('h1', <String, String>{}, '.SH a\n'),
      ('div', <String, String>{}, '.RS\na\n.RE\n'),
      ('pre', <String, String>{}, '.nf\na\n.fi\n'),
      ('a', {'href': '/u'}, '.UR /u\na\n.UE\n'),
    ]) {
      test('a line in $name', () {
        final marker = Marker();
        final next = edited(
          man,
          read('a\n'),
          Edit(3, Mark.of(marker, over(0, 1, {'': name, ...said}))),
        );
        expect(string(next.items), written);
        expect(marked(next, marker).get(''), Str(Text.of(name)));
      });
    }

    test('in ms and me, as each package represents a heading', () {
      expect(
        string(
          edited(
            const Ms(),
            decoded(const Ms(), 'a\n'),
            Edit(3, Mark(over(0, 1, {'': 'h2'}))),
          ).items,
        ),
        '.NH 2\na\n',
      );
      expect(
        string(
          edited(
            const Me(),
            decoded(const Me(), 'a\n'),
            Edit(3, Mark(over(0, 1, {'': 'h1'}))),
          ).items,
        ),
        '.sh 1 a\n',
      );
    });

    test('a name the package has no representation for is refused', () {
      refused(
        read('a\n'),
        Edit(3, Mark(over(0, 1, {'': 'blockquote'}))),
        'no representation for',
      );
    });
  });

  group('Layer 3: unwrapping, renaming and deleting', () {
    for (final (text, name, written) in [
      ('.PP\na \\fBb\\fP c\n', 'strong', '.PP\na b c\n'),
      ('.RS\na\n.RE\n', 'div', 'a\n'),
      ('.SH NAME\n', 'h1', 'NAME\n'),
      ('.nf\ncode\n.fi\n', 'pre', 'code\n'),
    ]) {
      test('$name unwrapped from "$text"', () {
        final document = read(text);
        final next = edited(
          man,
          document,
          Edit(3, Unmark(element(document, name))),
        );
        expect(string(next.items), written);
      });
    }

    test(
      'a paragraph no request opened has no representation to take away',
      () {
        final document = read('a\n');
        refused(
          document,
          Edit(3, Unmark(element(document, 'p'))),
          'representation',
        );
      },
    );

    for (final (text, from, to, written) in [
      ('.PP\na \\fBb\\fP c\n', 'strong', 'em', '.PP\na \\fIb\\fP c\n'),
      ('.SH A\n', 'h1', 'h2', '.SS A\n'),
    ]) {
      test('$from renamed $to, keeping its marker', () {
        final document = read(text);
        final marker = element(document, from);
        final next = edited(
          man,
          document,
          Edit(3, Update(marker, {'': Str(Text.of(to))})),
        );
        expect(string(next.items), written);
        expect(said(marked(next, marker), ''), to);
      });
    }

    test('an element of no tokens is renamed where it stands', () {
      // A face \fP brings back at the end of a line closes where it opens.
      final document = read('.PP\n\\fBa\\fIb\\fP\n.SH X\n');
      final empty = document
          .markers(3)
          .firstWhere((pair) => pair.$2.length == 0);
      final change = document.apply(
        Edit(3, Update(empty.$1, {'': Str(Text.of('strong'))})),
      );
      if (change case Success(:final value)) {
        expect(
          layers(value.document),
          layers(read(string(value.document.items))),
        );
      } else {
        expect((change as Failure<Object?>).message, isNot(contains('threw')));
      }
    });

    test('elements are deleted with what they hold', () {
      final document = read('.PP\na \\fBb\\fP c\n.PP\nd\n');
      final index = document
          .layer(3)
          .items
          .toList()
          .indexWhere((range) => said(range as ARange, '') == 'strong');
      final next = edited(
        man,
        document,
        Edit(3, Delete(value(Range.create(index, 1)))),
      );
      expect(string(next.items), '.PP\na  c\n.PP\nd\n');
    });
  });

  group('At random', () {
    for (final (name, syntax) in [
      ('htpasswd.1', man),
      ('markwrite.1', man),
      ('ranges.ms', const Ms()),
    ]) {
      test('structural edits of $name leave what a fresh read gives', () {
        structural(
          syntax,
          File('test/samples/$name').readAsStringSync(),
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
  const names = ['strong', 'em', 'code', 'p', 'h1', 'h2', 'div', 'pre', 'li'];
  final name = names[random.nextInt(names.length)];
  final said = {'': Str(Text.of(name))};
  switch (random.nextInt(7)) {
    case 0:
      return Edit(2, Mark(Open(random.nextInt(length + 1), name)));
    case 1:
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
              attributes: said,
            ),
          ),
        ),
      );
    case 4 when elements.isNotEmpty:
      return Edit(3, Unmark(elements[random.nextInt(elements.length)].$1));
    case 5 when elements.isNotEmpty:
      return Edit(
        3,
        Update(elements[random.nextInt(elements.length)].$1, said),
      );
    case 6 when elements.isNotEmpty:
      return Edit(
        3,
        Delete(value(Range.create(random.nextInt(elements.length), 1))),
      );
  }
  return null;
}
