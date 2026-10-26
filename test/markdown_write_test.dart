import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// What Markdown writes, against what it reads: ported from markwrite's
/// `markdown_write_test`, the writing cases of `emit_test`, and the cases
/// of `markdown_link_test` and `markdown_table_test` that write.
void main() {
  const markdown = Markdown();
  const xml = XML();

  /// The names a fresh read of [text] finds.
  Set<String> named(String text) => {
    for (final (element, _) in covering(decoded(markdown, text)))
      '${element.get('')}',
  };

  /// [text] read as XML and written as Markdown.
  String written(String text) =>
      string(value(markdown.encode(decoded(xml, text))));

  group('A structural edit represents, so that a fresh read finds one,', () {
    for (final name in [
      'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'em', 'strong', 'code', //
      'blockquote', 'pre', 'ul', 'ol', 'li', 'a',
    ]) {
      test(name, () {
        final document = decoded(markdown, 'x\n');
        final next = edited(
          markdown,
          document,
          Edit(
            3,
            Mark(
              value(
                ARange.create(
                  0,
                  1,
                  attributes: {
                    '': Str(Text.of(name)),
                    if (name == 'a') 'href': Str(Text.of('http://x')),
                  },
                ),
              ),
            ),
          ),
        );
        expect(named(string(next.items)), contains(name));
      });
    }

    for (final (name, said, text, at) in [
      ('hr', <String, String>{}, '', 0),
      ('table', <String, String>{}, '', 0),
      ('img', {'src': 'x.png'}, '', 0),
      // A break is between two things, so it is read with one either side.
      ('br', <String, String>{}, 'one two\n', 3),
    ]) {
      test(name, () {
        final document = edited(
          markdown,
          decoded(markdown, text),
          Edit(2, Mark(Empty(at, name, said))),
        );
        expect(named(string(document.items)), contains(name));
        if (name == 'table') {
          expect(
            named(string(document.items)),
            containsAll(['table', 'tr', 'th', 'td']),
          );
        }
      });
    }
  });

  group('Words written as Markdown read back as the same words', () {
    /// The elements a fresh read of [text] written as Markdown finds, each
    /// with the content it shows and what it says.
    List<String> back(String text) => [
      for (final (element, _) in covering(decoded(markdown, written(text))))
        [
          '${element.get('')}',
          for (final key in ['href', 'src'])
            if (said(element, key) case final String value) '$key=$value',
        ].join(' '),
    ];

    test('code holding a backtick', () {
      const text = '<p><code>a`b</code> and <code>`</code></p>';
      expect(written(text), '``a`b`` and `` ` ``');
      expect(back(text), ['p', 'code', 'code']);
    });

    test('a link to where spaces and brackets stand', () {
      expect(back('<p><a href="x y)">t</a> <img src="a b" alt="c"/></p>'), [
        'p',
        'a href=x%20y)',
        'img src=a%20b',
      ]);
    });

    test('a line that would begin a block', () {
      for (final line in ['# hi', '1. one', '2) two', '- x', '+ y', '> q']) {
        final escaped = line.replaceAll('>', '&gt;');
        expect(back('<p>$escaped</p>'), ['p'], reason: line);
      }
      expect(back('<p>a<br/>- b</p>'), ['p', 'br']);
    });

    test('an HTML page with nothing in its head', () {
      expect(
        string(value(markdown.encode(decoded(const HTML(), '<p>x</p>')))),
        'x',
      );
    });
  });

  group('A document read in another syntax, written as Markdown', () {
    test('is its blocks and inlines', () {
      expect(written('<h1>Title</h1><p>a <em>b</em></p>'), '# Title\n\na *b*');
    });

    test('and the first block stands where the text begins', () {
      // Nothing stands before it to part it from, so a line end before it
      // is kept as it was rather than made a blank line.
      expect(written('<doc>\n<h1>T</h1><p>a</p></doc>'), '\n# T\n\na');
    });

    test('a paragraph ending in one line end still stands apart', () {
      // From roff, say: the words before a paragraph end in the newline
      // before its request, and one newline in Markdown runs on.
      expect(written('<doc><p>one\n</p><p>two\n</p></doc>'), 'one\n\ntwo\n');
      final read = written('<doc><p>one\n</p><p>two\n</p></doc>');
      expect([
        for (final (element, _) in covering(decoded(markdown, read)))
          if ('${element.get('')}' == 'p') element,
      ], hasLength(2));
    });

    test(
      'and an element Markdown cannot represent stands in a link for itself',
      () {
        // Read as XML, where `<toc/>` holds nothing, as it would not in HTML.
        final text = written('<article><toc/><p>text</p></article>');
        expect(text, contains('[](toc "element")'));
        final names = named(text);
        expect(names, contains('toc'));
        expect(names, isNot(contains('a')));
      },
    );

    test('while one with content keeps the content', () {
      final text = written('<article><aside>kept</aside></article>');
      expect(text, contains('kept'));
      expect(text, isNot(contains('"element"')));
    });

    test('and a table is written with bars', () {
      final text = written(
        '<article><table><tr><th>A</th><th>B</th></tr>'
        '<tr><td>1</td><td>2</td></tr></table></article>',
      );
      expect(text, contains('| A | B |'));
      expect(text, contains('| --- | --- |'));
      expect(text, contains('| 1 | 2 |'));
    });

    test('with a bar inside a cell escaped so it does not end it', () {
      expect(
        written(
          '<article><table><tr><td>a | b</td><td>c</td></tr></table>'
          '</article>',
        ),
        contains(r'a \| b'),
      );
    });

    test('and what is written reads back as the same table', () {
      final document = decoded(
        markdown,
        written(
          '<article><table><tr><th>Header 1</th><th>Header 2</th></tr>'
          '<tr><td>Row 1, Col 1</td><td>Row 1, Col 2</td></tr></table>'
          '</article>',
        ),
      );
      List<String> cells(String name) => [
        for (final (element, covered) in covering(document))
          if (said(element, '') == name) covered.trim(),
      ];
      expect(cells('th'), ['Header 1', 'Header 2']);
      expect(cells('td'), ['Row 1, Col 1', 'Row 1, Col 2']);
    });

    test('and a numbered list counts on from the last where it continues', () {
      expect(
        written(
          '<d><ol start="3"><li>a</li><li>b</li></ol>'
          '<ol continue=""><li>c</li></ol></d>',
        ),
        '3. a\n4. b\n\n5. c',
      );
    });
  });
}
