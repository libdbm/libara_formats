import 'dart:io';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// XML's layer 2: one token per tag, construct and reference, and one per
/// run of text between them. Ported from markwrite's `xml_lex_test`,
/// `token_boundaries_test` and `entities_test`; what pairs the tokens into
/// elements is layer 3's, and tested there.
void main() {
  const xml = XML();

  group('Tokens', () {
    test('the text is kept verbatim', () {
      roundtrip(xml, '<p>The <i>quick</i> brown fox.</p>');
    });

    test('each tag, and each run between, is a token at its offset', () {
      final document = decoded(xml, '<p>The <i>quick</i> brown fox.</p>');
      expect(tokens(document), [
        ('p', '<p>'),
        ('#text', 'The '),
        ('i', '<i>'),
        ('#text', 'quick'),
        ('i', '</i>'),
        ('#text', ' brown fox.'),
        ('p', '</p>'),
      ]);
      expect(
        [for (final range in document.layer(2).items) range.start],
        [0, 3, 7, 10, 15, 19, 30],
      );
      expect(problems(document, 2), isEmpty);
    });

    test('an empty tag is one token', () {
      expect(tokens(decoded(xml, '<p>a<br/>b</p>')), [
        ('p', '<p>'),
        ('#text', 'a'),
        ('br', '<br/>'),
        ('#text', 'b'),
        ('p', '</p>'),
      ]);
    });

    test('attributes are carried on the start token and not the end', () {
      final document = decoded(
        xml,
        '<a href="http://x" rel="me" hidden>go</a>',
      );
      final start = token(document, 0);
      expect(said(start, 'href'), 'http://x');
      expect(said(start, 'rel'), 'me');
      expect(said(start, 'hidden'), '');
      expect(token(document, 37).attributes.keys, ['']);
    });

    test('an attribute called name does not touch the element name', () {
      final start = token(decoded(xml, '<a name="top">x</a>'), 0);
      expect(said(start, ''), 'a');
      expect(said(start, 'name'), 'top');
    });

    test('an attribute value is held as what it says', () {
      final start = token(decoded(xml, '<a href="?a=1&amp;b=2">x</a>'), 0);
      expect(said(start, 'href'), '?a=1&b=2');
    });

    test('a quoted attribute value may contain the tag close', () {
      final document = decoded(xml, '<a title="a > b">x</a>');
      expect(said(token(document, 0), 'title'), 'a > b');
      expect(tokens(document).first, ('a', '<a title="a > b">'));
    });
  });

  group('Constructs that are not elements', () {
    test('a comment is markup, a token of its own', () {
      expect(tokens(decoded(xml, '<!-- c --><p>hi</p>')), [
        ('#comment', '<!-- c -->'),
        ('p', '<p>'),
        ('#text', 'hi'),
        ('p', '</p>'),
      ]);
    });

    test('an instruction and a doctype are tokens too', () {
      expect(tokens(decoded(xml, '<?xml version="1.0"?><!DOCTYPE p><p/>')), [
        ('#pi', '<?xml version="1.0"?>'),
        ('#doctype', '<!DOCTYPE p>'),
        ('p', '<p/>'),
      ]);
    });

    test('a doctype is read through its internal subset', () {
      const doctype =
          '<!DOCTYPE r [\n<!ENTITY e "x>y">\n<!-- ] > -->\n'
          "<!ATTLIST r a CDATA '>'>\n<?pi ]>?>\n]>";
      final document = decoded(xml, '$doctype<r/>');
      expect(tokens(document), [('#doctype', doctype), ('r', '<r/>')]);
      expect(problems(document, 2), isEmpty);
    });

    test('a CDATA section is read to its own end, not to the first >', () {
      final document = decoded(xml, '<p><![CDATA[a > b <b>]]>hi</p>');
      expect(tokens(document), [
        ('p', '<p>'),
        ('#cdata', '<![CDATA[a > b <b>]]>'),
        ('#text', 'hi'),
        ('p', '</p>'),
      ]);
      expect(said(token(document, 3), 'shows'), 'a > b <b>');
    });
  });

  group('References', () {
    test('a reference stays in the text and says what it stands for', () {
      final document = decoded(xml, '<p>a &amp; b &lt; c</p>');
      expect(string(document.items), '<p>a &amp; b &lt; c</p>');
      expect(tokens(document), [
        ('p', '<p>'),
        ('#text', 'a '),
        ('#entity', '&amp;'),
        ('#text', ' b '),
        ('#entity', '&lt;'),
        ('#text', ' c'),
        ('p', '</p>'),
      ]);
      expect(said(token(document, 5), 'shows'), '&');
    });

    test('an ampersand that opens nothing is text', () {
      expect(tokens(decoded(xml, '<p>tea &c, ?a=1&b=2</p>'))[1], (
        '#text',
        'tea &c, ?a=1&b=2',
      ));
    });

    test('a name this does not know is left as it was written', () {
      expect(tokens(decoded(xml, '<p>&nosuchthing;</p>'))[1], (
        '#text',
        '&nosuchthing;',
      ));
    });

    test('a reference inside a tag is left to the tag', () {
      expect(tokens(decoded(xml, '<a href="&amp;">x</a>')).first, (
        'a',
        '<a href="&amp;">',
      ));
    });
  });

  group('What does not parse', () {
    test('an unterminated CDATA section is a diagnostic, not a failure', () {
      final document = decoded(xml, '<p><![CDATA[a > b</p>');
      expect(problems(document, 2), ['unterminated character section']);
      expect(tokens(document).last, ('#text', '<![CDATA[a > b</p>'));
    });

    test('so are an unterminated tag and comment', () {
      expect(problems(decoded(xml, '<p>a<b'), 2), ['unterminated tag']);
      expect(problems(decoded(xml, '<p>a<!-- b'), 2), ['unterminated comment']);
    });

    test('and a tag with no name', () {
      final document = decoded(xml, '<p>a<>b</p>');
      expect(problems(document, 2), ['tag with no name']);
      expect(tokens(document)[2], ('#text', '<>'));
    });

    test('and an attribute with no name, which is dropped', () {
      final document = decoded(xml, '<p ="x" a="y">z</p>');
      expect(problems(document, 2), ['attribute with no name']);
      expect(token(document, 0).attributes.keys, unorderedEquals(['', 'a']));
    });
  });

  group('Edits', () {
    test('typing beside a tag does not grow it', () {
      final document = value(
        decoded(xml, '<p>x</p>').apply(Edit(1, Insert(3, Text.of('X')))),
      ).document;
      expect(tokens(document), [('p', '<p>'), ('#text', 'Xx'), ('p', '</p>')]);
    });

    test('a reference broken by an edit joins the text before it', () {
      final document = value(
        decoded(xml, '<p>ab&amp;c</p>').apply(Edit(1, Insert(8, Text.of('X')))),
      ).document;
      expect(layers(document), layers(decoded(xml, '<p>ab&amXp;c</p>')));
      expect(tokens(document)[1], ('#text', 'ab&amXp;c'));
    });

    test('a comment opened by an edit takes in what follows', () {
      final document = value(
        decoded(
          xml,
          '<p>a</p><q>b</q>-->',
        ).apply(Edit(1, Insert(4, Text.of('<!--')))),
      ).document;
      expect(layers(document), layers(decoded(xml, '<p>a<!--</p><q>b</q>-->')));
    });
  });

  group('Samples', () {
    for (final file
        in Directory('test/samples')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.xml'))) {
      test('${file.uri.pathSegments.last} round-trips', () {
        roundtrip(xml, file.readAsStringSync());
      });
    }
  });
}
