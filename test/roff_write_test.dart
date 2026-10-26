import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// Writing a document as a roff package: ported from markwrite's
/// `roff_emit_test`.
void main() {
  const man = Man();
  const html = HTML();
  const xml = XML();

  /// [text] read as [from] and written as [to].
  Result<Sequence<int>> converted(Syntax from, String text, Syntax to) =>
      to.encode(decoded(from, text));

  /// [text] read as [from] and written as [to], as text.
  String written(Syntax from, String text, Syntax to) =>
      string(value(converted(from, text, to)));

  /// That [text] read as [from] is refused as [to], saying [why].
  void refused(Syntax from, String text, Syntax to, String why) {
    expect(
      converted(from, text, to),
      isA<Failure<Sequence<int>>>()
          .having((failure) => failure.kind, 'kind', Kind.invalid)
          .having((failure) => failure.message, 'message', contains(why)),
    );
  }

  group('A link written as man', () {
    /// The names a fresh read of [text], read as XML and written as man,
    /// finds.
    Set<String> names(String text) => {
      for (final (element, _) in covering(
        decoded(man, string(value(man.encode(decoded(const XML(), text))))),
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

  group('Writing a document as a roff package', () {
    test('turns HTML into a manual page', () {
      expect(
        written(
          html,
          '<h1>NAME</h1><p>ls - list</p><h2>Options</h2>'
          '<p>a <em>b</em> <strong>c</strong> <code>d</code></p>'
          '<pre>raw\n.dot</pre><ul><li>one</li><li>two</li></ul>'
          '<ol><li>first</li></ol><blockquote><p>q</p></blockquote>',
          man,
        ),
        '.SH NAME\n.PP\nls - list\n.SS Options\n'
        '.PP\na \\fIb\\fP \\fBc\\fP \\fCd\\fP\n'
        '.nf\nraw\n\\&.dot\n.fi\n'
        '.IP \\(bu\none\n.IP \\(bu\ntwo\n.IP 1.\nfirst\n'
        '.RS\n.PP\nq\n.RE\n',
      );
    });

    test('and a manual page into HTML', () {
      expect(
        written(
          man,
          '.TH ls 1\n.SH NAME\nls \\- list\n.PP\na \\fBb\\fP \\(em c\n'
          '.TP\n.B \\-l\nlong\n',
          html,
        ),
        '<head name="ls" section="1"></head>\n<h1>NAME</h1>\n'
        '<p implied="">ls - list</p>\n<p>a <strong>b</strong> — c</p>\n'
        '<dt><strong>-l</strong></dt>\n<dd>long</dd>\n',
      );
    });

    test('and Markdown into an ms paper, and a me paper', () {
      const text = '# Intro\n\nSome *words* here.\n\n> quoted\n';
      expect(
        written(const Markdown(), text, const Ms()),
        '.NH 1\nIntro\n.PP\nSome \\fIwords\\fP here.\n.QS\n.PP\nquoted\n.QE\n',
      );
      expect(
        written(const Markdown(), text, const Me()),
        '.sh 1 Intro\n.pp\nSome \\fIwords\\fP here.\n.(q\n.pp\nquoted\n.)q\n',
      );
    });

    test('and a heading with a space in me is quoted, as me wants it', () {
      expect(
        written(html, '<h1>Two words</h1>', const Me()),
        '.sh 1 "Two words"',
      );
      expect(written(html, '<h1>Two words</h1>', man), '.SH Two words');
    });

    test('a term and its description come to a tagged paragraph', () {
      expect(
        written(html, '<dl><dt>-a</dt><dd>all</dd></dl>', man),
        '.TP\n-a\nall',
      );
      expect(
        written(html, '<dt>-a</dt><dd>all</dd>', const Ms()),
        '.IP -a\nall',
      );
    });

    test('a table as tbl writes one', () {
      const text =
          '<table><tr><th>a</th><th>b</th></tr>'
          '<tr><td>c</td><td><p>d</p><p>e</p></td></tr></table>';
      final table = written(html, text, man);
      expect(table, contains('.TS\nl l.\na\tb\n'));
      expect(table, contains('T{\n'));
      expect([
        for (final (element, covered) in covering(decoded(man, table)))
          if (said(element, '') == 'td') covered,
      ], hasLength(4));
    });

    test('and what has no representation is said to have none', () {
      refused(html, '<p><img src="x.png"></p>', man, 'img');
      refused(xml, '<p><math>x^2</math></p>', man, 'TeX');
    });

    test('and an equation in eqn is written back as one', () {
      expect(
        written(
          xml,
          '<equation notation="eqn">x sup 2</equation>'
          '<p>let <math notation="eqn">a over b</math> be</p>',
          man,
        ),
        '.EQ\ndelim \$\$\n.EN\n.EQ\nx sup 2\n.EN\n.PP\nlet \$a over b\$ be',
      );
    });

    test('and what would read as syntax is escaped', () {
      final text = written(
        xml,
        '<p>a \\ b</p><p>.dot first</p><p>\'quote first</p>'
        '<p>caf\u00e9 \u2014 \u4e2d</p>',
        man,
      );
      expect(
        text,
        '.PP\na \\e b\n.PP\n\\&.dot first\n.PP\n\\&\'quote first\n'
        '.PP\ncaf\\(\'e \\(em \\[u4E2D]',
      );
      final shown = [
        for (final (_, token) in decoded(man, text).markers(2))
          if (said(token, '') == '#text')
            string(decoded(man, text).slice(token))
          else
            token.get('shows')?.toString() ?? '',
      ].join();
      expect(shown, contains('caf\u00e9 \u2014 \u4e2d'));
      expect(shown, contains('.dot first'));
      expect(shown, contains('a \\ b'));
    });

    test('and a face inside another closes back to it by name', () {
      expect(
        written(html, '<p><i>a <b>b</b> c</i> d</p>', man),
        '.PP\n\\fIa \\fBb\\fP c\\fR d',
      );
      expect(
        written(html, '<p><i>a <b>b <code>c</code> d</b> e</i> f</p>', man),
        '.PP\n\\fIa \\fBb \\fCc\\fP d\\fI e\\fR f',
      );
    });

    test('and a comment is a comment, and a quotation its quotes', () {
      expect(
        written(xml, '<p>x<comment>why</comment></p>', man),
        '.PP\nx\n.\\" why\n',
      );
      expect(
        written(xml, '<p><q>said</q></p>', const Me()),
        '.pp\n\\(lqsaid\\(rq',
      );
    });

    test('and a page written as itself is its text', () {
      const text = '.TH ls 1\n.SH NAME\nls \\- list\n.nr X 1\n.PP\na\n\nb\n';
      expect(written(man, text, man), text);
    });
  });

  group('Reading faces', () {
    test('the previous face is what roff makes of it', () {
      // \fP brings back the face before the last change, and the change to
      // it is a change too: after \fI \fB \fP \fP the face is bold.
      const text = '.PP\n\\fIa \\fBb\\fP c\\fP d\n';
      expect(
        [
          for (final (element, covered) in covering(decoded(man, text)))
            (said(element, ''), covered),
        ],
        [
          ('p', '.PP\n\\fIa \\fBb\\fP c\\fP d'),
          ('em', '\\fIa '),
          ('strong', '\\fBb\\fP'),
          ('em', ' c\\fP'),
          ('strong', ' d'),
        ],
      );
    });
  });

  group('A break written by a structural edit', () {
    test('is a request on a line of its own, which a fresh read finds', () {
      final document = edited(
        man,
        decoded(man, '.PP\na b\n'),
        Edit(2, Mark(Empty(5, 'br'))),
      );
      expect(string(document.items), '.PP\na\n.br\n b\n');
      expect([
        for (final (element, _) in covering(document)) said(element, ''),
      ], contains('br'));
    });
  });
}

/// [text] as an XML attribute value holds it.
String escaped(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('\n', '&#10;');
