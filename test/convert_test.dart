import 'dart:io';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:libara_formats/src/convert.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// Conversion between the tree syntaxes, ported from markwrite's
/// `emit_test`: a document read in one is written in another, its content
/// and its elements, and a tree syntax refuses what it cannot nest.
void main() {
  const xml = XML();
  const html = HTML();
  const lmnl = LMNL();

  /// [text] read as [from] and written as [to].
  Result<Sequence<int>> converted(Syntax from, Syntax to, String text) =>
      to.encode(decoded(from, text));

  /// [text] read as [from], written as [to], as text.
  String written(Syntax from, Syntax to, String text) =>
      string(value(converted(from, to, text)));

  group('A document written in a syntax', () {
    test('in its own is its text', () {
      const text = '<p>The <i>quick</i> brown fox.</p>';
      expect(written(xml, xml, text), text);
    });

    test('XML as LMNL', () {
      expect(
        written(xml, lmnl, '<p>The <i>quick</i> fox.</p>'),
        '[p}The [i}quick{i] fox.{p]',
      );
    });

    test('LMNL as XML, where it nests', () {
      expect(
        written(lmnl, xml, '[p}The [i}quick{i] fox.{p]'),
        '<p>The <i>quick</i> fox.</p>',
      );
    });

    test('with characters past the BMP keeps every one', () {
      expect(written(xml, html, '<a>x😀y😀z</a>'), contains('x😀y😀z'));
      expect(written(xml, lmnl, '<a>x😀y😀z</a>'), '[a}x😀y😀z{a]');
    });

    test('LMNL that overlaps is refused as XML and HTML, and kept as LMNL', () {
      // a covers "xxyy" and b "yyzz": they cross in the content.
      const text = '[a}xx[b}yy{a]zz{b]';
      for (final tree in [xml, html]) {
        expect(
          converted(lmnl, tree, text),
          isA<Failure<Sequence<int>>>()
              .having((failure) => failure.kind, 'kind', Kind.invalid)
              .having(
                (failure) => failure.message,
                'message',
                contains('overlapping'),
              ),
        );
      }
      expect(written(lmnl, lmnl, text), text);
    });

    test('HTML as XML, with the elements HTML implies', () {
      expect(
        written(html, xml, '<p>a <em>b</em> c</p>'),
        '<html><head/><body><p>a <em>b</em> c</p></body></html>',
      );
    });

    test('XML as HTML, a void element without an end', () {
      expect(
        written(xml, html, '<p>a<br/>b <i>c</i><x></x></p>'),
        '<p>a<br>b <i>c</i><x></x></p>',
      );
    });

    test('attributes, escapes and references carry over', () {
      expect(
        written(xml, lmnl, '<p n="1&amp;2">a &lt; [b]</p>'),
        '[p [n}1&2{n]}a < \\[b\\]{p]',
      );
      expect(
        written(lmnl, xml, '[p [n}"1"{n]}a < & \\[b\\]{p]'),
        '<p n="&quot;1&quot;">a &lt; &amp; [b]</p>',
      );
    });

    test('what markup only is leaves nothing behind', () {
      expect(
        written(xml, lmnl, '<?xml version="1.0"?><!--c--><p>a<?pi?></p>'),
        '[p}a{p]',
      );
    });

    test('what HTML reads as it stands is carried as its content', () {
      expect(
        written(html, xml, '<title>a<b</title><script>x</script>'),
        '<html><head><title>a&lt;b</title><script>x</script></head>'
        '<body/></html>',
      );
    });
  });

  group('Every sample written in XML and LMNL', () {
    /// What [document] says: its content, and each element in pre-order
    /// with its depth, name, attributes and the content it holds.
    List<String> says(Layered<int> document) {
      final (:content, :offsets, :elements) = projected(document);
      return [
        content,
        for (final element in elements)
          '${element.depth} ${element.name} ${element.said} '
              '${content.substring(offsets[element.first], offsets[element.last])}',
      ];
    }

    for (final name in [
      'alice', 'htpasswd', 'huck', 'markwrite', 'ranges', //
      'xinclude', 'xml-names', 'xml-stylesheet', 'xmlbase',
    ]) {
      for (final (from, extension) in [
        (xml, 'xml'),
        (html, 'html'),
        (lmnl, 'lmnl'),
      ]) {
        test('$name.$extension reads back as it was read', () {
          final document = decoded(
            from,
            File('test/samples/$name.$extension').readAsStringSync(),
          );
          for (final to in [xml, lmnl]) {
            switch (to.encode(document)) {
              case Failure(:final message):
                expect(message, contains('overlapping'), reason: '$to');
                expect(from, lmnl);
              case Success(value: final written):
                expect(
                  says(decoded(to, string(written))),
                  says(document),
                  reason: '$to',
                );
            }
          }
        });
      }
    }
  });

  group('Every sample written in every syntax', () {
    final samples = [
      for (final file in Directory('test/samples').listSync().whereType<File>())
        if (formats[file.path.split('.').last] case final Syntax syntax)
          (file.path.split('/').last, syntax, file.readAsStringSync()),
    ];
    for (final (name, from, text) in samples) {
      test('$name is written, or refused saying why, and never throws', () {
        final document = decoded(from, text);
        for (final MapEntry(key: called, value: to) in formats.entries) {
          switch (to.encode(document)) {
            case Failure(:final kind, :final message):
              expect(kind, Kind.invalid, reason: called);
              expect(message, isNotEmpty, reason: called);
            case Success(value: final written):
              expect(
                to.decode(written),
                isA<Success<Layered<int>>>(),
                reason: called,
              );
          }
        }
      });
    }
  });

  group('A document written as LMNL', () {
    test('writes an element over nothing as an empty range', () {
      expect(written(xml, lmnl, '<p>a<br/>b</p>'), '[p}a[br]b{p]');
      expect(written(lmnl, xml, '[p}a[br]b{{hr}}{p]'), '<p>a<br/>b<hr/></p>');
    });

    test('refuses a name a tag cannot hold', () {
      expect(
        converted(html, lmnl, '<x"y>z</x"y>'),
        isA<Failure<Sequence<int>>>().having(
          (failure) => failure.message,
          'message',
          contains('x"y'),
        ),
      );
    });
  });

  group('A document written as HTML', () {
    const markdown = Markdown();

    test('drops a target that runs', () {
      expect(
        written(markdown, html, '[x](javascript:alert(1))'),
        '<p><a>x</a></p>',
      );
      expect(
        written(markdown, html, '![a](JavaScript:x)'),
        '<p><img alt="a"></p>',
      );
      expect(
        written(markdown, html, '[x](https://example.invalid)'),
        '<p><a href="https://example.invalid">x</a></p>',
      );
    });

    test('writes an element a browser would run as a span', () {
      expect(
        written(markdown, html, '[alert(1)](script "element")'),
        '<p><span>alert(1)</span></p>',
      );
      expect(
        written(lmnl, html, '[style}p{color:red}{style]'),
        '<span>p{color:red}</span>',
      );
    });

    test('drops an attribute that runs a handler', () {
      expect(
        written(xml, html, '<a onclick="x()" href="y">z</a>'),
        '<a href="y">z</a>',
      );
    });
  });

  group('A Markdown link', () {
    const markdown = Markdown();

    test('that would run says so', () {
      expect(problems(decoded(markdown, '[x](javascript:alert(1))'), 3), [
        contains('runs'),
      ]);
      expect(problems(decoded(markdown, '[a](script "element")'), 3), [
        contains('script'),
      ]);
      expect(problems(decoded(markdown, '[x](y)'), 3), isEmpty);
    });
  });

  group('Placing elements in the content', () {
    test('nested and adjacent elements stand exactly', () {
      expect(
        written(xml, lmnl, '<a>one<b>two</b><c>three</c>four</a>'),
        '[a}one[b}two{b][c}three{c]four{a]',
      );
    });

    test('an empty element stands between its neighbours', () {
      expect(written(xml, lmnl, '<a>one<br/>two</a>'), '[a}one[br]two{a]');
      expect(written(lmnl, xml, '[a}one[br]two{a]'), '<a>one<br/>two</a>');
    });
  });
}
