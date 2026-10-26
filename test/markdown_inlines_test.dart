import 'dart:io';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// Markdown's inlines: each mark that is syntax is a token named for
/// the element it belongs to, and each element runs from its first token to
/// its last.
void main() {
  const markdown = Markdown();

  Layered<int> read(String text) => decoded(markdown, text);

  /// The elements of [text] called [name], each with the text it covers.
  List<(ARange, String)> named(String text, String name) => [
    for (final (element, covered) in covering(read(text)))
      if (said(element, '') == name) (element, covered),
  ];

  /// The tokens of [text] called [name].
  List<String> marks(String text, String name) => [
    for (final (called, covered) in tokens(read(text)))
      if (called == name) covered,
  ];

  group('Emphasis, code and references', () {
    test('emphasis and strong markers pair by order', () {
      const text = 'a *em* and **strong** end';
      expect(marks(text, 'em'), ['*', '*']);
      expect(marks(text, 'strong'), ['**', '**']);
      expect(named(text, 'em').single.$2, '*em*');
      expect(named(text, 'strong').single.$2, '**strong**');
    });

    test('a code span pairs its backticks and shields its content', () {
      const text = 'run `a * b` now';
      expect(marks(text, 'em'), isEmpty);
      expect(named(text, 'code').single.$2, '`a * b`');
    });

    test('nested inline gives a tree by containment', () {
      final elements = [
        for (final (element, _) in covering(read('**a *b* c**')))
          said(element, ''),
      ];
      expect(elements, ['p', 'strong', 'em']);
    });

    test('an escaped marker is a character, shown by its escape', () {
      const text = r'a \* not em';
      expect(marks(text, 'em'), isEmpty);
      final escape = read(text)
          .layer(2)
          .items
          .cast<ARange>()
          .firstWhere((token) => token.start == 2);
      expect(said(escape, ''), '#escape');
      expect(said(escape, 'shows'), '*');
    });

    test('a reference shows its character', () {
      final token = read('a &amp; b')
          .layer(2)
          .items
          .cast<ARange>()
          .firstWhere((token) => said(token, '') == '#entity');
      expect(said(token, 'shows'), '&');
    });

    test('a token moves when text is inserted before it', () {
      final document = edited(
        markdown,
        read('a *b* c'),
        Edit(1, Insert(0, Text.of('XX'))),
      );
      expect(said(token(document, 6), ''), 'em');
    });

    test('a hard break asked for either way, with or without returns', () {
      expect(marks('a  \nb', 'br'), ['  ']);
      expect(marks('a\\\nb', 'br'), [r'\']);
      expect(marks('a  \r\nb', 'br'), ['  \r']);
      expect(marks('a\\\r\nb', 'br'), [r'\']);
      expect(marks('a  \n', 'br'), isEmpty);
    });

    test('an autolink goes where it says', () {
      final (link, text) = named('see <https://x.org> now', 'a').single;
      expect(text, '<https://x.org>');
      expect(said(link, 'href'), 'https://x.org');
    });
  });

  group('A Markdown link', () {
    test('is an element carrying where it goes', () {
      final (link, text) = named(
        'See [the manual](https://example.org) now.',
        'a',
      ).single;
      expect(said(link, 'href'), 'https://example.org');
      expect(text, '[the manual](https://example.org)');
    });

    test('and its words are read like any other, so marks inside it read', () {
      expect(named('[a *quick* gull](x)', 'em'), hasLength(1));
    });

    test('and its title is said', () {
      final (link, _) = named(
        '[the site](https://example.org "Example")',
        'a',
      ).single;
      expect(said(link, 'title'), 'Example');
    });

    test('and a picture inside one is stepped over, not read as its end', () {
      final document = read('[![alt](p.png)](https://example.org)');
      final elements = covering(document);
      final link = elements.firstWhere((one) => said(one.$1, '') == 'a').$1;
      final picture = elements
          .firstWhere((one) => said(one.$1, '') == 'img')
          .$1;
      expect(said(link, 'href'), 'https://example.org');
      expect(said(picture, 'src'), 'p.png');
      expect(link.start <= picture.start && picture.end <= link.end, isTrue);
    });

    test('and a link whose text runs over a line is still a link', () {
      for (final text in ['[a\nb](x)', '[a [b] c](x)', '[a](<b c>)']) {
        expect(named(text, 'a'), hasLength(1), reason: text);
      }
    });

    test('and markup it cannot read stays ordinary text', () {
      for (final text in [
        '[a](x',
        '[a] (x)',
        '[a](x\ny)',
        '[a',
        '[a](b c)',
        r'\[a](b)',
      ]) {
        expect(named(text, 'a'), isEmpty, reason: text);
        roundtrip(markdown, text);
      }
    });

    test('written by name, goes where a definition says', () {
      for (final text in ['[a][x]', '[x][]', '[x]', '[X]']) {
        final (link, _) = named('$text\n\n[x]: /u "T"\n', 'a').single;
        expect(said(link, 'href'), '/u', reason: text);
        expect(said(link, 'title'), 'T', reason: text);
      }
      expect(named('[y]\n\n[x]: /u\n', 'a'), isEmpty);
    });

    test('and the first definition of a name is the one that counts', () {
      final (link, _) = named('[x]\n\n[x]: /one\n[x]: /two\n', 'a').single;
      expect(said(link, 'href'), '/one');
    });

    test('a definition is a token, and a paragraph of them no block', () {
      final document = read('[x]: /u "T"\n');
      final definition = document.layer(2).items.cast<ARange>().first;
      expect(said(definition, ''), '#definition');
      expect(said(definition, 'label'), 'x');
      expect(said(definition, 'href'), '/u');
      expect(covering(document), isEmpty);
    });
  });

  group('Markdown images', () {
    test('an image is one token that is its own element', () {
      const text = 'A gull: ![A gull](gull.png) here.\n';
      final document = read(text);
      final picture = token(document, 8);
      expect(string(document.slice(picture)), '![A gull](gull.png)');
      expect(said(picture, ''), 'img');
      final (image, _) = named(text, 'img').single;
      expect(said(image, 'src'), 'gull.png');
      expect(said(image, 'alt'), 'A gull');
      expect(image.length, 1);
    });

    test('markers inside the image are the image\'s, not emphasis', () {
      const text = '![A *quick* gull](a_b.png)';
      expect(marks(text, 'em'), isEmpty);
      expect(said(named(text, 'img').single.$1, 'alt'), 'A quick gull');
    });

    test('escaped markup is left as text', () {
      expect(named(r'Not an image: !\[a](b).', 'img'), isEmpty);
    });

    test('markup that falls short is left as text', () {
      for (final text in [
        '![alt](never closed',
        '![alt] (x.png)',
        '![alt](x\n.png)',
        '![alt',
        '!',
      ]) {
        expect(named(text, 'img'), isEmpty, reason: text);
      }
    });

    test('an image may say nothing of itself', () {
      final (image, _) = named('![](x.png)', 'img').single;
      expect(said(image, 'alt'), '');
      expect(said(image, 'src'), 'x.png');
    });

    test('an image inside a code span is code', () {
      expect(named('Say `![a](b)` to write one.', 'img'), isEmpty);
    });
  });

  group('Markdown nested deep', () {
    test('in its pictures is read as deep as they go', () {
      final (image, _) = named('${'![' * 100}a${'](/u)' * 100}', 'img').single;
      expect(said(image, 'alt'), 'a');
    });

    test('and brackets nest as deep as anybody writes them, in a moment', () {
      final clock = Stopwatch()..start();
      expect(named('${'[' * 4000}a${'](/u)' * 4000}', 'a'), hasLength(1));
      expect(clock.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('Re-reading after a keystroke', () {
    const far = 'one\n\ntwo\n\nthree\n\nfour\n\nfive\n\n';

    test('a definition changed changes the links it names, far away', () {
      final text = 'see [x]\n\n$far[x]: /one\n';
      final document = edited(
        markdown,
        read(text),
        Edit(
          1,
          Replace(
            value(Range.create(text.indexOf('/one') + 1, 3)),
            Text.of('two'),
          ),
        ),
      );
      final link = covering(document)
          .firstWhere((one) => said(one.$1, '') == 'a');
      expect(said(link.$1, 'href'), '/two');
    });

    test('a definition added makes a link of a name far away', () {
      final text = 'see [x]\n\n$far';
      final document = edited(
        markdown,
        read(text),
        Edit(1, Insert(text.length, Text.of('[x]: /u\n'))),
      );
      expect(
        covering(document).where((one) => said(one.$1, '') == 'a'),
        hasLength(1),
      );
    });

    test('a definition taken away unmakes the links it named, far away', () {
      final text = 'see [x]\n\n$far[x]: /u\n';
      final document = edited(
        markdown,
        read(text),
        Edit(1, Delete(value(Range.create(text.indexOf('[x]:'), 8)))),
      );
      expect(
        covering(document).where((one) => said(one.$1, '') == 'a'),
        isEmpty,
      );
    });

    test('a link written by name, typed far from its definition', () {
      final text = 'see x]\n\n$far[x]: /u\n';
      final document = edited(
        markdown,
        read(text),
        Edit(1, Insert(text.indexOf('x]'), Text.of('['))),
      );
      expect(
        covering(document).where((one) => said(one.$1, '') == 'a'),
        hasLength(1),
      );
    });

    for (final name in ['markwrite', 'ranges', 'htpasswd']) {
      test('editing $name.md at random derives what a fresh read does', () {
        derivable(
          markdown,
          File('test/samples/$name.md').readAsStringSync(),
          seed: name.hashCode + 7,
          edits: 200,
        );
      });
    }
  });
}
