import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

const pipes = '''
Before.

| Header 1 | Header 2 | Header 3 |
| --- | --- | --- |
| Row 1, Col 1 | Row 1, Col 2 | Row 1, Col 3 |
| Row 2, Col 1 | Row 2, Col 2 | Row 2, Col 3 |

After.
''';

/// Pipe tables: a table, its rows and its cells are elements, the bars are
/// tokens of their rows, and the dashes under the head a token of the table.
void main() {
  const markdown = Markdown();

  /// What the elements of [text] called [name] cover.
  List<String> named(String text, String name) => [
    for (final (element, covered) in covering(decoded(markdown, text)))
      if (said(element, '') == name) covered,
  ];

  /// The bars and rulings of [text], as tokens.
  List<String> syntax(String text) => [
    for (final (name, covered) in tokens(decoded(markdown, text)))
      if (name == 'tr' || name == 'table') '$name "$covered"',
  ];

  group('Reading a pipe table', () {
    test('a table, its rows and its cells are all there', () {
      expect(named(pipes, 'table'), hasLength(1));
      expect(named(pipes, 'tr'), hasLength(3));
      expect(named(pipes, 'th'), ['Header 1', 'Header 2', 'Header 3']);
      expect(named(pipes, 'td'), [
        'Row 1, Col 1', 'Row 1, Col 2', 'Row 1, Col 3', //
        'Row 2, Col 1', 'Row 2, Col 2', 'Row 2, Col 3',
      ]);
      expect(named(pipes, 'p'), ['Before.', 'After.']);
    });

    test('the table ends where the rows do', () {
      final table = named(pipes, 'table').single;
      expect(table, startsWith('| Header 1'));
      expect(table, endsWith('Row 2, Col 3 |'));
    });

    test('lines of the paragraph before it are a paragraph', () {
      const text = 'Intro *here*\n| a | b |\n| - | - |\n';
      expect(named(text, 'p'), ['Intro *here*']);
      expect(named(text, 'em'), ['*here*']);
      expect(named(text, 'th'), ['a', 'b']);
    });

    test('a line after it with no bar is a row, as GFM reads one', () {
      const text = '| a | b |\n| - | - |\n| c | d |\nbar\n\nafter\n';
      expect(named(text, 'tr'), hasLength(3));
      expect(named(text, 'td'), ['c', 'd', 'bar']);
      expect(named(text, 'p'), ['after']);
    });

    test('a head with more cells than its ruling is no table', () {
      const text = '| a | b |\n| - |\n';
      expect(named(text, 'table'), isEmpty);
      expect(named(text, 'p'), hasLength(1));
    });

    test('an empty cell between two bars is a cell, and the bars apart', () {
      const text = '| a |  |\n| --- | --- |\n|  | d |\n';
      expect(named(text, 'th'), ['a', '']);
      expect(named(text, 'td'), ['', 'd']);
      expect(named(text, 'tr'), hasLength(2));
    });

    test('what is typed in an empty cell stands between its spaces', () {
      const text = '| a |  |\n| --- | --- |\n';
      final document = decoded(markdown, text);
      final cell = covering(document)
          .lastWhere((found) => said(found.$1, '') == 'th')
          .$1;
      // An empty element stands before the token it is counted at.
      final at = document.layer(2).items.elementAt(cell.start).start;
      final typed = edited(
        markdown,
        document,
        Edit(1, Insert(at, Text.of('x'))),
      );
      expect(string(typed.items), '| a | x |\n| --- | --- |\n');
    });

    test('a bar with no dashes under it is only a bar', () {
      expect(named('A | B\n\nplain text\n', 'table'), isEmpty);
    });

    test('an escaped bar does not divide a cell', () {
      expect(named('| a \\| b | c |\n| --- | --- |\n', 'th'), [r'a \| b', 'c']);
    });

    test('words in a cell are read as words, and stay in it', () {
      const text = '| *a | b* | `c` |\n| --- | --- | --- |\n';
      expect(named(text, 'em'), isEmpty);
      expect(named(text, 'code'), ['`c`']);
    });

    test('a bar does not take what is typed against it', () {
      const text = '| a | b |\n| - | - |\n| c | d |\n';
      final document = edited(
        markdown,
        decoded(markdown, text),
        Edit(1, Insert(2, Text.of('x'))),
      );
      expect(tokens(document).first, ('tr', '| '));
    });
  });

  group('Editing a pipe table', () {
    /// [text] with [requests] written, one at a time, each at layer 2.
    String written(String text, List<ARange> requests) {
      var document = decoded(markdown, text);
      for (final request in requests) {
        document = edited(markdown, document, Edit(2, Mark(request)));
      }
      return string(document.items);
    }

    /// The tags of a row of [cells] cells called [name], at [at], last
    /// first, as an editor writes them at one point.
    List<ARange> row(int at, int cells, [String name = 'td']) => [
      Close(at, 'tr'),
      for (var cell = 0; cell < cells; cell++) ...[
        Close(at, name),
        Open(at, name),
      ],
      Open(at, 'tr'),
    ];

    test('a table is written at one point, the ruling under its head', () {
      const text = 'Words.\n\n';
      expect(
        written(text, [
          Close(8, 'table'),
          ...row(8, 2),
          ...row(8, 2, 'th'),
          Open(8, 'table'),
        ]),
        'Words.\n\n|  |  |\n| --- | --- |\n|  |  |\n',
      );
    });

    test('a row is a line written where the next begins', () {
      const text = '| a | b |\n| --- | --- |\n| c | d |\n';
      expect(
        written(text, row(text.indexOf('| c'), 2)),
        '| a | b |\n| --- | --- |\n|  |  |\n| c | d |\n',
      );
    });

    test('a cell after the last of each row widens the ruling', () {
      const text = '| a | b |\n| --- | --- |\n| c | d |\n';
      final cell = [
        for (final at in [text.indexOf('d') + 1, text.indexOf('b') + 1]) ...[
          Close(at, 'td'),
          Open(at, 'td'),
        ],
      ];
      expect(
        written(text, cell),
        '| a | b |  |\n| --- | --- | --- |\n| c | d |  |\n',
      );
    });

    test('a cell taken with its bar narrows the ruling', () {
      const text = '| a | b |\n| --- | --- |\n| c | d |\n';
      var document = decoded(markdown, text);
      for (final word in ['d', 'b']) {
        final at = tokens(document).indexWhere((token) => token.$2 == word);
        document = edited(
          markdown,
          document,
          Edit(2, Delete(value(Range.create(at, 2)))),
        );
      }
      expect(string(document.items), '| a |\n| --- |\n| c |\n');
    });

    test('a row written leaves the ruling as it is written', () {
      // Its alignment is the author's, and a ruling written afresh moves
      // every line after it under what an editor is still writing.
      const text = '| a | b |\n|:---|---:|\n| c | d |\n';
      expect(
        written(text, row(text.indexOf('| c'), 2)),
        '| a | b |\n|:---|---:|\n|  |  |\n| c | d |\n',
      );
    });

    test('a cell after the last widens the ruling in its own markup', () {
      const text = '| a | b |\n|-----|:---:|\n| c | d |\n';
      final cell = [
        for (final at in [text.indexOf('d') + 1, text.indexOf('b') + 1]) ...[
          Close(at, 'td'),
          Open(at, 'td'),
        ],
      ];
      expect(
        written(text, cell),
        '| a | b |  |\n|-----|:---:|-----|\n| c | d |  |\n',
      );
    });

    test('a cell taken narrows the ruling where the cell stood', () {
      const text = '| a | b | c |\n|:---|:---:|---:|\n| d | e | f |\n';
      var document = decoded(markdown, text);
      for (final word in ['e', 'b']) {
        final at = tokens(document).indexWhere((token) => token.$2 == word);
        document = edited(
          markdown,
          document,
          Edit(2, Delete(value(Range.create(at, 2)))),
        );
      }
      expect(string(document.items), '| a | c |\n|:---|---:|\n| d | f |\n');
    });

    test('the head taken out, the next row is the head', () {
      const text = '| a | b |\n| --- | --- |\n| c | d |\n';
      final document = decoded(markdown, text);
      // The head's tokens and the line ending after them.
      final next = edited(
        markdown,
        document,
        Edit(2, Delete(value(Range.create(0, 6)))),
      );
      expect(string(next.items), '| c | d |\n| --- | --- |\n');
      expect(named(string(next.items), 'th'), ['c', 'd']);
    });
  });

  group('A heading line holding a bar', () {
    test('is a heading, not the head of a table', () {
      expect(named('# | a\n-|-\n', 'h1'), hasLength(1));
      expect(named('# | a\n-|-\n', 'table'), isEmpty);
    });

    test('while a table under an ordinary line is still a table', () {
      expect(
        syntax('| head | next |\n| --- | --- |\n| one | two |\n'),
        isNotEmpty,
      );
    });
  });

  group('A table behind something else', () {
    test('indented, is read and leaves the indent to the block', () {
      expect(syntax('  | a | b |\n  |---|---|'), [
        'tr "| "',
        'tr " | "',
        'tr " |"',
        'table "|---|---|"',
      ]);
    });

    test('and with only its rule indented', () {
      expect(syntax('| a | b |\n  |---|---|'), contains('table "|---|---|"'));
    });

    test('and with only its head indented', () {
      expect(syntax('  | a | b |\n|---|---|'), contains('table "|---|---|"'));
    });

    test('inside a list item, is read', () {
      expect(
        syntax('- item\n\n  | a | b |\n  |---|---|'),
        contains('table "|---|---|"'),
      );
    });

    test('inside a quotation, is read', () {
      expect(syntax('> | a | b |\n> |---|---|'), [
        'tr "| "',
        'tr " | "',
        'tr " |"',
        'table "|---|---|"',
      ]);
    });
  });

  group('What looks like a table but is code', () {
    test('in a fenced block, is left alone', () {
      expect(syntax('```\n| a | b |\n|---|---|\n```'), isEmpty);
    });

    test('in an indented block, is left alone', () {
      expect(syntax('    | a | b |\n    | --- | --- |'), isEmpty);
    });
  });

  test('every one of them is kept as it was written', () {
    for (final text in [
      pipes,
      '  | a | b |\n  |---|---|',
      '| a | b |\n  |---|---|',
      '  | a | b |\n|---|---|',
      '- item\n\n  | a | b |\n  |---|---|',
      '> | a | b |\n> |---|---|',
      '```\n| a | b |\n|---|---|\n```',
      '    | a | b |\n    | --- | --- |',
    ]) {
      roundtrip(markdown, text);
    }
  });

  test('editing tables at random derives what a fresh read does', () {
    for (var seed = 0; seed < 20; seed++) {
      derivable(markdown, '$pipes\n> $pipes\n- $pipes' * 2, seed: seed);
    }
  });
}
