import 'dart:io';
import 'dart:math';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:libara_formats/src/html/html.dart' show nested;
import 'package:test/test.dart';

import 'harness.dart';

/// Structural edits: each is carried out as edits one layer down, and
/// leaves the layers a fresh read of the edited text gives.
void main() {
  const html = HTML();

  bool named(ARange range, String name) => said(range, '') == name;

  /// The tree, in pre-order, each element with its depth.
  List<String> built(Layered<int> document) => [
    '0:#document',
    for (final (element, depth, _) in nested(document))
      '${depth + 1}:${element.get('')}',
  ];

  group('Layer 2: tokens', () {
    test('a start tag inserted in a run of text splits it', () {
      final document = edited(
        html,
        decoded(html, '<p>abcd</p>'),
        Edit(2, Mark(Open(5, 'em', {'class': 'x'}))),
      );
      expect(string(document.items), '<p>ab<em class="x">cd</p>');
    });

    test('an end tag and a void tag at the edge of a token', () {
      var document = decoded(html, '<p>ab</p>');
      document = edited(html, document, Edit(2, Mark(Close(5, 'p'))));
      document = edited(html, document, Edit(2, Mark(Empty(3, 'br'))));
      expect(string(document.items), '<p><br>ab</p></p>');
    });

    test('only a void element is written empty', () {
      refused(
        decoded(html, '<p>ab</p>'),
        Edit(2, Mark(Empty(3, 'div'))),
        'void',
      );
    });

    test('a tag is not put inside another token', () {
      refused(
        decoded(html, '<p>ab</p>'),
        Edit(2, Mark(Open(1, 'em'))),
        'inside',
      );
    });

    test('nor given a name HTML does not read back as itself', () {
      for (final tag in [
        Open(4, 'a b'),
        Open(4, 'EM'),
        Open(4, 'a', {'x y': '1'}),
      ]) {
        refused(decoded(html, '<p>ab</p>'), Edit(2, Mark(tag)), 'reads back');
      }
    });

    test('nor one whose element reads what follows as text', () {
      refused(
        decoded(html, '<p>ab</p>'),
        Edit(2, Mark(Open(3, 'script'))),
        'as text',
      );
    });

    test('text and markup are commented out, and back in', () {
      var document = decoded(html, '<p>ab<b>c</b>d</p>');
      document = edited(
        html,
        document,
        Edit(2, Mark(Comment(value(Range.create(4, 9))))),
      );
      expect(string(document.items), '<p>a<!--b<b>c</b>-->d</p>');
      expect(built(document), [
        '0:#document',
        '1:html',
        '2:head',
        '2:body',
        '3:p',
      ]);
      document = edited(
        html,
        document,
        Edit(
          2,
          Unmark(marker(document, 2, (range) => named(range, '#comment'))),
        ),
      );
      expect(string(document.items), '<p>ab<b>c</b>d</p>');
      expect(tokens(document)[1], ('#text', 'ab'));
    });

    test('a comment is not made of what would end it early', () {
      refused(
        decoded(html, '<p>a-->b</p>'),
        Edit(2, Mark(Comment(value(Range.create(3, 5))))),
        'one comment',
      );
    });

    test('only a comment is unmarked at layer 2', () {
      final document = decoded(html, '<p>a</p>');
      refused(
        document,
        Edit(2, Unmark(marker(document, 2, (range) => named(range, 'p')))),
        'comment',
      );
    });

    test('a tag is renamed in place, keeping its marker', () {
      final document = decoded(html, '<P a="1">x</p>');
      final tag = marker(document, 2, (range) => range.start == 0);
      final next = edited(
        html,
        document,
        Edit(2, Update(tag, {'': Str(Text.of('q')), 'a': Str(Text.of('1'))})),
      );
      expect(string(next.items), '<q a="1">x</p>');
      expect(said(next.layer(2).items.first as ARange, ''), 'q');
      expect(next.markers(2).first.$1, tag);
    });

    test('and given new attributes, written out afresh', () {
      final document = decoded(html, "<p  a='1'>x</p>");
      final next = edited(
        html,
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

    test('an end tag says nothing but its name', () {
      final document = decoded(html, '<p>x</p>');
      refused(
        document,
        Edit(
          2,
          Update(marker(document, 2, (range) => range.start == 4), {
            '': Str(Text.of('p')),
            'a': Str(Text.of('1')),
          }),
        ),
        'nothing but its name',
      );
    });

    test('a tag is not renamed to one that reads what follows as text', () {
      final document = decoded(html, '<p>x</p>');
      refused(
        document,
        Edit(
          2,
          Update(marker(document, 2, (range) => range.start == 0), {
            '': Str(Text.of('title')),
          }),
        ),
        'as text',
      );
    });

    test('nor is a tag that holds its element\'s text', () {
      final document = decoded(html, '<title>x</title>');
      refused(
        document,
        Edit(
          2,
          Update(marker(document, 2, (range) => range.start == 0), {
            '': Str(Text.of('p')),
          }),
        ),
        'as text',
      );
    });

    test('a run of text is not renamed', () {
      final document = decoded(html, '<p>a</p>');
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
        html,
        decoded(html, '<p>a<b>b</b>c</p>'),
        Edit(2, Delete(value(Range.create(2, 1)))),
      );
      expect(string(document.items), '<p>ab</b>c</p>');
      expect(tokens(document)[1], ('#text', 'ab'));
    });

    test('but not into a tag whose element reads on as text', () {
      refused(
        decoded(html, '<p><<b>script>x</p><p>y</p>'),
        Edit(2, Delete(value(Range.create(2, 1)))),
        'read on',
      );
    });

    test('and a reference written across the join is read as one', () {
      final document = edited(
        html,
        decoded(html, '<p>&am<b>p;</p>'),
        Edit(2, Delete(value(Range.create(2, 1)))),
      );
      expect(tokens(document)[1], ('#entity', '&amp;'));
    });
  });

  group('Layer 3: elements', () {
    test('tokens holding whole elements are wrapped in a new one', () {
      final document = edited(
        html,
        decoded(html, '<p>a<b>c</b>d</p>'),
        Edit(3, Mark(over(1, 5, {'': 'em', 'id': 'x'}))),
      );
      expect(string(document.items), '<p><em id="x">a<b>c</b>d</em></p>');
      expect(built(document), [
        '0:#document',
        '1:html',
        '2:head',
        '2:body',
        '3:p',
        '4:em',
        '5:b',
      ]);
    });

    test('and at the edge of an element with no tags of its own', () {
      // The body HTML implies takes in the tags put in at its end, as a
      // fresh read does.
      final document = edited(
        html,
        decoded(html, '<h1>x</h1><p>a</p><p>b</p>'),
        Edit(3, Mark(over(3, 6, {'': 'ul'}))),
      );
      expect(string(document.items), '<h1>x</h1><ul><p>a</p><p>b</p></ul>');
      expect(built(document), [
        '0:#document',
        '1:html',
        '2:head',
        '2:body',
        '3:h1',
        '3:ul',
        '4:p',
        '4:p',
      ]);
    });

    test('and at the start of one', () {
      final document = edited(
        html,
        decoded(html, '<p>a</p><p>b</p><h1>x</h1>'),
        Edit(3, Mark(over(0, 6, {'': 'ul'}))),
      );
      expect(string(document.items), '<ul><p>a</p><p>b</p></ul><h1>x</h1>');
    });

    test('half an element is not wrapped', () {
      refused(
        decoded(html, '<p>a<b>c</b>d</p>'),
        Edit(3, Mark(over(1, 2, {'': 'em'}))),
        'other elements',
      );
    });

    test('nor is what the new element would close', () {
      refused(
        decoded(html, '<p>a<b>c</b>d</p>'),
        Edit(3, Mark(over(1, 1, {'': 'p'}))),
        'other elements',
      );
    });

    test('an element is unwrapped, keeping what it holds', () {
      final document = decoded(html, '<p>a<b>c</b>d</p>');
      final next = edited(
        html,
        document,
        Edit(3, Unmark(marker(document, 3, (range) => named(range, 'b')))),
      );
      expect(string(next.items), '<p>acd</p>');
      expect(tokens(next)[1], ('#text', 'acd'));
    });

    test('but not when what it holds would be built differently', () {
      final document = decoded(html, '<p><b>c<i>d</b>e</i></p>');
      refused(
        document,
        Edit(3, Unmark(marker(document, 3, (range) => named(range, 'b')))),
        'other elements',
      );
    });

    test('an element with no tags of its own is not unwrapped', () {
      final document = decoded(html, '<p>a</p>');
      refused(
        document,
        Edit(3, Unmark(marker(document, 3, (range) => named(range, 'body')))),
        'tags of its own',
      );
    });

    test('an element is renamed at both its tags', () {
      final document = decoded(html, '<p><b a="1">c</b></p>');
      final next = edited(
        html,
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

    test('but not to a name that builds the tree differently', () {
      final document = decoded(html, '<p>x<b>c</b></p>');
      refused(
        document,
        Edit(
          3,
          Update(marker(document, 3, (range) => named(range, 'b')), {
            '': Str(Text.of('p')),
          }),
        ),
        'other elements',
      );
    });

    test('nor where a clone made from it would go, though one alike stays', () {
      // The em reopened in the second paragraph spans what the em inside
      // it does, so two elements alike are carried and one is built.
      final document = decoded(html, '<p><em>a</p><p><em>b</em></p>');
      refused(
        document,
        Edit(3, Unmark(marker(document, 3, (range) => range.start == 1))),
        'other elements',
      );
    });

    test('elements are deleted with what they hold', () {
      final document = decoded(html, '<p>a<b>c</b><i></i>d</p>');
      final at = document
          .layer(3)
          .items
          .toList()
          .indexWhere((range) => named(range as ARange, 'b'));
      final next = edited(
        html,
        document,
        Edit(3, Delete(value(Range.create(at, 2)))),
      );
      expect(string(next.items), '<p>ad</p>');
      expect(tokens(next)[1], ('#text', 'ad'));
    });
  });

  group('At random', () {
    for (final name in ['markwrite', 'ranges', 'htpasswd']) {
      test('structural edits of $name.html leave what a fresh read gives', () {
        structural(
          html,
          File('test/samples/$name.html').readAsStringSync(),
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
  final names = ['em', 'b', 'p', 'div', 'li'];
  final name = names[random.nextInt(names.length)];
  switch (random.nextInt(10)) {
    case 0:
      return Edit(2, Mark(Open(random.nextInt(length + 1), name)));
    case 1:
      return Edit(2, Mark(Close(random.nextInt(length + 1), name)));
    case 2:
      return Edit(2, Mark(Empty(random.nextInt(length + 1), 'br')));
    case 3:
      final start = random.nextInt(length + 1);
      return Edit(
        2,
        Mark(
          Comment(
            value(Range.create(start, random.nextInt(length - start + 1))),
          ),
        ),
      );
    case 4 when tokens.isNotEmpty:
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
    case 5 when tokens.isNotEmpty:
      final (marker, _) = tokens[random.nextInt(tokens.length)];
      return Edit(2, Update(marker, {'': Str(Text.of(name))}));
    case 6:
      final start = random.nextInt(tokens.length + 1);
      return Edit(
        3,
        Mark(
          value(
            ARange.create(
              start,
              random.nextInt(min(8, tokens.length - start + 1)),
              attributes: {'': Str(Text.of(name))},
            ),
          ),
        ),
      );
    case 7 when elements.isNotEmpty:
      return Edit(3, Unmark(elements[random.nextInt(elements.length)].$1));
    case 8 when elements.isNotEmpty:
      return Edit(
        3,
        Update(elements[random.nextInt(elements.length)].$1, {
          '': Str(Text.of(name)),
        }),
      );
    case 9 when elements.isNotEmpty:
      return Edit(
        3,
        Delete(value(Range.create(random.nextInt(elements.length), 1))),
      );
    case 4 || 5 || 7 || 8 || 9:
      return null;
  }
  return null;
}
