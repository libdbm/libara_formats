import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// Writing a document as LaTeX: ported from the written cases of
/// markwrite's `latex_lex_test`.
void main() {
  const latex = LaTeX();
  const markdown = Markdown();

  group('A link written as latex', () {
    /// The names a fresh read of [text], read as XML and written as latex,
    /// finds.
    Set<String> names(String text) => {
      for (final (element, _) in covering(
        decoded(latex, string(value(latex.encode(decoded(const XML(), text))))),
      ))
        '${element.get('')}',
    };

    test('says nothing its address holds', () {
      final plain = names('<p><a href="x">t</a></p>');
      for (final href in [
        r'x}\textbf{y}',
        r'x\fBy\fR',
        'x\n.SH Y',
        'x\n\nY',
        'x" \\fBy',
      ]) {
        expect(
          names('<p><a href="${escaped(href)}">t</a></p>'),
          plain,
          reason: href,
        );
      }
    });
  });

  group('A LaTeX document written', () {
    test('from Markdown', () {
      expect(
        string(
          value(
            latex.encode(
              decoded(
                markdown,
                '# Title\n\nOne *two* and `x_y`.\n\n- a\n- b\n',
              ),
            ),
          ),
        ),
        '\\documentclass{article}\n\\begin{document}\n'
        '\\section{Title}\n\nOne \\emph{two} and \\texttt{x\\_y}.\n\n'
        '\\begin{itemize}\n\\item a\n\\item b\n\\end{itemize}\n'
        '\\end{document}\n',
      );
    });

    test('reads back as what it was written from', () {
      final written = string(
        value(
          latex.encode(
            decoded(
              const XML(),
              '<d><h1>One</h1><p>Words <em>here</em> and <q>said</q>.</p>'
              '<blockquote><p>Quoted.</p></blockquote>'
              '<ol><li>a</li></ol><p><a href="http://x/a_b">link</a></p></d>',
            ),
          ),
        ),
      );
      expect({
        for (final (element, _) in covering(decoded(latex, written)))
          '${element.get('')}',
      }, containsAll(['h1', 'em', 'blockquote', 'ol', 'li', 'a', 'p']));
    });

    test('as itself is its text', () {
      const text =
          '\\documentclass{article}\n\\begin{document}\n'
          '\\section{One}\n\nWords \\emph{here} and \$x\$.\n\n'
          '\\begin{quote}\nQuoted.\n\\end{quote}\n\\end{document}\n';
      expect(string(value(latex.encode(decoded(latex, text)))), text);
    });

    test('and its mathematics refused where TeX has no representation', () {
      expect(
        const Man().encode(decoded(latex, r'a \(x\)')),
        isA<Failure<Sequence<int>>>()
            .having((failure) => failure.kind, 'kind', Kind.invalid)
            .having((failure) => failure.message, 'message', contains('TeX')),
      );
    });

    test('and a picture as graphicx includes one', () {
      final written = string(
        value(
          latex.encode(decoded(const XML(), '<d><img src="a/b.png"/></d>')),
        ),
      );
      expect(written, contains(r'\includegraphics{a/b.png}'));
      expect(
        latex.encode(decoded(const XML(), '<d><img src="a}b.png"/></d>')),
        isA<Failure<Sequence<int>>>(),
      );
    });

    test('and an anchor and a link to it as a label and a reference', () {
      final written = string(
        value(
          latex.encode(
            decoded(
              const HTML(),
              '<p><a id="s:x"></a>See <a href="#s:x">s:x</a>.</p>',
            ),
          ),
        ),
      );
      expect(written, contains(r'\label{s:x}'));
      expect(written, contains(r'See \ref{s:x}.'));
    });

    test('and a sixth heading as the fifth, the last LaTeX has', () {
      expect(
        string(value(latex.encode(decoded(const XML(), '<d><h6>x</h6></d>')))),
        contains(r'\subparagraph{x}'),
      );
    });

    test('and what has no LaTeX markup is refused', () {
      expect(
        latex.encode(
          decoded(const XML(), '<table><tr><td>x</td></tr></table>'),
        ),
        isA<Failure<Sequence<int>>>().having(
          (failure) => failure.message,
          'message',
          contains('table'),
        ),
      );
    });
  });

  test('A break written by a structural edit is two backslashes', () {
    final document = edited(
      latex,
      decoded(latex, 'a b'),
      Edit(2, Mark(Empty(1, 'br'))),
    );
    expect(string(document.items), r'a\\ b');
    expect([
      for (final (element, _) in covering(document)) said(element, ''),
    ], contains('br'));
  });
}

/// [text] as an XML attribute value holds it.
String escaped(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('\n', '&#10;');
