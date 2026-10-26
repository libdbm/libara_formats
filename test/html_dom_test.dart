import 'dart:io';
import 'dart:math';

import 'package:html/dom.dart' as reference;
import 'package:html/parser.dart' as reference;
import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:libara_formats/src/html/html.dart' show nested;
import 'package:test/test.dart';

import 'harness.dart';

/// The elements package:html builds for [text], in pre-order, as
/// `depth:name` under a `#document` at depth 0.
List<String> expected(String text) {
  final order = ['0:#document'];
  void walk(reference.Node node, int depth) {
    for (final child in node.nodes) {
      if (child is reference.Element) {
        final space = switch (child.namespaceUri) {
          'http://www.w3.org/2000/svg' => 'svg ',
          'http://www.w3.org/1998/Math/MathML' => 'math ',
          _ => '',
        };
        order.add('$depth:$space${child.localName}');
        walk(child, depth + 1);
      }
    }
  }

  walk(reference.parse(text), 1);
  return order;
}

/// The elements of [document]'s layer 3 in pre-order, nested by HTML's
/// rule.
List<String> built(Layered<int> document) => [
  '0:#document',
  for (final (element, depth, space) in nested(document))
    '${depth + 1}:${space.isEmpty ? '' : '$space '}${element.get('')}',
];

/// HTML's layer 3: the WHATWG tree construction.
void main() {
  const html = HTML();

  group('Elements nest as package:html builds them', () {
    for (final text in const [
      '',
      'x',
      '<p>x',
      '<!doctype html><html><head><title>t</title></head><body><p>a</body></html>',
      '<!--a--><p>x</p><!--b-->',
      '<p>a<p>b<div>c</div>',
      '<ul><li>a<li>b</ul><ol><li>c</ol>',
      '<dl><dt>a<dd>b<dt>c</dl>',
      '<h1>a<h2>b</h2></h1>',
      'x</p>y',
      'a<br></br>b',
      '<head><meta charset=x><link rel=a><title>t</title></head><p>x',
      ' \n <p>x',
      '<html><body>',
      '<button>a<button>b</button>',
      '<select><option>a<option>b</select>',
      '<p>a</div>b</p>',
      '<div><p>a</div>b',
      '<pre>\nx</pre><hr><img src=a><input>',
      '<body><p>a</body><p>b',
      '</html><!--c--><p>after',
      '<noscript><p>x</p></noscript>',
      '<textarea><p></textarea><script>a<b</script>',
      '<ruby>a<rt>b<rp>c</ruby>',
      '<span><address>a</address></span>',
      // The adoption agency and active formatting, T10a.
      '<b>1<p>2</b>3</p>',
      '<b><i>x</b>y</i>',
      '<p><b><i>x</p>y',
      '<a href=1>x<a href=2>y</a>',
      '<b>1<div>2<i>3</b>4</i>5</div>',
      '<p><b><b><b><b>x</p>y',
      '<nobr>a<nobr>b',
      '<b><p>x</b><div>y',
      '<object><b>x</object>y',
      '<em>a<p>b</em><p>c',
      '<u><s>x<h1>y</u>z</h1>',
    ]) {
      test(text.isEmpty ? '(empty)' : text, () {
        expect(built(decoded(html, text)), expected(text));
      });
    }

    for (final name in [
      'alice',
      'htpasswd',
      'markwrite',
      'ranges',
      'xinclude',
      'xmlbase',
      'huck',
      'xml-names',
      'xml-stylesheet',
    ]) {
      test('$name.html', () {
        final text = File('test/samples/$name.html').readAsStringSync();
        expect(built(decoded(html, text)), expected(text));
      });
    }
  });

  group('At random', () {
    // No select, whose 2025 rules package:html predates, and no template,
    // which package:html reads as an ordinary element. The html5lib cases
    // hold those to the standard.
    const pieces = [
      '<p>', '</p>', '<div>', '</div>', '<ul>', '</ul>', '<ol>', '<li>', //
      '</li>', '<dl>', '<dt>', '<dd>', '</dd>', '<h1>', '</h1>', '<h2>',
      '</h2>', '<span>', '</span>', '<button>', '</button>', '<br>', '</br>',
      '<hr>', '<img>', '<pre>', '</pre>', '<section>', '</section>',
      '<address>', '<form>', '</form>', '<option>', '<optgroup>', '<ruby>',
      '<rt>', '<rp>', '<html>', '</html>', '<head>', '</head>', '<body>',
      '</body>', '<title>t</title>', '<script>x</script>', '<meta>',
      '<link>', '<style>s</style>', '<!-- c -->', '<!doctype html>', 'text',
      ' ',
      '\n',
      '</x>',
      '<x>',
      '<noscript>n</noscript>',
      // No textarea: package:html, as html5lib, reads its text in body and
      // reopens formatting elements inside it, where the standard reads it
      // in the "text" mode and does not. A test below pins the standard.
      '<b>', '</b>', '<i>', '</i>', '<a href=x>', '</a>', '<em>', '</em>',
      '<nobr>', '</nobr>', '<font color=red>', '</font>', '<object>',
      '</object>', '<marquee>', '</marquee>',
      '<table>', '</table>', '<tr>', '</tr>', '<td>', '</td>', '<th>', //
      '<tbody>', '</tbody>', '<caption>', '</caption>', '<colgroup>', '<col>',
      '<thead>', '<svg>', '</svg>', '<math>', '</math>', '<mi>', '</mi>',
      '<circle/>', '<g>', '</g>', '<foreignObject>', '</foreignObject>',
      '<desc>', '<mtext>', '<annotation-xml encoding="text/html">',
      '<![CDATA[x]]>',
    ];
    for (var seed = 0; seed < 2000; seed++) {
      test('document $seed', () {
        final random = Random(seed);
        final text = [
          for (var at = 0; at < 1 + random.nextInt(14); at++)
            pieces[random.nextInt(pieces.length)],
        ].join();
        // package:html keeps </p> and </br> inside foreign content, where
        // the standard now breaks out of it; the html5lib case
        // `<p><math></p>a` holds us to it.
        if ((text.contains('<svg') || text.contains('<math')) &&
            (text.contains('</p>') || text.contains('</br>'))) {
          return;
        }
        final document = decoded(html, text);
        // Fostered content stays where it is written, by design.
        if (problems(document, 3).any((it) => it.startsWith('fostered'))) {
          return;
        }
        expect(built(document), expected(text), reason: text);
      });
    }
  });

  group('Where package:html and the standard part', () {
    test('a textarea holds text, with no formatting reopened inside it', () {
      expect(built(decoded(html, '<p><b>x</p><textarea>a</textarea>y')), [
        '0:#document',
        '1:html',
        '2:head',
        '2:body',
        '3:p',
        '4:b',
        '3:textarea',
        '3:b',
      ]);
    });
  });

  group('Implied elements', () {
    test('are ranges without tags of their own, an empty head included', () {
      final document = decoded(html, '<p>x');
      final ranges = {
        for (final range in document.layer(3).items.cast<ARange>())
          '${range.get('')}': (range.start, range.length),
      };
      expect(ranges, {
        'html': (0, 2),
        'head': (0, 0),
        'body': (0, 2),
        'p': (0, 2),
      });
    });

    test('a p a stray end tag implies covers that tag', () {
      final document = decoded(html, 'x</p>y');
      final p = document
          .layer(3)
          .items
          .cast<ARange>()
          .firstWhere((range) => said(range, '') == 'p');
      expect((p.start, p.length), (1, 1));
    });
  });

  group('Parse errors', () {
    test('an element the text ends inside, where the standard objects', () {
      expect(problems(decoded(html, '<div>x'), 3), ['unclosed <div>']);
      expect(problems(decoded(html, '<p>x'), 3), isEmpty);
    });

    test('an end tag that closes nothing', () {
      expect(problems(decoded(html, '<p>a</span>b'), 3), [
        'end tag </span> closes nothing',
      ]);
    });
  });

  group('Edits', () {
    // Each typed or deleted into the text, which a fresh read checks.
    for (final (source, edit) in [
      ('<p>one <em>two</em> three</p>', Insert<int>(5, Text.of('x'))),
      // Text, a reference and text join into one run, at the end of an
      // element its end tag does not close.
      ('<p><em>a &amp; b</p><p>c</p>', Delete<int>(value(Range.create(10, 4)))),
      ('<table><tr><td>a</td></tr> </table>', Insert<int>(26, Text.of('x'))),
      (
        '<html><head> </head><body></body></html>',
        Insert<int>(12, Text.of('x')),
      ),
    ]) {
      test('$edit on $source reads as its text does', () {
        edited(html, decoded(html, source), Edit(1, edit));
      });
    }
    for (final name in ['markwrite', 'ranges', 'htpasswd']) {
      test('editing $name.html at random derives what a fresh read does', () {
        derivable(
          html,
          File('test/samples/$name.html').readAsStringSync(),
          seed: name.hashCode + 1,
          edits: 200,
        );
      });
    }
  });
}
