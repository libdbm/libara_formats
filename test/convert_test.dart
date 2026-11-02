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

  group('Elements that cross, written as a tree', () {
    // Each LMNL text, with what XML makes of it: the inline is cut where it
    // crosses a block, and of two inlines the later is cut.
    const cases = {
      'an em across two paragraphs is an em in each': (
        '[p}aa[em}bb{p][p}cc{em]dd{p]',
        '<p>aa<em part="initial" join="1">bb</em></p>'
            '<p><em part="final" join="1">cc</em>dd</p>',
      ),
      'of an em and a strong that cross, the strong is cut': (
        '[em}aa[strong}bb{em]cc{strong]',
        '<em>aa<strong part="initial" join="1">bb</strong></em>'
            '<strong part="final" join="1">cc</strong>',
      ),
      'a paragraph starting inside an em is whole, the em cut': (
        '[em}aa[p}bb{em]cc{p]',
        '<em part="initial" join="1">aa</em>'
            '<p><em part="final" join="1">bb</em>cc</p>',
      ),
      'an em across three paragraphs is three pieces': (
        '[p}a[em}b{p][p}c{p][p}d{em]e{p]',
        '<p>a<em part="initial" join="1">b</em></p>'
            '<p><em part="medial" join="1">c</em></p>'
            '<p><em part="final" join="1">d</em>e</p>',
      ),
      'an em across two cells is an em in each': (
        '[table}[tr}[td}a[em}b{td][td}c{em]d{td]{tr]{table]',
        '<table><tr><td>a<em part="initial" join="1">b</em></td>'
            '<td><em part="final" join="1">c</em>d</td></tr></table>',
      ),
    };
    for (final MapEntry(key: name, value: (text, tree)) in cases.entries) {
      test(name, () => expect(written(lmnl, xml, text), tree));
    }

    test('two elements cut say different joins', () {
      expect(
        written(lmnl, xml, '[p}[em}a{p][p}b{em][strong}c{p][p}d{strong]{p]'),
        '<p><em part="initial" join="1">a</em></p>'
        '<p><em part="final" join="1">b</em>'
        '<strong part="initial" join="2">c</strong></p>'
        '<p><strong part="final" join="2">d</strong></p>',
      );
    });

    test('an element cut that already says part or join is refused', () {
      for (final key in ['part', 'join']) {
        expect(
          converted(lmnl, xml, '[p}a[em [$key}x{$key]}b{p][p}c{em]{p]'),
          isA<Failure<Sequence<int>>>()
              .having((failure) => failure.kind, 'kind', Kind.invalid)
              .having((failure) => failure.message, 'message', contains(key)),
        );
      }
    });

    test('an element not cut is written with what it says', () {
      expect(
        written(lmnl, xml, '[em [part}x{part]}a{em]'),
        '<em part="x">a</em>',
      );
    });

    // What the other tree writers make of the same texts, in order. LaTeX
    // has no tables, so that is not asserted.
    const others = {
      'html': [
        '<p>aa<em>bb</em></p><p><em>cc</em>dd</p>',
        '<em>aa<strong>bb</strong></em><strong>cc</strong>',
        '<em>aa</em><p><em>bb</em>cc</p>',
        '<p>a<em>b</em></p><p><em>c</em></p><p><em>d</em>e</p>',
        '<table><tr><td>a<em>b</em></td><td><em>c</em>d</td></tr></table>',
      ],
      'markdown': [
        'aa*bb*\n\n*cc*dd',
        '*aa**bb*** **cc**',
        '*aa*\n\n*bb*cc',
        'a*b*\n\n*c*\n\n*d*e',
        '| a*b* | *c*d |\n| --- | --- |',
      ],
      'latex': [
        '\\documentclass{article}\n\\begin{document}\naa\\emph{bb}\n\n\\emph{cc}dd\n\\end{document}\n',
        '\\documentclass{article}\n\\begin{document}\n\\emph{aa\\textbf{bb}}\\textbf{cc}\n\\end{document}\n',
        '\\documentclass{article}\n\\begin{document}\n\\emph{aa}\n\n\\emph{bb}cc\n\\end{document}\n',
        '\\documentclass{article}\n\\begin{document}\na\\emph{b}\n\n\\emph{c}\n\n\\emph{d}e\n\\end{document}\n',
        null,
      ],
      'man': [
        '.PP\naa\\fIbb\\fP\n.PP\n\\fIcc\\fPdd',
        '\\fIaa\\fBbb\\fP\\fR\\fBcc\\fP',
        '\\fIaa\\fP\n.PP\n\\fIbb\\fPcc',
        '.PP\na\\fIb\\fP\n.PP\n\\fIc\\fP\n.PP\n\\fId\\fPe',
        '.TS\nl l.\na\\fIb\\fP\t\\fIc\\fPd\n.TE\n',
      ],
    };
    final texts = [for (final (text, _) in cases.values) text];
    for (final MapEntry(key: to, value: expected) in others.entries) {
      test('the same, written as $to', () {
        for (final (index, text) in texts.indexed) {
          if (expected[index] case final String tree) {
            expect(written(lmnl, formats[to]!, text), tree, reason: text);
          }
        }
      });
    }
  });

  test('Markdown parts two runs of * that would meet with a space', () {
    // An em ending in a strong, then a strong: `***` and `**` that met
    // would read back as neither.
    const text = '<em>aa<strong>bb</strong></em><strong>cc</strong>';
    final written = string(value(const Markdown().encode(decoded(xml, text))));
    expect(written, '*aa**bb*** **cc**');
    expect(
      string(value(xml.encode(decoded(const Markdown(), written)))),
      '<p><em>aa<strong>bb</strong></em> <strong>cc</strong></p>',
    );
  });

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

    test('LMNL that overlaps is split as XML and HTML, and kept as LMNL', () {
      // a covers "xxyy" and b "yyzz": they cross in the content, and b,
      // starting later, is cut where a ends.
      const text = '[a}xx[b}yy{a]zz{b]';
      expect(
        written(lmnl, xml, text),
        '<a>xx<b part="initial" join="1">yy</b></a>'
        '<b part="final" join="1">zz</b>',
      );
      expect(written(lmnl, html, text), '<a>xx<b>yy</b></a><b>zz</b>');
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
          // No sample has elements that cross, so each is written whole.
          for (final to in [xml, lmnl]) {
            final written = value(to.encode(document));
            expect(
              says(decoded(to, string(written))),
              says(document),
              reason: '$to',
            );
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
