import 'dart:io';
import 'dart:math';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// LMNL's structural edits: each carried out as edits one layer down, and
/// none refused on account of overlap, since overlap is what LMNL is for.
void main() {
  const lmnl = LMNL();

  bool named(ARange range, String name) => said(range, '') == name;

  Edit<int> wrap(int start, int length, String name) => Edit(
    3,
    Mark(
      value(ARange.create(start, length, attributes: {'': Str(Text.of(name))})),
    ),
  );

  group('Layer 2: tokens', () {
    test('a start tag inserted in a run of text splits it', () {
      final document = edited(
        lmnl,
        decoded(lmnl, '[p}abcd{p]'),
        Edit(2, Mark(Open(5, 'em', {'n': '1'}))),
      );
      expect(string(document.items), '[p}ab[em [n}1{n]}cd{p]');
    });

    test('an end tag at the edge of a token', () {
      final document = edited(
        lmnl,
        decoded(lmnl, '[p}ab{p]'),
        Edit(2, Mark(Close(3, 'q'))),
      );
      expect(string(document.items), '[p}{q]ab{p]');
    });

    test('LMNL writes no empty element', () {
      refused(decoded(lmnl, 'ab'), Edit(2, Mark(Empty(1, 'br'))), 'empty');
    });

    test('a tag is not put inside another token', () {
      refused(
        decoded(lmnl, '[p}ab{p]'),
        Edit(2, Mark(Open(1, 'em'))),
        'inside',
      );
    });

    test('nor given a name LMNL cannot represent', () {
      for (final name in ['a b', '#x', 'a]', '']) {
        refused(decoded(lmnl, 'ab'), Edit(2, Mark(Open(1, name))), 'name');
      }
    });

    test('text and markup are commented out, and back in', () {
      var document = decoded(lmnl, '[p}ab[b}c{b]d{p]');
      document = edited(
        lmnl,
        document,
        Edit(2, Mark(Comment(value(Range.create(4, 8))))),
      );
      expect(string(document.items), '[p}a[!--b[b}c{b]--]d{p]');
      expect(preorder(document), ['0:#document', '1:p']);
      document = edited(
        lmnl,
        document,
        Edit(
          2,
          Unmark(marker(document, 2, (range) => named(range, '#comment'))),
        ),
      );
      expect(string(document.items), '[p}ab[b}c{b]d{p]');
      expect(tokens(document)[1], ('#text', 'ab'));
    });

    test('a comment is not made of what would end it', () {
      refused(
        decoded(lmnl, 'a--]b'),
        Edit(2, Mark(Comment(value(Range.create(0, 5))))),
        '--]',
      );
    });

    test('a tag is renamed in place, keeping its marker', () {
      final document = decoded(lmnl, '[p [n}1{n]}x{p]');
      final tag = marker(document, 2, (range) => range.start == 0);
      final next = edited(
        lmnl,
        document,
        Edit(2, Update(tag, {'': Str(Text.of('q')), 'n': Str(Text.of('1'))})),
      );
      expect(string(next.items), '[q [n}1{n]}x{p]');
      expect(next.markers(2).first.$1, tag);
    });

    test('and given new annotations, written out afresh', () {
      final document = decoded(lmnl, '[p [n}1{n]}x{p]');
      final next = edited(
        lmnl,
        document,
        Edit(
          2,
          Update(marker(document, 2, (range) => range.start == 0), {
            '': Str(Text.of('p')),
            'k': Str(Text.of('v')),
          }),
        ),
      );
      expect(string(next.items), '[p [k}v{k]}x{p]');
    });

    test('deleting an end tag pairs its start tag afresh, though another of '
        'its name stands where it ended', () {
      // Found at random. The outer b collapsed onto the inner b's end tag,
      // which looked like an end tag of its own.
      final document = edited(
        lmnl,
        decoded(lmnl, '[b}x[b}y{b]z{b]w'),
        Edit(2, Delete(value(Range.create(5, 2)))),
      );
      expect(string(document.items), '[b}x[b}y{b]w');
      expect(document.layer(3).length, 1);
    });

    test('deleting tokens joins the runs of text either side', () {
      final document = edited(
        lmnl,
        decoded(lmnl, '[p}a[b}b{b]c{p]'),
        Edit(2, Delete(value(Range.create(2, 1)))),
      );
      expect(string(document.items), '[p}ab{b]c{p]');
      expect(tokens(document)[1], ('#text', 'ab'));
    });
  });

  group('Layer 3: elements', () {
    test('tokens are wrapped even where the new element crosses another', () {
      final document = edited(
        lmnl,
        decoded(lmnl, '[a}one two{a] three'),
        wrap(1, 3, 'b'),
      );
      expect(string(document.items), '[a}[b}one two{a] three{b]');
      final ranges = document.layer(3).items.cast<ARange>().toList();
      expect(ranges[0].overlaps(ranges[1]), isTrue);
    });

    test('but not over a tag of the same name, which would pair with it', () {
      refused(decoded(lmnl, '[b}x{b]y'), wrap(0, 4, 'b'), 'pair');
    });

    test('an element is unwrapped, keeping what it holds', () {
      final document = decoded(lmnl, '[p}a[b}c{b]d{p]');
      final next = edited(
        lmnl,
        document,
        Edit(3, Unmark(marker(document, 3, (range) => named(range, 'b')))),
      );
      expect(string(next.items), '[p}acd{p]');
    });

    test('an element is renamed at both its tags', () {
      final document = decoded(lmnl, '[p}[b [n}1{n]}c{b]{p]');
      final next = edited(
        lmnl,
        document,
        Edit(
          3,
          Update(marker(document, 3, (range) => named(range, 'b')), {
            '': Str(Text.of('i')),
            'n': Str(Text.of('1')),
          }),
        ),
      );
      expect(string(next.items), '[p}[i [n}1{n]}c{i]{p]');
    });

    test('but not to a name a tag inside it already has', () {
      final document = decoded(lmnl, '[b}x[i}y{b]');
      refused(
        document,
        Edit(
          3,
          Update(marker(document, 3, (range) => named(range, 'b')), {
            '': Str(Text.of('i')),
          }),
        ),
        'pair',
      );
    });

    test('elements are deleted with what they hold', () {
      final document = edited(
        lmnl,
        decoded(lmnl, '[p}a[b}c{b]d{p]'),
        Edit(3, Delete(value(Range.create(1, 1)))),
      );
      expect(string(document.items), '[p}ad{p]');
    });

    test('but not when that cuts a crossing element from one of its tags', () {
      final document = decoded(lmnl, '[a}x[b}y{a]z{b]');
      refused(document, Edit(3, Delete(value(Range.create(0, 1)))), 'cuts');
    });
  });

  group('At random', () {
    for (final name in ['markwrite', 'ranges', 'htpasswd']) {
      test('structural edits of $name.lmnl leave what a fresh read gives', () {
        structural(
          lmnl,
          File('test/samples/$name.lmnl').readAsStringSync(),
          proposed,
          seed: name.hashCode,
          edits: 300,
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
  final names = ['em', 'b', 'p', 'note'];
  final name = names[random.nextInt(names.length)];
  switch (random.nextInt(9)) {
    case 0:
      return Edit(2, Mark(Open(random.nextInt(length + 1), name)));
    case 1:
      return Edit(2, Mark(Close(random.nextInt(length + 1), name)));
    case 2:
      final start = random.nextInt(length + 1);
      return Edit(
        2,
        Mark(
          Comment(
            value(Range.create(start, random.nextInt(length - start + 1))),
          ),
        ),
      );
    case 3 when tokens.isNotEmpty:
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
    case 4 when tokens.isNotEmpty:
      return Edit(
        2,
        Update(tokens[random.nextInt(tokens.length)].$1, {
          '': Str(Text.of(name)),
        }),
      );
    case 5:
      final start = random.nextInt(tokens.length + 1);
      return Edit(
        3,
        Mark(
          value(
            ARange.create(
              start,
              random.nextInt(tokens.length - start + 1),
              attributes: {'': Str(Text.of(name))},
            ),
          ),
        ),
      );
    case 6 when elements.isNotEmpty:
      return Edit(3, Unmark(elements[random.nextInt(elements.length)].$1));
    case 7 when elements.isNotEmpty:
      return Edit(
        3,
        Update(elements[random.nextInt(elements.length)].$1, {
          '': Str(Text.of(name)),
        }),
      );
    case 8 when elements.isNotEmpty:
      return Edit(
        3,
        Delete(value(Range.create(random.nextInt(elements.length), 1))),
      );
  }
  return null;
}
