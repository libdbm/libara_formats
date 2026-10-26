import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// Ported from markwrite's `codec_malformed_test`. What markwrite refused
/// is here a document with diagnostics: it still opens, still round-trips,
/// and says what is wrong where.
void main() {
  const xml = XML();

  // Each input, and whether markwrite's XML codec refused it.
  const malformed = {
    'an unterminated start tag': ('<p>one <em two</p>', true),
    'a close with no open': ('<p>one</em> two</p>', true),
    'tags that cross rather than nest': ('<a>one <b>two</a> three</b>', true),
    'a stray less-than': ('<p>a < b</p>', true),
    'a stray greater-than': ('<p>a > b</p>', false),
    'an unterminated comment': ('<p>a <!-- b</p>', true),
    'an unterminated character section': ('<p><![CDATA[ a </p>', true),
    'an unterminated entity': ('<p>a &amp b &#x</p>', false),
    'an entity nobody has heard of': ('<p>a &nope; b</p>', false),
    'an unquoted attribute': ('<p class=a b>one</p>', false),
    'an attribute quote never closed': ('<p class="a>one</p>', true),
    'the same attribute said twice': ('<p a="1" a="2">one</p>', false),
    'a tag with no name': ('<>one</>', true),
    'nothing at all': ('', false),
    'markers and no content': ('<<>><<>>', true),
  };

  group('Malformed XML opens, round-trips, and says what is wrong', () {
    for (final MapEntry(key: name, value: (text, refused))
        in malformed.entries) {
      test(name, () {
        final document = decoded(xml, text);
        roundtrip(xml, text);
        expect(document.valid, !refused);
      });
    }
  });

  group('What does not pair', () {
    test('an end tag closing something else names both', () {
      final document = decoded(xml, '<p>x</q></p>');
      expect(problems(document, 3), ['</q> closes p']);
      expect(preorder(document), ['0:#document', '1:p']);
    });

    test('an end tag closing nothing says so', () {
      expect(problems(decoded(xml, 'x</q>'), 3), ['</q> closes nothing']);
    });

    test('a start tag never closed says so, and is not an element', () {
      final document = decoded(xml, '<p>x');
      expect(problems(document, 3), ['unclosed <p>']);
      expect(preorder(document), ['0:#document']);
    });

    test('tags that cross pair what nests and name the rest', () {
      final document = decoded(xml, '<a>one <b>two</a> three</b>');
      expect(problems(document, 3), ['unclosed <a>', '</a> closes b']);
      expect(preorder(document), ['0:#document', '1:b']);
    });
  });

  group('XML names what it could not finish reading', () {
    const sources = {
      'comment': '<a><!-- x</a>',
      'character section': '<a><![CDATA[ x</a>',
      'processing instruction': '<a><?pi x',
      'declaration': '<a><!DOCTYPE x',
    };
    for (final MapEntry(key: construct, value: text) in sources.entries) {
      test('an unterminated $construct', () {
        final document = decoded(xml, text);
        expect(problems(document, 2), ['unterminated $construct']);
        expect(document.diagnostics(2).items.single.start, 3);
      });
    }
  });
}
