import 'dart:io';
import 'dart:math';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// Structural edits: each is carried out as edits one layer down, and
/// leaves the layers a fresh read of the edited text gives.
void main() {
  const xml = XML();

  bool named(ARange range, String name) => said(range, '') == name;

  group('Layer 2: tokens', () {
    test('a start tag inserted in a run of text splits it', () {
      final document = edited(
        xml,
        decoded(xml, '<p>abcd</p>'),
        Edit(2, Mark(Open(5, 'em', {'class': 'x'}))),
      );
      expect(string(document.items), '<p>ab<em class="x">cd</p>');
    });

    test('an end tag and an empty tag at the edge of a token', () {
      var document = decoded(xml, '<p>ab</p>');
      document = edited(xml, document, Edit(2, Mark(Close(5, 'p'))));
      document = edited(xml, document, Edit(2, Mark(Empty(3, 'br'))));
      expect(string(document.items), '<p><br/>ab</p></p>');
    });

    test('a tag is not put inside another token', () {
      refused(
        decoded(xml, '<p>ab</p>'),
        Edit(2, Mark(Open(1, 'em'))),
        'inside',
      );
    });

    test('nor given a name XML cannot represent', () {
      refused(decoded(xml, '<p>ab</p>'), Edit(2, Mark(Open(4, 'a b'))), 'name');
      refused(
        decoded(xml, '<p>ab</p>'),
        Edit(2, Mark(Open(4, 'a', {'x y': '1'}))),
        'name',
      );
    });

    test('text and markup are commented out, and back in', () {
      var document = decoded(xml, '<p>ab<b>c</b>d</p>');
      document = edited(
        xml,
        document,
        Edit(2, Mark(Comment(value(Range.create(4, 9))))),
      );
      expect(string(document.items), '<p>a<!--b<b>c</b>-->d</p>');
      expect(preorder(document), ['0:#document', '1:p']);
      document = edited(
        xml,
        document,
        Edit(
          2,
          Unmark(marker(document, 2, (range) => named(range, '#comment'))),
        ),
      );
      expect(string(document.items), '<p>ab<b>c</b>d</p>');
      expect(tokens(document)[1], ('#text', 'ab'));
    });

    test('a comment is not made of what a comment cannot hold', () {
      refused(
        decoded(xml, '<p>a--b</p>'),
        Edit(2, Mark(Comment(value(Range.create(3, 4))))),
        '--',
      );
    });

    test('only a comment is unmarked at layer 2', () {
      final document = decoded(xml, '<p>a</p>');
      refused(
        document,
        Edit(2, Unmark(marker(document, 2, (range) => named(range, 'p')))),
        'comment',
      );
    });

    test('a tag is renamed in place, keeping its marker', () {
      final document = decoded(xml, '<p a="1">x</p>');
      final tag = marker(document, 2, (range) => range.start == 0);
      final next = edited(
        xml,
        document,
        Edit(2, Update(tag, {'': Str(Text.of('q')), 'a': Str(Text.of('1'))})),
      );
      expect(string(next.items), '<q a="1">x</p>');
      expect(said(next.layer(2).items.first as ARange, ''), 'q');
      expect(next.markers(2).first.$1, tag);
    });

    test('and given new attributes, written out afresh', () {
      final document = decoded(xml, "<p  a='1'>x</p>");
      final next = edited(
        xml,
        document,
        Edit(
          2,
          Update(marker(document, 2, (range) => range.start == 0), {
            '': Str(Text.of('p')),
            'b': Str(Text.of('2 > 1 & "so"')),
          }),
        ),
      );
      expect(string(next.items), '<p b="2 &gt; 1 &amp; &quot;so&quot;">x</p>');
    });

    test('a run of text is not renamed', () {
      final document = decoded(xml, '<p>a</p>');
      refused(
        document,
        Edit(
          2,
          Update(marker(document, 2, (range) => range.start == 3), {
            '': Str(Text.of('b')),
          }),
        ),
        'not a tag',
      );
    });

    test('deleting tokens joins the runs of text either side', () {
      final document = edited(
        xml,
        decoded(xml, '<p>a<b>b</b>c</p>'),
        Edit(2, Delete(value(Range.create(2, 1)))),
      );
      expect(string(document.items), '<p>ab</b>c</p>');
      expect(tokens(document)[1], ('#text', 'ab'));
    });

    test('and a reference written across the join is read as one', () {
      final document = edited(
        xml,
        decoded(xml, '<p>&am<b/>p;</p>'),
        Edit(2, Delete(value(Range.create(2, 1)))),
      );
      expect(tokens(document)[1], ('#entity', '&amp;'));
    });
  });

  group('Layer 3: elements', () {
    test('tokens holding whole elements are wrapped in a new one', () {
      final document = edited(
        xml,
        decoded(xml, '<p>a<b>c</b>d</p>'),
        Edit(
          3,
          Mark(
            value(
              ARange.create(
                1,
                5,
                attributes: {'': Str(Text.of('em')), 'id': Str(Text.of('x'))},
              ),
            ),
          ),
        ),
      );
      expect(string(document.items), '<p><em id="x">a<b>c</b>d</em></p>');
      expect(preorder(document), ['0:#document', '1:p', '2:em', '3:b']);
    });

    test('half an element is not wrapped', () {
      refused(
        decoded(xml, '<p>a<b>c</b>d</p>'),
        Edit(
          3,
          Mark(
            value(ARange.create(1, 2, attributes: {'': Str(Text.of('em'))})),
          ),
        ),
        'whole elements',
      );
    });

    test('an element is unwrapped, keeping what it holds', () {
      final document = decoded(xml, '<p>a<b>c</b>d</p>');
      final next = edited(
        xml,
        document,
        Edit(3, Unmark(marker(document, 3, (range) => named(range, 'b')))),
      );
      expect(string(next.items), '<p>acd</p>');
      expect(tokens(next)[1], ('#text', 'acd'));
    });

    test('but not when what it holds would pair differently without it', () {
      final document = decoded(xml, '<p><b>c</i></b></p>');
      refused(
        document,
        Edit(3, Unmark(marker(document, 3, (range) => named(range, 'b')))),
        'pair differently',
      );
    });

    test('an empty element has nothing to keep, so is deleted instead', () {
      final document = decoded(xml, '<p><br/></p>');
      refused(
        document,
        Edit(3, Unmark(marker(document, 3, (range) => named(range, 'br')))),
        'delete',
      );
    });

    test('an element is renamed at both its tags', () {
      final document = decoded(xml, '<p><b a="1">c</b></p>');
      final next = edited(
        xml,
        document,
        Edit(
          3,
          Update(marker(document, 3, (range) => named(range, 'b')), {
            '': Str(Text.of('strong')),
            'a': Str(Text.of('1')),
          }),
        ),
      );
      expect(string(next.items), '<p><strong a="1">c</strong></p>');
    });

    test('elements are deleted with what they hold', () {
      final document = decoded(xml, '<p>a<b>c</b><i/>d</p>');
      final next = edited(
        xml,
        document,
        Edit(3, Delete(value(Range.create(1, 2)))),
      );
      expect(string(next.items), '<p>ad</p>');
      expect(tokens(next)[1], ('#text', 'ad'));
    });
  });

  group('At random', () {
    for (final name in ['markwrite', 'ranges', 'htpasswd']) {
      test('structural edits of $name.xml leave what a fresh read gives', () {
        structural(
          xml,
          File('test/samples/$name.xml').readAsStringSync(),
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
      final (marker, _) = tokens[random.nextInt(tokens.length)];
      return Edit(2, Update(marker, {'': Str(Text.of(name))}));
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
    case 3 || 4 || 6 || 7 || 8:
      return null;
  }
  return null;
}
