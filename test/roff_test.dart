import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// roff's core, read through the man package: requests and escapes are
/// tokens named for the element they represent, and eqn's equations and the
/// formulae its delimiters mark are elements.
void main() {
  const man = Man();

  Layered<int> read(String text) => decoded(man, text);

  /// The elements of [text] called [name], each with the text it covers.
  List<(ARange, String)> named(String text, String name) => [
    for (final (element, covered) in covering(read(text)))
      if (said(element, '') == name) (element, covered),
  ];

  group('An equation in a roff document', () {
    test('is a block that says it is eqn, with its label', () {
      final (equation, text) = named(
        '.EQ (1)\nx sup 2\n.EN\n.PP\ny\n',
        'equation',
      ).single;
      expect(said(equation, 'notation'), 'eqn');
      expect(said(equation, 'id'), '(1)');
      expect(text, '.EQ (1)\nx sup 2\n.EN\n');
    });

    test('and delim makes a formula of what stands between its characters', () {
      const text = '.EQ\ndelim \$\$\n.EN\n.PP\nlet \$x sup 2\$ be \$y\$ now\n';
      final maths = named(text, 'math');
      expect(maths, hasLength(2));
      expect(said(maths.first.$1, 'notation'), 'eqn');
      expect(maths.first.$2, '\$x sup 2\$');
      // The delim line is syntax, saying what it sets.
      final delim = read(text)
          .layer(2)
          .items
          .cast<ARange>()
          .firstWhere((token) => said(token, 'delim') != null);
      expect(said(delim, ''), '#pi');
      expect(said(delim, 'delim'), '\$\$');
    });

    test('and delim off ends that, so a dollar is a dollar again', () {
      expect(
        named(
          '.EQ\ndelim \$\$\n.EN\n.EQ\ndelim off\n.EN\n.PP\ncost \$5 or \$6\n',
          'math',
        ),
        isEmpty,
      );
    });

    test('and a delimiter never closed on its line is a character', () {
      expect(named('.EQ\ndelim @@\n.EN\n.PP\nat @ home\n', 'math'), isEmpty);
    });

    test('and a delim line outside an equation is words', () {
      expect(named('.PP\ndelim \$\$\nwords \$a\$ here\n', 'math'), isEmpty);
    });
  });

  group('Requests and escapes', () {
    test('a heading is its request and its words', () {
      final document = read('.SH NAME\nls \\- list\n');
      expect(tokens(document).take(2), [('h1', '.SH '), ('#text', 'NAME')]);
      expect(named('.SH NAME\nls \\- list\n', 'h1').single.$2, '.SH NAME');
      final escape = document
          .layer(2)
          .items
          .cast<ARange>()
          .firstWhere((token) => said(token, '') == '#escape');
      expect(said(escape, 'shows'), '-');
    });

    test('a paragraph no request opens is implied', () {
      final (paragraph, text) = named('words here\n', 'p').single;
      expect(text, 'words here');
      expect(said(paragraph, 'implied'), '');
    });

    test('a face opens at its escape and closes at the one that ends it', () {
      const text = '.PP\none \\fBtwo\\fP three\n';
      expect(named(text, 'strong').single.$2, '\\fBtwo\\fP');
      final faces = [
        for (final (name, covered) in tokens(read(text)))
          if (name == 'strong') covered,
      ];
      expect(faces, ['\\fB', '\\fP']);
    });

    test('a glyph shows its character, and an unknown request nothing', () {
      final document = read('.PP\n\\(em\n.xx unknown\n');
      final glyph = document
          .layer(2)
          .items
          .cast<ARange>()
          .firstWhere((token) => said(token, '') == '#escape');
      expect(said(glyph, 'shows'), '—');
      expect(tokens(document), contains(('#pi', '.xx unknown\n')));
    });

    test('a comment is a comment', () {
      expect(tokens(read('.\\" a note\n.PP\nx\n')).first, (
        '#comment',
        '.\\" a note\n',
      ));
    });
  });

  group('Re-reading after a keystroke', () {
    test('a keystroke in words reads what a fresh read does', () {
      const text = '.SH ONE\n.PP\nwords here and there\n.SH TWO\n.PP\nmore\n';
      edited(
        man,
        read(text),
        Edit(1, Insert(text.indexOf('here'), Text.of('x'))),
      );
    });

    test('with delimiters set, a keystroke reads them still', () {
      const text = '.EQ\ndelim @@\n.EN\n.SH A\n.PP\nwords @x@ here\n';
      final document = edited(
        man,
        read(text),
        Edit(1, Insert(text.indexOf('here'), Text.of('@y@ '))),
      );
      expect(
        covering(document).where((one) => said(one.$1, '') == 'math'),
        hasLength(2),
      );
    });

    test('an edit that writes a delim line has the whole page read', () {
      const text = '.EQ\nx\n.EN\n.SH A\n.PP\nwords \$a\$ here\n';
      final document = edited(
        man,
        read(text),
        Edit(
          1,
          Replace(
            value(Range.create(text.indexOf('x\n'), 1)),
            Text.of('delim \$\$'),
          ),
        ),
      );
      expect(
        covering(document).where((one) => said(one.$1, '') == 'math'),
        hasLength(1),
      );
    });

    test('taking the delim line away reads its formulas as words', () {
      final text = '.EQ\ndelim @@\n.EN\n${'.PP\nwords @x@ here\n' * 50}';
      edited(
        man,
        read(text),
        Edit(1, Delete(value(Range.create(4, 'delim @@\n'.length)))),
      );
    });

    test('once its delim line is gone, a keystroke reads only its window', () {
      final text = '.EQ\ndelim @@\n.EN\n${'.PP\nwords here\n' * 200}';
      final document = edited(
        man,
        read(text),
        Edit(1, Delete(value(Range.create(4, 'delim @@\n'.length)))),
      );
      final at = string(document.items).lastIndexOf('here');
      final window = document.grammar.affected(
        document,
        2,
        value(Range.create(at, 1)),
      );
      expect(window.length, lessThan(document.items.length ~/ 10));
    });

    test('a face roff does not set changes nothing \\fP brings back', () {
      const text = '.PP\n\\fBbold\\fR plain\n.SH A\n.PP\nx \\fIy\\fP z\n';
      edited(
        man,
        read(text),
        Edit(
          1,
          Replace(
            value(Range.create(text.indexOf('fIy') + 1, 1)),
            Text.of('H'),
          ),
        ),
      );
    });

    test(
      'a face changed before a heading is what \\fP after it brings back',
      () {
        const text = '.SH A\n.PP\nw\n.SH B\n.PP\n\\fPx\n';
        final document = edited(
          man,
          read(text),
          Edit(1, Insert(text.indexOf('w'), Text.of('\\fBb\\fR '))),
        );
        expect(
          covering(document).where((one) => said(one.$1, '') == 'strong'),
          hasLength(2),
        );
      },
    );

    test('a container left open reaches past the paragraphs after it', () {
      const text = '.PP\na\n.nf\ncode\n.fi\n.PP\nwords\n.PP\nmore\n';
      final document = edited(
        man,
        read(text),
        Edit(1, Insert(text.indexOf('fi'), Text.of('n'))),
      );
      expect(
        covering(document).where((one) => said(one.$1, '') == 'pre').single.$2,
        endsWith('more'),
      );
    });

    test('a face brought back from before the heading is read so', () {
      const text = '.PP\n\\fBbold\\fR plain\n.SH A\n.PP\nx \\fPback\n';
      edited(
        man,
        read(text),
        Edit(1, Insert(text.indexOf('x '), Text.of('y'))),
      );
    });
  });

  test('a heading waiting for its words, closed by a request first', () {
    expect(named('.SH\n.RS\n.RE\nwords\n', 'p').single.$2, 'words');
  });

  test('editing a dense page at random reads what a fresh read does', () {
    // The seeds random editing first caught the window out with, among
    // them a face brought back on a heading's own line.
    for (final seed in [114, 118, 227, 280, 322, 360]) {
      derivable(man, dense * 3, seed: seed, edits: 150);
    }
  });

  test('every page round-trips', () {
    for (final text in [
      '.TH LS 1\n.SH NAME\nls \\- list\n.PP\none \\fBtwo\\fP \\(em three\n',
      '.TP\n.B \\-l\nlong form\n.IP \\(bu\nitem\n.\\" note\nplain words here\n',
      '.de XX\n.SH inside\n..\n.if n \\{\\\n.SH no\n.\\}\nafter\n',
    ]) {
      roundtrip(man, text);
    }
  });
}

/// A page with every construct the core reads.
const dense = r'''.TH LS 1 "2024" "x" "y"
.SH NAME
ls \- list \fBdirectory\fR contents
.SH SYNOPSIS
.B ls
[\fIOPTION\fP]... [\fIFILE\fP]...
.SS "Sub heading"
.PP
one \fBtwo\fP \(em three \fIfour\fP back
.TP
.B \-l
long form \fBbold
.IP \(bu 4
item text
.RS
inner
.RE
.nf
pre text \fBx\fP
.fi
.\" a comment
.de XX
.SH inside
..
.if n \{\
.SH no
.\}
.EQ (1)
x sup 2
.EN
.BR one two
.UR http://x
link
.UE
.br
plain words here
''';
