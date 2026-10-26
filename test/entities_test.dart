import 'package:libara_formats/src/entities.dart';
import 'package:test/test.dart';

/// Ported from markwrite's `entities_test`: the parts about what a
/// reference stands for. What a syntax makes of one is in its own tests.
void main() {
  group('What a reference stands for', () {
    test('the five predefined ones', () {
      expect(
        [
          for (final name in ['amp', 'lt', 'gt', 'quot', 'apos']) entity(name),
        ],
        ['&', '<', '>', '"', "'"],
      );
    });

    test('a numbered reference in either base', () {
      expect(entity('#169'), '©');
      expect(entity('#xA9'), '©');
      expect(entity('#XA9'), '©');
    });

    test('a value may be more than one character', () {
      expect(entity('ngE'), '≧̸');
    });

    test('a surrogate is not a character', () {
      expect(entity('#xD800'), isNull);
    });

    test('nothing is beyond the last code point', () {
      expect(entity('#x110000'), isNull);
    });

    test('and nought is the character a reader is shown for none', () {
      expect(entity('#0'), '�');
    });

    test('a name that is not a name is not one', () {
      expect(entity('notanentity'), isNull);
      expect(entity('#notanumber'), isNull);
    });

    test('a number is digits, with no sign', () {
      for (final name in [
        '#-65', '#+65', '#x-41', '#x+41', '#', '#x', //
        '#${'9' * 30}', '#x${'F' * 30}',
      ]) {
        expect(entity(name), isNull, reason: name);
      }
    });
  });

  group('Where references stand', () {
    test('read out one at a time rather than all at once', () {
      final found = references('&amp;&lt;&gt;', 0, 13);
      expect(found, isA<Iterable<(int, int, String)>>());
      expect(found.take(1), [(0, 5, '&')]);
    });

    test('an ampersand that opens nothing is passed over', () {
      expect(references('a &c and ?a=1&b=2 &amp;', 0, 23).toList(), [
        (18, 23, '&'),
      ]);
    });

    test('however long the name the standard gives it', () {
      const text = 'a &CounterClockwiseContourIntegral; b';
      expect(references(text, 0, text.length).toList(), [(2, 35, '∳')]);
      expect(resolved('&NotNestedGreaterGreater;'), '⪢̸');
    });

    test('only within the stretch asked about', () {
      expect(references('&amp;&amp;', 5, 10).toList(), [(5, 10, '&')]);
      expect(references('&amp;&amp;', 0, 4).toList(), isEmpty);
    });
  });

  group('A value as written in a tag', () {
    test('is read as what it says', () {
      expect(resolved('a &amp; b'), 'a & b');
      expect(resolved('plain'), 'plain');
      expect(resolved('&nosuch; &lt;'), '&nosuch; <');
    });
  });
}
