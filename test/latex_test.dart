import 'dart:io';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// LaTeX, ported from markwrite's `latex_lex_test`: commands, environments,
/// braces and dollars are tokens named for what they represent, and the
/// elements stand over them.
void main() {
  const latex = LaTeX();

  Layered<int> read(String text) => decoded(latex, text);

  /// The elements of [text] in the order they open, outermost first, each
  /// as its name and the text it covers.
  List<(String, String)> elements(String text) => [
    for (final (element, covered) in covering(read(text)))
      ('${element.get('')}', covered),
  ];

  /// The elements of [text] called [name].
  List<ARange> named(String text, String name) => [
    for (final (element, _) in covering(read(text)))
      if (said(element, '') == name) element,
  ];

  /// What a reader is shown of [text], or of its tokens from [from] to
  /// [to]: runs of text as they stand, an escape what it shows, and other
  /// markup nothing.
  String shown(String text, [int from = 0, int? to]) {
    final document = read(text);
    final tokens = document.layer(2).items.cast<ARange>().toList();
    return [
      for (final token in tokens.sublist(from, to ?? tokens.length))
        switch ('${token.get('')}') {
          '#text' => string(document.slice(token)),
          '#escape' => '${token.get('shows')}',
          _ => '',
        },
    ].join();
  }

  /// What a reader is shown of [element] in [text].
  String inside(String text, ARange element) =>
      shown(text, element.start, element.end);

  group('A LaTeX document', () {
    test('keeps its text verbatim, and is found by its extensions', () {
      roundtrip(
        latex,
        '\\documentclass{article}\n\\begin{document}\n'
        '\\section{One}\nWords \\emph{here}.\n\\end{document}\n',
      );
      expect(formats['tex'], isA<LaTeX>());
      expect(formats['latex'], isA<LaTeX>());
    });

    test('a preamble and a document are blocks of their own', () {
      const text =
          '\\documentclass[12pt]{article}\n\\usepackage{amsmath}\n'
          '\\makeatletter\\def\\@x{junk}\\makeatother\n'
          '\\title{A \\emph{Paper}}\n\\author{Me \\and You}\n'
          '\\begin{document}\n\\maketitle\nWords.\n\\end{document}\n'
          'after the end\n';
      expect(
        [for (final (name, _) in elements(text)) name],
        ['preamble', 'title', 'em', 'author', 'document', 'p'],
      );
      expect(elements(text)[1], ('title', '\\title{A \\emph{Paper}}'));
      expect(elements(text)[4], (
        'document',
        '\\begin{document}\n\\maketitle\nWords.\n\\end{document}\n'
            'after the end\n',
      ));
      expect(
        shown(text).trim().split(RegExp(r'\s+')).join(' '),
        'A Paper Me and You Words.',
      );
    });

    test('a text with no document environment is all body', () {
      expect(elements('One.\n\nTwo.\n'), [('p', 'One.'), ('p', 'Two.')]);
    });

    test('and a document environment in a comment is not one', () {
      expect(elements('% \\begin{document}\nWords.\n'), [('p', 'Words.')]);
    });

    test('a blank line parts two paragraphs, and a line end does not', () {
      expect(elements('one\ntwo\n\n  \nthree\n'), [
        ('p', 'one\ntwo'),
        ('p', 'three'),
      ]);
    });

    test('and a paragraph takes the spaces ending its last line', () {
      expect(elements('one  \n\ntwo'), [('p', 'one  '), ('p', 'two')]);
    });

    test('a sectioning command is a heading over its argument', () {
      expect(
        elements('\\section{One}\n\\subsection*{Two}\n\\paragraph[x]{Four}\n'),
        [
          ('h1', '\\section{One}'),
          ('h2', '\\subsection*{Two}'),
          ('h4', '\\paragraph[x]{Four}'),
        ],
      );
    });

    test('and a heading ends the paragraph before it', () {
      expect(elements('words\n\\section{One}\nmore\n'), [
        ('p', 'words'),
        ('h1', '\\section{One}'),
        ('p', 'more'),
      ]);
    });

    test('a command wrapping its argument is an inline element', () {
      expect(elements('a \\emph{b} \\textbf{c} \\texttt{d} e'), [
        ('p', 'a \\emph{b} \\textbf{c} \\texttt{d} e'),
        ('em', '\\emph{b}'),
        ('strong', '\\textbf{c}'),
        ('code', '\\texttt{d}'),
      ]);
    });

    test('and a declaration sets the rest of its group', () {
      expect(elements('a {\\bf b \\em c} d'), [
        ('p', 'a {\\bf b \\em c} d'),
        ('strong', '\\bf b \\em c}'),
        ('em', '\\em c}'),
      ]);
      expect(shown('a {\\bf b} d'), 'a b d');
    });

    test('a blank line closes a group left open', () {
      expect(elements('a \\emph{b\n\nc} d\n'), [
        ('p', 'a \\emph{b'),
        ('em', '\\emph{b'),
        ('p', 'c} d'),
      ]);
    });

    test('lists are lists of items, and a description of terms', () {
      expect(
        elements(
          '\\begin{itemize}\n\\item one\n\\item[*] two\n\\end{itemize}\n',
        ),
        [
          ('ul', '\\begin{itemize}\n\\item one\n\\item[*] two\n\\end{itemize}'),
          ('li', '\\item one'),
          ('li', '\\item[*] two'),
        ],
      );
      expect(
        elements(
          '\\begin{description}\n\\item[A \\emph{term}] its words\n'
          '\\end{description}\n',
        ),
        [
          (
            'dl',
            '\\begin{description}\n\\item[A \\emph{term}] its words\n'
                '\\end{description}',
          ),
          ('dt', '\\item[A \\emph{term}]'),
          ('em', '\\emph{term}'),
          ('dd', ' its words'),
        ],
      );
    });

    test('and lists nest', () {
      final found = elements(
        '\\begin{enumerate}\n\\item a\n\\begin{itemize}\n\\item b\n'
        '\\end{itemize}\n\\item c\n\\end{enumerate}\n',
      );
      expect(
        [for (final (name, _) in found) name],
        ['ol', 'li', 'ul', 'li', 'li'],
      );
      expect(found[4], ('li', '\\item c'));
    });

    test('an item no list holds ends at a blank line', () {
      expect(elements('\\item a\n\nb\n'), [('li', '\\item a'), ('p', 'b')]);
    });

    test('an environment nothing here knows is a division of its class', () {
      expect(
        said(
          named('\\begin{theorem}[Name]\nWords.\n\\end{theorem}', 'div').single,
          'class',
        ),
        'theorem',
      );
      expect(
        elements('\\begin{quote}\nx\n\\end{quote}').first.$1,
        'blockquote',
      );
    });

    test('and an end with nothing open is syntax', () {
      expect(elements('\\end{itemize}\nx\n'), [('p', 'x')]);
    });

    test('verbatim words are read as they stand', () {
      expect(
        elements(
          '\\begin{verbatim}\n\\emph{not} \$read\$\n\n\\end{verbatim}\nafter\n',
        ),
        [
          ('pre', '\\begin{verbatim}\n\\emph{not} \$read\$\n\n\\end{verbatim}'),
          ('p', 'after'),
        ],
      );
    });

    test('a TikZ picture is read whole, options and all', () {
      expect(
        elements(
          '\\begin{tikzpicture}[box/.style={draw}]\n'
          '\\node[box] (a) {\$x\$};\n\\end{tikzpicture}\nafter\n',
        ),
        [
          (
            'tikzpicture',
            '\\begin{tikzpicture}[box/.style={draw}]\n'
                '\\node[box] (a) {\$x\$};\n\\end{tikzpicture}',
          ),
          ('p', 'after'),
        ],
      );
    });

    test('an inline TikZ picture is read whole, in its line', () {
      expect(
        elements(
          'Before \\tikz[baseline]{\\draw (0,0) -- (1,0);} and '
          '\\tikz \\fill (0,0) circle (1pt); after.\n',
        ),
        [
          (
            'p',
            'Before \\tikz[baseline]{\\draw (0,0) -- (1,0);} and '
                '\\tikz \\fill (0,0) circle (1pt); after.',
          ),
          ('tikz', '\\tikz[baseline]{\\draw (0,0) -- (1,0);}'),
          ('tikz', '\\tikz \\fill (0,0) circle (1pt);'),
        ],
      );
    });

    test('a tabular is a table of rows and cells', () {
      expect(
        elements(
          '\\begin{tabular}{ll}\na & \\textbf{b} \\\\\nc & d\n\\end{tabular}',
        ),
        [
          (
            'table',
            '\\begin{tabular}{ll}\na & \\textbf{b} \\\\\nc & d\n\\end{tabular}',
          ),
          ('tr', 'a & \\textbf{b} \\\\'),
          ('td', 'a &'),
          ('td', ' \\textbf{b} '),
          ('strong', '\\textbf{b}'),
          ('tr', 'c & d'),
          ('td', 'c &'),
          ('td', ' d'),
        ],
      );
    });

    test('and its rules are asked for by the rows beside them', () {
      final rows = [
        for (final row in named(
          '\\begin{tabular}{ll}\n\\toprule\na & b \\\\\n\\midrule\n'
              'c & d \\\\\ne & f \\\\\n\\bottomrule\n\\end{tabular}',
          'tr',
        ))
          (said(row, 'above'), said(row, 'below')),
      ];
      expect(rows, [('heavy', 'light'), (null, null), (null, 'heavy')]);
    });

    test('and a cell spread across columns says how many', () {
      const text =
          '\\begin{tabular}{lll}\n\\multicolumn{2}{c}{Both} & c \\\\\n'
          '\\end{tabular}';
      final cell = named(text, 'td').first;
      expect(said(cell, 'colspan'), '2');
      expect(inside(text, cell).trim(), 'Both');
    });

    test('a command nothing here knows is an element of its own name', () {
      expect(elements('\\venue{\\hall{A}\\town{B}} and \\event[x]{one}{two}'), [
        ('p', '\\venue{\\hall{A}\\town{B}} and \\event[x]{one}{two}'),
        ('venue', '\\venue{\\hall{A}\\town{B}}'),
        ('hall', '\\hall{A}'),
        ('town', '\\town{B}'),
        ('event', '\\event[x]{one}{two}'),
      ]);
      expect(shown('\\event[x]{one}{two}'), 'one two');
    });

    test('and in the preamble too, where a definition still shows nothing', () {
      const text =
          '\\documentclass{article}\n\\venue{cc}\n'
          '\\def\\x{junk}\n\\begin{document}\nWords.\n\\end{document}\n';
      expect(elements(text)[1], ('venue', '\\venue{cc}'));
      expect(shown(text), isNot(contains('junk')));
      expect(shown(text), contains('cc'));
    });

    test('a bibliography is a list of its entries, each with its key', () {
      const text =
          '\\begin{thebibliography}{2}\n'
          '\\providecommand\\bibinfo[2]{#2}\n'
          '\\def \\showURL #1{#1}\n'
          '\\bibitem{one} A. Writer. \\emph{First}. 2020.\n'
          '\\bibitem[Reader(2021)]%\n        {two}\n'
          '\\bibfield{author}{\\bibinfo{person}{B. Reader}}.\n'
          '\\newblock \\bibinfo{title}{Second}.\n'
          '\\end{thebibliography}\n';
      final list = named(text, 'ol').single;
      final entries = named(text, 'li');
      expect(said(list, 'class'), 'thebibliography');
      expect([for (final one in entries) said(one, 'id')], ['one', 'two']);
      expect(inside(text, entries.first).trim(), 'A. Writer. First. 2020.');
      expect(
        inside(text, entries.last).split(RegExp(r'\s+')).join(' ').trim(),
        'B. Reader. Second.',
      );
      expect(
        [for (final one in named(text, 'bibinfo')) said(one, 'field')],
        ['person', 'title'],
      );
      expect(inside(text, list), isNot(contains('#')));
    });

    test('mathematics is TeX, inline and displayed', () {
      expect(elements(r'a $x^2$ and \(y\) b'), [
        ('p', r'a $x^2$ and \(y\) b'),
        ('math', r'$x^2$'),
        ('math', r'\(y\)'),
      ]);
      expect(elements('a\n\\[ x = 1 \\]\nb\n'), [
        ('p', 'a'),
        ('equation', r'\[ x = 1 \]'),
        ('p', 'b'),
      ]);
      expect(elements('\\begin{align}\nx &= 1 \\\\\n\\end{align}'), [
        ('equation', '\\begin{align}\nx &= 1 \\\\\n\\end{align}'),
      ]);
    });

    test('and a blank line ends the search for its close', () {
      // A backslash ending a line does not hide the blank line after it.
      expect(named('a \$b\\\n\nc\$ d', 'math'), isEmpty);
      expect([
        for (final (name, covered) in elements('a \\foo[b\\\n\nc]{d}'))
          if (name == 'foo') covered,
      ], isNot(contains(contains('d'))));
    });

    test('and a dollar never closed is syntax', () {
      expect(shown(r'costs $5'), 'costs 5');
    });

    test('a link carries its address', () {
      expect(
        [
          for (final link in named(
            r'\url{http://a.b/c\_d} and \href{http://e.f}{there}',
            'a',
          ))
            said(link, 'href'),
        ],
        ['http://a.b/c_d', 'http://e.f'],
      );
      expect(shown(r'\href{http://e.f}{there}'), 'there');
    });

    test('a key is shown as it stands', () {
      expect(
        shown(r'see \cite[p.~2]{knuth} and \ref{one}'),
        'see [knuth] and one',
      );
    });

    test('escapes, symbols, accents and ligatures show what they mean', () {
      expect(shown(r'50\% \& \$ \{x\}'), r'50% & $ {x}');
      expect(shown(r'\LaTeX{} \ldots \S'), 'LaTeX … §');
      expect(
        shown('caf\\\'e na\\"ive \\c{c}'),
        'cafe\u0301 nai\u0308ve c\u0327',
      );
      expect(shown("a -- b --- c ``d'' e~f"), 'a – b — c “d” e\u00A0f');
    });

    test('a line break is its own element', () {
      expect(elements(r'a\\b'), [('p', r'a\\b'), ('br', r'\\')]);
    });

    test('a comment and a command nothing here knows show nothing', () {
      expect(shown('a % note\nb \\foo[x]{c}'), 'a b c');
    });
  });

  group('What LaTeX passes over', () {
    test('a comment environment is a comment, blank lines and all', () {
      const text =
          'a\n\\begin{comment}\nx \\textbf{y}\n\nz\n\\end{comment}\nb\n';
      expect(shown(text), 'a\n\nb\n');
      expect(
        [
          for (final (name, covered) in tokens(read(text)))
            if (name == '#comment') covered,
        ],
        ['\\begin{comment}\nx \\textbf{y}\n\nz\n\\end{comment}'],
      );
    });

    test('and so is what stands between iffalse and its fi', () {
      const text = 'a \\iffalse x \\ifx y\\fi z \\fi b\n';
      expect(shown(text), 'a  b\n');
      expect(named(text, 'strong'), isEmpty);
    });
  });

  group('What acmart and graphicx write', () {
    test('a CCSXML block is a comment, as acmart reads it', () {
      const text =
          'a\n\\begin{CCSXML}\n<ccs2012>x</ccs2012>\n\\end{CCSXML}\nb\n';
      expect(shown(text), 'a\n\nb\n');
    });

    test('a picture is an img over its command, saying its file', () {
      const text = 'a \\includegraphics[width=0.9\\textwidth]{fig/x.png} b\n';
      final pictures = named(text, 'img');
      expect(pictures, hasLength(1));
      expect(said(pictures.single, 'src'), 'fig/x.png');
      expect(shown(text), 'a  b\n');
    });

    test('front matter is read as what it is', () {
      const text =
          '\\documentclass{acmart}\n\\author{A B}\n'
          '\\authornote{While at C.}\n'
          '\\affiliation{\\institution{C}\\city{Paris}\\country{France}}\n'
          '\\email{a@c.eu}\n\\setcopyright{cc}\n\\acmDOI{10.1/2}\n'
          '\\acmConference[D]{Doc}{Aug}{Fribourg}\n'
          '\\begin{document}\n\\ccsdesc[500]{Software~tools}\n'
          '\\keywords{graphs, docs}\n\\maketitle\nWords.\n\\end{document}\n';
      final found = {
        for (final (name, covered) in elements(text)) covered: name,
      };
      expect(found['\\authornote{While at C.}'], 'footnote');
      expect(
        found['\\affiliation{\\institution{C}\\city{Paris}\\country{France}}'],
        'address',
      );
      expect(found['\\city{Paris}'], 'span');
      expect(found['\\email{a@c.eu}'], 'a');
      expect(said(named(text, 'a').single, 'href'), 'mailto:a@c.eu');
      expect(found['\\ccsdesc[500]{Software~tools}'], 'div');
      expect(found['\\keywords{graphs, docs}'], 'div');
      expect(
        [for (final element in named(text, 'div')) said(element, 'class')],
        ['ccsdesc', 'keywords'],
      );
      expect(shown(text), isNot(contains('10.1/2')));
      expect(shown(text), isNot(contains('Fribourg')));
      expect(named(text, 'acmDOI'), isEmpty);
    });

    test('a label is an anchor, and a reference a link to it', () {
      const text =
          'See~\\ref{fig:a}.\n\\begin{figure}\\caption{X}\\label{fig:a}\\end{figure}\n';
      final links = named(text, 'a');
      expect([for (final link in links) said(link, 'href')], ['#fig:a', null]);
      expect([for (final link in links) said(link, 'id')], [null, 'fig:a']);
      expect(shown(text), contains('See\u00a0fig:a.'));
    });

    test('an equation says which environment it is and what labels it', () {
      // So a sheet numbers the environments LaTeX numbers, and a reference
      // reaches the equation its label is written inside.
      const text =
          '\\begin{equation}\na = b \\label{eq:one}\n\\end{equation}\n'
          '\\begin{align*}\np &= q\n\\end{align*}\n'
          '\\[ c = d \\]\n';
      final equations = named(text, 'equation');
      expect(
        [for (final one in equations) said(one, 'env')],
        ['equation', 'align*', null],
      );
      expect(
        [for (final one in equations) said(one, 'label')],
        ['eq:one', null, null],
      );
    });

    test('an equation reference says it is one', () {
      final links = named('See \\eqref{eq:one}.\n', 'a');
      expect([for (final link in links) said(link, 'href')], ['#eq:one']);
      expect([for (final link in links) said(link, 'class')], ['ref eqref']);
    });

    test('a reference says it is one, and another link does not', () {
      const text =
          '\\ref{a} \\pageref{b} \\autoref{c} '
          '\\href{https://example.com}{site} \\url{https://example.com}\n';
      final links = named(text, 'a');
      expect(
        [for (final link in links) said(link, 'href')],
        ['#a', '#b', '#c', 'https://example.com', 'https://example.com'],
      );
      expect(
        [for (final link in links) said(link, 'class')],
        ['ref', 'ref', 'ref', null, null],
      );
    });

    test('the arguments of a command it does not know stand apart', () {
      expect(shown(r'\venue{Paris}{2026}'), 'Paris 2026');
    });
  });

  group('A command defined as words', () {
    const head =
        '\\documentclass{article}\n\\newcommand{\\lib}{libara}\n'
        '\\newcommand\\fmt{formats}\n\\newcommand{\\two}[1]{x #1}\n'
        '\\begin{document}\n';

    test('shows them where it is used', () {
      const text = '$head\\lib{} and \\fmt here\n\\end{document}\n';
      expect(shown(text), contains('libara and formatshere'));
    });

    test('and a command taking arguments is left as it was', () {
      const text = '$head\\two{y}\n\\end{document}\n';
      expect(named(text, 'two'), hasLength(1));
    });

    test('and after a keystroke that reads only a window', () {
      final text =
          '$head${'words\n\n' * 400}use \\lib here\n\n${'more\n\n' * 400}\\end{document}\n';
      final document = edited(
        latex,
        read(text),
        Edit(1, Insert(text.lastIndexOf('here'), Text.of('x'))),
      );
      expect([
        for (final token in document.layer(2).items.cast<ARange>())
          if (said(token, 'shows') == 'libara') token,
      ], hasLength(1));
    });

    test('and a definition changed reads again what uses it', () {
      final text =
          '$head${'words\n\n' * 400}use \\lib here\n\n${'more\n\n' * 400}\\end{document}\n';
      final at = text.indexOf('libara');
      edited(
        latex,
        read(text),
        Edit(1, Replace(value(Range.create(at, 6)), Text.of('other'))),
      );
    });
  });

  group('Re-reading after a keystroke', () {
    const paper =
        '\\documentclass{article}\n\\title{T}\n\n\\usepackage{x}\n\n'
        '\\begin{document}\nOne \\emph{a}.\n\nTwo {\\bf b} c.\n\n'
        '\\begin{itemize}\n\\item x\n\n\\item y\n\\end{itemize}\n\n'
        'Three \$m\$.\n\nFour.\n\\end{document}\n';

    test('a keystroke in the body reads what a fresh read does', () {
      edited(
        latex,
        read(paper),
        Edit(1, Insert(paper.indexOf('Two'), Text.of('x'))),
      );
    });

    test('a paragraph takes a character typed at its head', () {
      const text =
          '\\documentclass{article}\n\\begin{document}\nthe words\n'
          '\\end{document}\n';
      final document = edited(
        latex,
        read(text),
        Edit(1, Insert(text.indexOf('the'), Text.of('X'))),
      );
      expect(
        [
          for (final (element, covered) in covering(document))
            if (said(element, '') == 'p') covered,
        ],
        ['Xthe words'],
      );
    });

    test('a keystroke near the end of the document reads only its window', () {
      final text =
          '\\documentclass{article}\n\\begin{document}\n\n'
          '${'words\n\n' * 400}\\end{document}\n';
      final document = read(text);
      final window = document.grammar.affected(
        document,
        2,
        value(Range.create(text.lastIndexOf('words'), 1)),
      );
      expect(window.length, lessThan(text.length ~/ 10));
    });

    test('a verbatim begun by a keystroke runs past the window', () {
      const text = 'One.\n\nTwo.\n\nThree.\n\nFour.\n';
      edited(
        latex,
        read(text),
        Edit(1, Insert(text.indexOf('Two'), Text.of('\\begin{verbatim}\n'))),
      );
    });

    test('a line taken away leaves a blank line first', () {
      const text = 'One.\n\nTwo.\n\nThree.\n';
      edited(latex, read(text), Edit(1, Delete(value(Range.create(0, 5)))));
    });

    test('an environment whose end is taken away runs on', () {
      const text = 'One.\n\n\\begin{quote}\nx\n\n\\end{quote}\n\nTwo.\n';
      edited(
        latex,
        read(text),
        Edit(
          1,
          Delete(
            value(Range.create(text.indexOf('\\end'), '\\end{quote}\n'.length)),
          ),
        ),
      );
    });

    test('an environment closed by a keystroke ends there', () {
      const text =
          'One.\n\n\\begin{quote}\nx\n\n\\end{quote}\n\nTwo.\n\nThree.\n';
      edited(
        latex,
        read(text),
        Edit(1, Insert(text.indexOf('x'), Text.of('\\end{quote}\n'))),
      );
    });

    test('the document unbegun by a keystroke reads the whole', () {
      const text =
          '\\documentclass{article}\n\nA.\n\n\\begin{document}\nB.\n\nC.\n';
      edited(
        latex,
        read(text),
        Edit(
          1,
          Delete(
            value(
              Range.create(
                text.indexOf('\\begin'),
                '\\begin{document}\n'.length,
              ),
            ),
          ),
        ),
      );
    });

    test('and one taken away from below blank lines', () {
      // Nothing spans the blank lines before the document, but the words
      // above them are the preamble's only while it follows.
      const text =
          '\\documentclass{article}\n\\usepackage{x\\section{y}\n\n\n'
          '\\begin{document}\n\n\nA\n\n\\end{document}\n';
      // The edit renaming the document strong: the backslash both
      // forms begin with stays.
      final at = text.indexOf('\\begin');
      edited(
        latex,
        read(text),
        Edit(
          1,
          Replace(
            value(Range.create(at + 1, text.length - 2 - at)),
            Text.of('textbf{\n\n\nA\n\n}'),
          ),
        ),
      );
    });

    test('and one after the end of the document', () {
      const text =
          '\\begin{document}\nOne.\n\\end{document}\n\nafter\n\nmore\n';
      edited(
        latex,
        read(text),
        Edit(1, Insert(text.indexOf('more') - 1, Text.of('\n\n'))),
      );
    });

    test('a heading taken away from below an item no list holds', () {
      const text = 'One.\n\n\\item a\n\n\n\n\\section{B}\n\nc\n\nd\n';
      final at = text.indexOf('\\section');
      edited(
        latex,
        read(text),
        Edit(
          1,
          Replace(value(Range.create(at, '\\section{B}'.length)), Text.of('B')),
        ),
      );
    });

    test('a command taken away from before blank lines', () {
      const text = '\\emph{\n\n\nx\n\ny\n';
      edited(
        latex,
        read(text),
        Edit(1, Delete(value(Range.create(0, '\\emph{'.length)))),
      );
    });

    test('a verbatim holding the only document taken away', () {
      // The preamble ran to the end, since no document began outside the
      // verbatim; once it goes, there is no preamble at all.
      const text =
          '\\documentclass{x}\n\n\\usepackage{y}\n\n'
          '\\begin{verbatim}\n\\begin{document}\n'
          '\\end{verbatim}\n\nA\n\nB\n';
      final at = text.indexOf('\\begin{verbatim}');
      edited(
        latex,
        read(text),
        Edit(1, Delete(value(Range.create(at, text.indexOf('A') - 2 - at)))),
      );
    });

    test('a keystroke in a preamble that runs to the document', () {
      // The stretch first read, 1,024 past the keystroke, ends a few
      // characters into the document's beginning, which says the
      // preamble's words show nothing.
      const head = '\\documentclass{x}\n\\usepackage{y}\n\nwords\n\n%';
      final at = head.indexOf('\n\n');
      final text =
          '$head${'x' * (at + 6 + 1024 - 5 - 6 - head.length - 2)}\n\n'
          '\\begin{document}\nA\n\\end{document}\n';
      edited(latex, read(text), Edit(1, Insert(at, Text.of('\\item '))));
    });

    test('and one in the preamble', () {
      edited(
        latex,
        read(paper),
        Edit(1, Insert(paper.indexOf('usepackage'), Text.of('x'))),
      );
    });

    test('a group opened by a keystroke closes at the blank line', () {
      edited(
        latex,
        read(paper),
        Edit(1, Insert(paper.indexOf('Two'), Text.of('\\emph{'))),
      );
    });

    test('an environment begun by a keystroke reaches past the window', () {
      edited(
        latex,
        read(paper),
        Edit(1, Insert(paper.indexOf('Three'), Text.of('\\begin{quote}\n'))),
      );
    });

    test('the document begun by a keystroke reads the whole', () {
      const text = 'One.\n\nTwo.\n\nThree.\n';
      final document = edited(
        latex,
        read(text),
        Edit(1, Insert(text.indexOf('Two'), Text.of('\\begin{document}\n'))),
      );
      expect(
        covering(document).map((one) => said(one.$1, '')),
        contains('preamble'),
      );
    });

    for (final name in ['codens', 'maltese', 'review', 'stopping']) {
      test('editing $name.tex at random derives what a fresh read does', () {
        final text = File('test/samples/$name.tex').readAsStringSync();
        roundtrip(latex, text);
        derivable(latex, text, seed: name.hashCode, edits: 150);
      });
    }
  });
}
