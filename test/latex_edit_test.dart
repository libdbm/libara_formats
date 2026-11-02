import 'dart:io';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';
import 'roff_edit_test.dart' show proposed;

/// LaTeX's structural edits: each is the text it writes or takes away, read
/// again, as roff's and Markdown's are, so every one leaves the layers a
/// fresh read gives.
void main() {
  const latex = LaTeX();

  Layered<int> read(String text) => decoded(latex, text);

  group('Layer 2: markup', () {
    test('an inline element is written a command and a brace at a time', () {
      var document = read('a b c');
      document = edited(latex, document, Edit(2, Mark(Close(3, 'em'))));
      document = edited(latex, document, Edit(2, Mark(Open(2, 'em'))));
      expect(string(document.items), 'a \\emph{b} c');
    });

    test('an environment is written on lines of its own', () {
      final document = edited(
        latex,
        read('a b'),
        Edit(2, Mark(Open(2, 'blockquote'))),
      );
      expect(string(document.items), 'a \\begin{quote}\nb');
    });

    test('deleting tokens takes their markup away', () {
      final document = read('a \\emph{b} c');
      final next = edited(
        latex,
        document,
        Edit(2, Delete(value(Range.create(at(document, '\\emph{'), 1)))),
      );
      expect(string(next.items), 'a b} c');
    });

    test('a name LaTeX has no representation for is refused', () {
      refused(
        read('a'),
        Edit(2, Mark(Open(0, 'span'))),
        'no representation for',
      );
    });
  });

  group('Layer 3: wrapping', () {
    for (final (name, said, written) in [
      ('em', <String, String>{}, '\\emph{a b}'),
      ('strong', <String, String>{}, '\\textbf{a b}'),
      ('code', <String, String>{}, '\\texttt{a b}'),
      ('h1', <String, String>{}, '\\section{a b}'),
      ('math', <String, String>{}, '\$a b\$'),
      ('equation', <String, String>{}, '\\[a b\\]'),
      ('a', {'href': 'http://x/a_b'}, '\\href{http://x/a\\_b}{a b}'),
      ('ul', <String, String>{}, '\\begin{itemize}\na b\n\\end{itemize}'),
      ('pre', <String, String>{}, '\\begin{verbatim}\na b\n\\end{verbatim}'),
    ]) {
      test('words in $name, which read back as one', () {
        final document = read('a b');
        final marker = Marker();
        final next = edited(
          latex,
          document,
          Edit(3, Mark.of(marker, over(0, 1, {'': name, ...said}))),
        );
        expect(string(next.items), written);
        expect(marked(next, marker).get(''), Str(Text.of(name)));
      });
    }

    test('a name LaTeX has no representation for is refused', () {
      refused(
        read('a'),
        Edit(3, Mark(over(0, 1, {'': 'span'}))),
        'no representation for',
      );
    });
  });

  group('Layer 3: unwrapping, renaming and deleting', () {
    for (final (text, name, written) in [
      ('a \\emph{b} c', 'em', 'a b c'),
      ('\\section{One}\n', 'h1', 'One\n'),
      ('\\begin{quote}\nx\n\\end{quote}\n', 'blockquote', '\nx\n\n'),
      ('a \\href{http://x}{b}', 'a', 'a b'),
    ]) {
      test('$name unwrapped from "$text"', () {
        final document = read(text);
        final next = edited(
          latex,
          document,
          Edit(3, Unmark(element(document, name))),
        );
        expect(string(next.items), written);
      });
    }

    test('a paragraph has no representation to take away', () {
      final document = read('a');
      refused(
        document,
        Edit(3, Unmark(element(document, 'p'))),
        'representation',
      );
    });

    for (final (text, from, to, written) in [
      ('a \\emph{b} c', 'em', 'strong', 'a \\textbf{b} c'),
      ('\\section{A}\n', 'h1', 'h2', '\\subsection{A}\n'),
      (
        '\\begin{itemize}\n\\item x\n\\end{itemize}\n',
        'ul',
        'ol',
        '\\begin{enumerate}\n\\item x\n\\end{enumerate}\n',
      ),
      ('a \\href{http://x}{b}', 'a', 'em', 'a \\emph{b}'),
    ]) {
      test('$from renamed $to, keeping its marker', () {
        final document = read(text);
        final marker = element(document, from);
        final next = edited(
          latex,
          document,
          Edit(3, Update(marker, {'': Str(Text.of(to))})),
        );
        expect(string(next.items), written);
        expect(said(marked(next, marker), ''), to);
      });
    }

    test('a link given a new address is recast', () {
      final document = read('a \\href{http://x}{b}');
      final marker = element(document, 'a');
      final next = edited(
        latex,
        document,
        Edit(
          3,
          Update(marker, {'': Str(Text.of('a')), 'href': Str(Text.of('y'))}),
        ),
      );
      expect(string(next.items), 'a \\href{y}{b}');
    });

    test('mathematics renamed is written afresh', () {
      // A dollar opens and closes alike, so neither says which it is.
      final document = read('a \$b\$ c');
      final next = edited(
        latex,
        document,
        Edit(3, Update(element(document, 'math'), {'': Str(Text.of('em'))})),
      );
      expect(string(next.items), 'a \\emph{b} c');
    });

    test('the document renamed reads its preamble again as words', () {
      // Nothing near the rename changes, but the preamble's words show
      // once no document follows them.
      final document = read(
        '\\documentclass{article}\n\\usepackage{x\\section{y}\n\n\n'
        '\\begin{document}\n\n\nA\n\n\\end{document}\n',
      );
      edited(
        latex,
        document,
        Edit(
          3,
          Update(element(document, 'document'), {'': Str(Text.of('strong'))}),
        ),
      );
    });

    test('elements are deleted with what they hold', () {
      final document = read('a \\emph{b} c\n\nd\n');
      final index = document
          .layer(3)
          .items
          .toList()
          .indexWhere((range) => said(range as ARange, '') == 'em');
      final next = edited(
        latex,
        document,
        Edit(3, Delete(value(Range.create(index, 1)))),
      );
      expect(string(next.items), 'a  c\n\nd\n');
    });
  });

  group('At random', () {
    for (final name in ['codens', 'maltese', 'review', 'stopping']) {
      test('structural edits of $name.tex leave what a fresh read gives', () {
        structural(
          latex,
          File('test/samples/$name.tex').readAsStringSync(),
          proposed,
          seed: name.hashCode,
          edits: 150,
        );
      });
    }
  });
}
