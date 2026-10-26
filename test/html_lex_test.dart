import 'dart:io';

import 'package:html/src/token.dart'
    as reference; // ignore: implementation_imports
import 'package:html/src/tokenizer.dart'
    as reference; // ignore: implementation_imports
import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// HTML's layer 2, by the WHATWG tokenizer: one token per tag, comment,
/// doctype and character reference, one per run of text, and one per
/// element whose content is not markup, from its start tag to its end tag.
void main() {
  const html = HTML();

  List<String> marks(String text) => [
    for (final (name, _) in tokens(decoded(html, text)))
      if (name != '#text') name,
  ];

  group('Tags', () {
    test('the text is kept verbatim', () {
      roundtrip(html, '<P CLASS=A>One <B>two</b></P>');
    });

    test('names are lower-cased, the text unchanged', () {
      final document = decoded(html, '<P CLASS=A>One</P>');
      expect(tokens(document), [
        ('p', '<P CLASS=A>'),
        ('#text', 'One'),
        ('p', '</P>'),
      ]);
      expect(said(token(document, 0), 'class'), 'A');
    });

    test('a void element is one token, written either way', () {
      expect(tokens(decoded(html, 'a<br>b<br/>c')), [
        ('#text', 'a'),
        ('br', '<br>'),
        ('#text', 'b'),
        ('br', '<br/>'),
        ('#text', 'c'),
      ]);
    });

    test('an unquoted value ends only at a space or the close', () {
      final document = decoded(html, '<img src=a/><a href=/x/y title=t>');
      expect(said(token(document, 0), 'src'), 'a/');
      expect(said(token(document, 12), 'href'), '/x/y');
      expect(said(token(document, 12), 'title'), 't');
    });

    test('a value may hold the close, and say a reference', () {
      final document = decoded(html, '<a title="a > b" href="?a=1&amp;b">');
      expect(said(token(document, 0), 'title'), 'a > b');
      expect(said(token(document, 0), 'href'), '?a=1&b');
    });

    test('in a value a legacy reference before = or a letter is text', () {
      final document = decoded(html, '<a href="?x=1&copy=2&copy;">');
      expect(said(token(document, 0), 'href'), '?x=1&copy=2©');
    });

    test('an attribute with no value says the empty string', () {
      expect(said(token(decoded(html, '<input disabled>'), 0), 'disabled'), '');
    });

    test('a repeated attribute keeps the first, under a diagnostic', () {
      final document = decoded(html, '<p a=1 A=2>x</p>');
      expect(said(token(document, 0), 'a'), '1');
      expect(problems(document, 2), ['duplicate attribute a']);
    });

    test('an end tag with attributes says so', () {
      expect(problems(decoded(html, '<p>x</p a=1>'), 2), [
        'end tag with attributes',
      ]);
    });

    test('a less-than that opens no tag is text', () {
      expect(tokens(decoded(html, 'a < b <3 c<')), [('#text', 'a < b <3 c<')]);
    });

    test('an empty end tag is dropped, under a diagnostic', () {
      final document = decoded(html, 'a</>b');
      expect(marks('a</>b'), ['#bogus']);
      expect(problems(document, 2), ['missing end tag name']);
    });

    test('a tag the text ends inside is dropped, under a diagnostic', () {
      final document = decoded(html, 'a<p class="x');
      expect(tokens(document).last, ('#bogus', '<p class="x'));
      expect(problems(document, 2), ['end of text in a tag']);
    });
  });

  group('Comments and the doctype', () {
    test('a comment, and the short ones the standard closes early', () {
      expect(tokens(decoded(html, '<!-- a --><!--><!--->x<!-- b --!>')), [
        ('#comment', '<!-- a -->'),
        ('#comment', '<!-->'),
        ('#comment', '<!--->'),
        ('#text', 'x'),
        ('#comment', '<!-- b --!>'),
      ]);
    });

    test('a comment the text ends inside runs to the end', () {
      final document = decoded(html, 'a<!-- b');
      expect(tokens(document).last, ('#comment', '<!-- b'));
      expect(problems(document, 2), ['end of text in a comment']);
    });

    test('a bogus comment, from a question mark or a stray bang', () {
      expect(marks('<?xml x?><!x><! >'), ['#comment', '#comment', '#comment']);
      expect(marks('</ x>'), ['#comment']);
    });

    test('a doctype, in any case', () {
      expect(tokens(decoded(html, '<!doctype html><!DOCTYPE html>')), [
        ('#doctype', '<!doctype html>'),
        ('#doctype', '<!DOCTYPE html>'),
      ]);
    });
  });

  group('Character references', () {
    test('named, with a semicolon', () {
      final document = decoded(html, 'a &amp; b &NotEqualTilde; c');
      expect(marks('a &amp; b &NotEqualTilde; c'), ['#entity', '#entity']);
      expect(said(token(document, 2), 'shows'), '&');
    });

    test('a legacy one without its semicolon, under a diagnostic', () {
      final document = decoded(html, 'a &amp b &copy2');
      expect(tokens(document), [
        ('#text', 'a '),
        ('#entity', '&amp'),
        ('#text', ' b '),
        ('#entity', '&copy'),
        ('#text', '2'),
      ]);
      expect(problems(document, 2), [
        'missing semicolon after character reference',
        'missing semicolon after character reference',
      ]);
    });

    test('the longest name that matches', () {
      expect(tokens(decoded(html, '&notit;'))[0], ('#entity', '&not'));
      expect(tokens(decoded(html, '&notin;'))[0], ('#entity', '&notin;'));
    });

    test('numbered, in either base, as the standard maps them', () {
      String shows(String text) =>
          said(token(decoded(html, text), 0), 'shows')!;
      expect(shows('&#169;'), '©');
      expect(shows('&#xA9;'), '©');
      expect(shows('&#128;'), '€');
      expect(shows('&#0;'), '�');
      expect(shows('&#xD800;'), '�');
      expect(shows('&#x110000;'), '�');
    });

    test('and what is not one is text', () {
      expect(tokens(decoded(html, 'a &c; &# &#x; ?a=1&b=2')), [
        ('#text', 'a &c; &# &#x; ?a=1&b=2'),
      ]);
    });
  });

  group('Elements whose content is not markup', () {
    for (final name in ['script', 'style', 'title', 'textarea', 'xmp']) {
      test('$name is one token, to its own end tag', () {
        final text = '<$name a=1><b>x</b> &amp; </${name.toUpperCase()} >y';
        final document = decoded(html, text);
        expect(tokens(document), [
          (name, '<$name a=1><b>x</b> &amp; </${name.toUpperCase()} >'),
          ('#text', 'y'),
        ]);
        expect(said(token(document, 0), 'a'), '1');
      });
    }

    test('and one never closed runs to the end of the text', () {
      expect(tokens(decoded(html, '<script>a</scrip')), [
        ('script', '<script>a</scrip'),
      ]);
    });

    test('plaintext takes in the rest of the text', () {
      expect(tokens(decoded(html, 'a<plaintext></plaintext><b>')), [
        ('#text', 'a'),
        ('plaintext', '<plaintext></plaintext><b>'),
      ]);
    });
  });

  group('Unicode', () {
    test('a character outside the BMP is one position', () {
      final document = decoded(html, '<p title="\u{1F600}">a\u{1D11E}b</p>');
      expect(
        [for (final range in document.layer(2).items) range.start],
        [0, 13, 16],
      );
    });
  });

  group('Samples', () {
    final files = Directory('test/samples')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.html'));
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      test('$name round-trips', () {
        roundtrip(html, file.readAsStringSync());
      });

      test('$name has the tags package:html reads, in order', () {
        final text = file.readAsStringSync();
        final expected = <String>[];
        final tokenizer = reference.HtmlTokenizer(text);
        while (tokenizer.moveNext()) {
          switch (tokenizer.current) {
            case reference.StartTagToken(:final name):
              expected.add('<$name');
            case reference.EndTagToken(:final name):
              expected.add('</$name');
          }
        }
        final document = decoded(html, text);
        final read = <String>[];
        for (final range in document.layer(2).items.cast<ARange>()) {
          final name = '${range.get('')}';
          if (name.startsWith('#')) {
            continue;
          }
          final tag = sliced(document, range);
          if (tag.startsWith('</')) {
            read.add('</$name');
          } else {
            read.add('<$name');
            if (tag.toLowerCase().contains('</$name')) {
              read.add('</$name');
            }
          }
        }
        expect(read, expected);
      });
    }

    for (final name in ['markwrite', 'ranges', 'htpasswd']) {
      test('editing $name.html at random derives what a fresh read does', () {
        derivable(
          html,
          File('test/samples/$name.html').readAsStringSync(),
          seed: name.hashCode,
          edits: 300,
        );
      });
    }
  });
}

/// The text [range] covers in [document].
String sliced(Layered<int> document, Range range) =>
    string(document.slice(range));
