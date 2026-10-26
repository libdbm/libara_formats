import 'dart:io';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// The three roff packages, man, ms and me, over the roff core: ported from
/// markwrite's `man_lex_test`, `ms_lex_test` and `me_lex_test`. Elements
/// are compared without regard to their order, which libara keeps.
void main() {
  /// The elements of [text] read as [syntax], each as its name and the
  /// text it covers.
  List<(String, String)> elements(Syntax syntax, String text) => [
    for (final (element, covered) in covering(decoded(syntax, text)))
      ('${element.get('')}', covered),
  ];

  /// What a reader is shown of [text] read as [syntax]: runs of text as
  /// they stand, an escape what it shows, and other markup nothing.
  String shown(Syntax syntax, String text) => [
    for (final token in decoded(syntax, text).layer(2).items.cast<ARange>())
      switch ('${token.get('')}') {
        '#text' => string(decoded(syntax, text).slice(token)),
        '#escape' => '${token.get('shows')}',
        _ => '',
      },
  ].join();

  /// The element of [text] read as [syntax] called [name].
  ARange element(Syntax syntax, String text, String name) => decoded(
    syntax,
    text,
  ).layer(3).items.cast<ARange>().firstWhere((one) => said(one, '') == name);

  group('A manual page', () {
    const man = Man();
    List<(String, String)> read(String text) => elements(man, text);

    test('keeps its text verbatim, and is found by section and name', () {
      roundtrip(man, '.TH ls 1\n.SH NAME\nls \\- list\n.PP\nWords.\n');
      expect(formats['1'], isA<Man>());
      expect(formats['man'], isA<Man>());
    });

    test('a section heading is a heading over the rest of its line', () {
      expect(
        read('.SH NAME\nls \\- list\n'),
        unorderedEquals([('h1', '.SH NAME'), ('p', 'ls \\- list')]),
      );
      expect(read('.SS Options\n'), [('h2', '.SS Options')]);
    });

    test('and the quotes round a heading are syntax', () {
      expect(shown(man, '.SH "SEE ALSO"\n'), 'SEE ALSO\n');
      expect(read('.SH "SEE ALSO"\n'), [('h1', '.SH "SEE ALSO"')]);
    });

    test('and one with no arguments takes the next line', () {
      expect(
        read('.SH\nNAME\n.PP\nx\n'),
        unorderedEquals([('h1', '.SH\nNAME'), ('p', '.PP\nx')]),
      );
    });

    test('a paragraph runs on to the next block request', () {
      expect(
        read('.PP\none\ntwo\n.PP\nthree\n'),
        unorderedEquals([('p', '.PP\none\ntwo'), ('p', '.PP\nthree')]),
      );
    });

    test('and a blank line ends one', () {
      expect(
        read('.PP\na\n\nb\n'),
        unorderedEquals([('p', '.PP\na'), ('p', 'b')]),
      );
    });

    test('a tagged paragraph is a term and what hangs under it', () {
      expect(
        read('.TP\n.B \\-l\nlong form\nmore\n.PP\nx\n'),
        unorderedEquals([
          ('dt', '.B \\-l'),
          ('strong', '.B \\-l'),
          ('dd', 'long form\nmore'),
          ('p', '.PP\nx'),
        ]),
      );
    });

    test('an indented paragraph is an item carrying its tag', () {
      const text = '.IP \\(bu 4\nitem\n.IP "1."\nnext\n';
      final items = [
        for (final (element, covered) in covering(decoded(man, text)))
          if (said(element, '') == 'li') (said(element, 'tag'), covered),
      ];
      expect(items, [('•', '.IP \\(bu 4\nitem'), ('1.', '.IP "1."\nnext')]);
    });

    test('an indent is a division holding what stands in it', () {
      expect(
        read('.RS\n.PP\nx\n.RE\n.PP\ny\n'),
        unorderedEquals([
          ('p', '.PP\nx'),
          ('div', '.RS\n.PP\nx\n.RE\n'),
          ('p', '.PP\ny'),
        ]),
      );
      expect(said(element(man, '.RS\nx\n.RE\n', 'div'), 'class'), 'indent');
    });

    test('and a close with nothing open is syntax', () {
      expect(read('.RE\nx\n'), [('p', 'x')]);
    });

    test('unfilled lines are a preformatted block, as they stand', () {
      expect(
        read('.nf\ncode  here\n\nmore\n.fi\n.PP\nx\n'),
        unorderedEquals([
          ('pre', '.nf\ncode  here\n\nmore\n.fi\n'),
          ('p', '.PP\nx'),
        ]),
      );
      expect(read('.EX\n\$ ls\n.EE\n'), [('pre', '.EX\n\$ ls\n.EE\n')]);
    });

    test('a font request sets the rest of its line', () {
      expect(
        read('.PP\nsee\n.B bold\nand\n.I slanted\n'),
        unorderedEquals([
          ('strong', '.B bold'),
          ('em', '.I slanted'),
          ('p', '.PP\nsee\n.B bold\nand\n.I slanted'),
        ]),
      );
      expect(
        read('.SB small\n'),
        unorderedEquals([
          ('p', '.SB small'),
          ('strong', '.SB small'),
          ('small', '.SB small'),
        ]),
      );
    });

    test('and an alternating one sets its arguments with nothing between', () {
      expect(shown(man, '.BI foo bar "b az"\n'), 'foobarb az\n');
      expect(
        read('.BI foo bar\n'),
        unorderedEquals([
          ('p', '.BI foo bar'),
          ('strong', 'foo'),
          ('em', 'bar'),
        ]),
      );
      expect(
        read('.BR ls (1)\n'),
        unorderedEquals([
          ('p', '.BR ls (1)'),
          ('strong', 'ls'),
          ('span', '(1)'),
        ]),
      );
    });

    test('a font escape opens a face that the next one closes', () {
      expect(
        read('.PP\n\\fBbold\\fR plain \\fIslant\\fP\n'),
        unorderedEquals([
          ('strong', '\\fBbold\\fR'),
          ('em', '\\fIslant\\fP'),
          ('p', '.PP\n\\fBbold\\fR plain \\fIslant\\fP'),
        ]),
      );
    });

    test('and a change of face closes the face that stood', () {
      expect(
        read('.PP\n\\fBbold \\fIboth\\fR\n'),
        unorderedEquals([
          ('strong', '\\fBbold '),
          ('em', '\\fIboth\\fR'),
          ('p', '.PP\n\\fBbold \\fIboth\\fR'),
        ]),
      );
      expect(
        read('.PP\n\\f(BIx\\f[R]y\n'),
        unorderedEquals([
          ('em', '\\f(BIx\\f[R]'),
          ('strong', '\\f(BIx\\f[R]'),
          ('p', '.PP\n\\f(BIx\\f[R]y'),
        ]),
      );
    });

    test('and a face still open at the end of a block closes there', () {
      expect(
        read('.PP\n\\fBbold\n.PP\nplain\n'),
        unorderedEquals([
          ('p', '.PP\n\\fBbold'),
          ('strong', '\\fBbold'),
          ('p', '.PP\nplain'),
        ]),
      );
    });

    test('a glyph shows the character it names', () {
      expect(
        shown(man, '.PP\na \\(em b \\[bu] c \\-d \\e\n'),
        'a — b • c -d \\\n',
      );
    });

    test(
      'and one nobody has heard of, or a string or register, shows nothing',
      () {
        expect(
          shown(
            man,
            '.PP\na\\(zzb\\*(xyc\\*[long]d\\nxe\\s+2f\\s0g\\h\'2n\'h\\&i\n',
          ),
          'abcdefghi\n',
        );
      },
    );

    test('a comment is syntax, whole line or trailing', () {
      expect(read('.\\" a comment\n.PP\nx \\" trailing\n'), [
        ('p', '.PP\nx \\" trailing'),
      ]);
      expect(shown(man, '.PP\nx \\" trailing\n'), 'x \n');
    });

    test('a definition and a condition are read as nothing at all', () {
      expect(read('.de Sh\n.br\n\\fB\\\\\$1\\fR\n..\n.PP\nx\n'), [
        ('p', '.PP\nx'),
      ]);
      expect(read('.if n \\{\\\n.sp\n.PP\n\\}\n.PP\nx\n'), [('p', '.PP\nx')]);
      expect(read('.ie t .sp 2\n.el .sp\n.PP\nx\n'), [('p', '.PP\nx')]);
      expect(read('.de Unterminated\n.PP\nx\n'), isEmpty);
    });

    test('a string defined is shown where it is used', () {
      expect(
        shown(
          man,
          '.ds Pr \\fBlibara\\fR\n.as Pr " formats\n.PP\n\\*(Pr and \\*[Pr]\n',
        ),
        'libara formats and libara formats\n',
      );
      expect(shown(man, '.PP\n\\*x\n'), '\n');
    });

    test('and after a keystroke that reads only a window', () {
      final text =
          '.ds Pr libara\n${'.PP\nwords\n' * 100}.PP\nuse \\*(Pr here\n';
      var document = decoded(man, text);
      document = edited(
        man,
        document,
        Edit(1, Insert(text.lastIndexOf('here'), Text.of('x'))),
      );
      expect(
        [
          for (final token in document.layer(2).items.cast<ARange>())
            if (said(token, '') == '#escape') said(token, 'shows'),
        ],
        ['libara'],
      );
      final window = document.grammar.affected(
        document,
        2,
        value(Range.create(document.items.length - 3, 1)),
      );
      expect(window.length, lessThan(document.items.length ~/ 10));
    });

    test('and a definition changed reads again what uses it', () {
      final text = '.ds Pr libara\n${'.PP\nwords\n' * 100}.PP\n\\*(Pr\n';
      edited(
        man,
        decoded(man, text),
        Edit(1, Replace(value(Range.create(7, 6)), Text.of('other'))),
      );
    });

    group('a tbl table', () {
      /// What [text]'s elements called [name] cover, read as man.
      List<String> named(String text, String name) => [
        for (final (element, covered) in covering(decoded(man, text)))
          if (said(element, '') == name) covered,
      ];

      const text =
          '.TS\ncenter tab(/) ;\nl l.\n\\fBName\\fR/What\n=\n'
          'one/T{\nmany\nwords\nT}\n.TE\n.PP\nafter\n';

      test('is a table of rows of cells', () {
        expect(named(text, 'table'), hasLength(1));
        expect(named(text, 'tr'), [
          '\\fBName\\fR/What',
          'one/T{\nmany\nwords\nT}',
        ]);
        expect(named(text, 'td'), [
          '\\fBName\\fR',
          'What',
          'one',
          'T{\nmany\nwords\nT}',
        ]);
        expect(named(text, 'p'), ['.PP\nafter']);
      });

      test('whose faces close with their cell', () {
        expect(named('.TS\ntab(/);\nl l.\n\\fBa/b\\fR\n.TE\n', 'strong'), [
          '\\fBa',
        ]);
      });

      test('read as words, with tabs where no option names a character', () {
        expect(named('.TS\nl l.\na\tb\n.TE\n', 'td'), ['a', 'b']);
      });

      test('kept as it was written', () {
        roundtrip(man, text);
      });

      test('edited at random as a fresh read gives it', () {
        var document = decoded(man, text);
        for (final at in [5, 20, 31, 40, 52, 60]) {
          document = edited(man, document, Edit(1, Insert(at, Text.of('x'))));
        }
      });
    });

    test('a pic picture is read as it stands', () {
      for (final syntax in [man, const Ms(), const Me()]) {
        final document = decoded(
          syntax,
          '.PS\nbox "x"; arrow\n.PE\n.PP\nafter\n',
        );
        expect([
          for (final (element, _) in covering(document))
            '${element.get('')} ${said(element, 'class')}',
        ], contains('pre picture'));
      }
    });

    test('a definition or an ignored stretch ends where it says it does', () {
      expect(read('.de Sh En\n..\n.PP\ny\n.En\n.PP\nx\n'), [('p', '.PP\nx')]);
      expect(read('.de Sh \\" a comment\n.br\n..\n.PP\nx\n'), [
        ('p', '.PP\nx'),
      ]);
      expect(read('.ig En\n..\n.PP\ny\n.En\n.PP\nx\n'), [('p', '.PP\nx')]);
    });

    test('and a request the package does not know is syntax', () {
      expect(shown(man, '.nr foo 1\n.ds bar baz\n.PP\nx\n'), 'x\n');
      expect(read('.nr foo 1\n.PP\nx\n'), [('p', '.PP\nx')]);
    });

    test('the title line is one element carrying what it says', () {
      final title = element(
        man,
        '.TH ls 1 "2024-01-02" "GNU" "User Commands"\n',
        'head',
      );
      expect(said(title, 'name'), 'ls');
      expect(said(title, 'section'), '1');
      expect(said(title, 'date'), '2024-01-02');
      expect(said(title, 'source'), 'GNU');
      expect(said(title, 'manual'), 'User Commands');
      expect(title.length, 1);
    });

    test('a link is an anchor pointing where its request said', () {
      const text = '.PP\nsee\n.UR https://x.org\nthe site\n.UE .\n';
      final link = covering(decoded(man, text))
          .firstWhere((one) => said(one.$1, '') == 'a');
      expect(said(link.$1, 'href'), 'https://x.org');
      expect(link.$2, '.UR https://x.org\nthe site\n.UE .\n');
      expect(
        said(element(man, '.MT a@b.c\nme\n.ME\n', 'a'), 'href'),
        'mailto:a@b.c',
      );
    });

    test('a break is an element of its own', () {
      expect(
        read('.PP\na\n.br\nb\n'),
        unorderedEquals([('br', '.br\n'), ('p', '.PP\na\n.br\nb')]),
      );
    });

    test('a page out of the wild reads as its sections', () {
      const page =
          '.\\" Copyright\n'
          '.TH AB 1 "2026-04-28" "Apache" "ab"\n'
          '.SH NAME\n'
          'ab \\- benchmarking tool\n'
          '.SH "SYNOPSIS"\n'
          '.PP\n'
          '\\fBab\\fR [ -\\fBA\\fR \\fIauth\\fR:\\fIpassword\\fR ]\n'
          '.SH OPTIONS\n'
          '.TP\n'
          '\\fB-A\\fR \\fIauth-username:password\\fR\n'
          'Supply BASIC Authentication credentials.\n'
          '.TP\n'
          '\\fB-b\\fR\n'
          'Size of TCP send/receive buffer.\n';
      final names = [for (final (name, _) in read(page)) name];
      expect(names.where((name) => name == 'h1'), hasLength(3));
      expect(names.where((name) => name == 'dt'), hasLength(2));
      expect(names.where((name) => name == 'dd'), hasLength(2));
      expect(names.first, 'head');
    });

    test('what is malformed for any syntax is read, never thrown', () {
      for (final text in [
        '<p>one <em two</p>', '<p>a < b</p>', '<p>a &amp b &#x</p>', //
        '', '<<>><<>>', '[p one [em}two', 'one {em] two',
        'one *two three\n', '```dart\none two\n', 'one ] two [ three\n',
        '| --- |\n', '.\n', '.\\', '\\', '\\f', '\\(', '.TH\n', '.SH',
        '.de\n', '.if \\{\n', '.EQ\ndelim\n.EN\n',
      ]) {
        roundtrip(man, text);
      }
    });

    test('and a page past its token limit is refused, not truncated', () {
      final read = const Man(limits: Limits(markers: 8))
          .decode(Text.of('.PP\n' * 20));
      expect(read, isA<Failure<Object?>>());
      expect((read as Failure<Object?>).message, contains('token'));
    });
  });

  group('A paper in the ms package', () {
    const ms = Ms();
    List<(String, String)> read(String text) => elements(ms, text);

    test('has a title, its authors and their affiliations as blocks', () {
      expect(
        read('.TL\nOn Things\n.AU\nA. Writer\n.AI\nA Place\n.PP\nx\n'),
        unorderedEquals([
          ('title', '.TL\nOn Things'),
          ('author', '.AU\nA. Writer'),
          ('affiliation', '.AI\nA Place'),
          ('p', '.PP\nx'),
        ]),
      );
    });

    test('and an abstract holding its paragraphs', () {
      expect(
        read('.AB\nIn short.\n.PP\nMore.\n.AE\n.PP\nx\n'),
        unorderedEquals([
          ('p', 'In short.'),
          ('p', '.PP\nMore.'),
          ('abstract', '.AB\nIn short.\n.PP\nMore.\n.AE\n'),
          ('p', '.PP\nx'),
        ]),
      );
    });

    test('a numbered heading takes its rank from its argument', () {
      expect(
        read('.NH\nOne\n.NH 2\nTwo\n.NH 3\nThree\n.SH\nPlain\n.PP\nx\n'),
        unorderedEquals([
          ('h1', '.NH\nOne'),
          ('h2', '.NH 2\nTwo'),
          ('h3', '.NH 3\nThree'),
          ('h1', '.SH\nPlain'),
          ('p', '.PP\nx'),
        ]),
      );
    });

    test('and one past the six ranks a sheet resolves is held to them', () {
      expect(read('.NH 9\nDeep\n'), [('h6', '.NH 9\nDeep')]);
    });

    test('a quotation is a paragraph of its own, or a container of them', () {
      expect(
        read('.QP\nquoted\n.PP\nx\n'),
        unorderedEquals([('blockquote', '.QP\nquoted'), ('p', '.PP\nx')]),
      );
      expect(
        read('.QS\none\n.PP\ntwo\n.QE\n'),
        unorderedEquals([
          ('p', 'one'),
          ('p', '.PP\ntwo'),
          ('blockquote', '.QS\none\n.PP\ntwo\n.QE\n'),
        ]),
      );
    });

    test('a display is preformatted, whichever way it is placed', () {
      for (final opener in ['.DS', '.DS L', '.LD', '.ID', '.CD', '.BD']) {
        expect(read('$opener\ncode  here\n.DE\n'), [
          ('pre', '$opener\ncode  here\n.DE\n'),
        ]);
      }
    });

    test('a footnote holds what stands between its requests', () {
      expect(
        read('.PP\nWords\n.FS\nA note.\n.FE\nmore\n'),
        unorderedEquals([
          ('p', '.PP\nWords'),
          ('footnote', '.FS\nA note.\n.FE\n'),
          ('p', 'A note.'),
          ('p', 'more'),
        ]),
      );
    });

    test('a keep is a division saying so', () {
      expect(said(element(ms, '.KS\nkept\n.KE\n', 'div'), 'class'), 'keep');
      expect([
        for (final (name, _) in read('.KF\nkept\n.KE\n')) name,
      ], unorderedEquals(['div', 'p']));
    });

    test('the font requests set their arguments', () {
      expect(
        read('.PP\n.B bold\n.I slant\n.BI a b\n.UL under\n.CW code\n'),
        unorderedEquals([
          ('strong', '.B bold'),
          ('em', '.I slant'),
          ('strong', 'a'),
          ('em', 'b'),
          ('u', '.UL under'),
          ('code', '.CW code'),
          ('p', '.PP\n.B bold\n.I slant\n.BI a b\n.UL under\n.CW code'),
        ]),
      );
    });

    test('an item carries its tag and an equation is its own block', () {
      const text = '.IP "1." 4\nfirst\n.EQ\nx sup 2\n.EN\n';
      expect([
        for (final (name, _) in read(text)) name,
      ], unorderedEquals(['li', 'equation']));
      expect(said(element(ms, text, 'li'), 'tag'), '1.');
    });

    test('and what the package does not know shows nothing', () {
      expect(read('.RP\n.ND "1 May"\n.2C\n.PP\nx\n'), [('p', '.PP\nx')]);
    });
  });

  group('A paper in the me package', () {
    const me = Me();
    List<(String, String)> read(String text) => elements(me, text);

    test('a section heading carries its rank and its words on the line', () {
      expect(
        read('.sh 1 "Intro"\n.pp\nx\n.sh 2 Deeper\ny\n.uh Plain\n'),
        unorderedEquals([
          ('h1', '.sh 1 "Intro"'),
          ('p', '.pp\nx'),
          ('h2', '.sh 2 Deeper'),
          ('p', 'y'),
          ('h1', '.uh Plain'),
        ]),
      );
    });

    test('and a rank may be a step from the last', () {
      expect(
        read('.sh 2 A\n.sh +1 B\n.sh -1 C\n.sh +9 D\n'),
        unorderedEquals([
          ('h2', '.sh 2 A'),
          ('h3', '.sh +1 B'),
          ('h2', '.sh -1 C'),
          ('h6', '.sh +9 D'),
        ]),
      );
    });

    test('and one with a rank and no words takes the next line', () {
      expect(
        read('.sh 1\nIntro\n.pp\nx\n'),
        unorderedEquals([('h1', '.sh 1\nIntro'), ('p', '.pp\nx')]),
      );
    });

    test('the quotes round a heading are syntax', () {
      expect(shown(me, '.sh 1 "In tro"\n'), 'In tro\n');
    });

    test('a paragraph, an item and a bullet', () {
      const text = '.lp\nplain\n.ip tag\nitem\n.bu\nbullet\n.np\nnumbered\n';
      expect(
        [
          for (final (element, _) in covering(decoded(me, text)))
            (said(element, ''), said(element, 'tag')),
        ],
        [('p', null), ('li', 'tag'), ('li', '•'), ('li', null)],
      );
    });

    test('the parenthesised requests are containers', () {
      expect(
        read('.(l\ncode  here\n.)l\n.(q\nquoted\n.)q\n.(c\ncentred\n.)c\n'),
        unorderedEquals([
          ('pre', '.(l\ncode  here\n.)l\n'),
          ('blockquote', '.(q\nquoted\n.)q\n'),
          ('p', 'quoted'),
          ('div', '.(c\ncentred\n.)c\n'),
          ('p', 'centred'),
        ]),
      );
      expect(
        read('.pp\nWords\n.(f\nA note.\n.)f\nmore\n'),
        unorderedEquals([
          ('p', '.pp\nWords'),
          ('footnote', '.(f\nA note.\n.)f\n'),
          ('p', 'A note.'),
          ('p', 'more'),
        ]),
      );
    });

    test('an index entry is read as nothing', () {
      expect(
        read('.pp\nx\n.(x\nan entry\n.)x\n.pp\ny\n'),
        unorderedEquals([('p', '.pp\nx'), ('p', '.pp\ny')]),
      );
      expect(shown(me, '.(x\nan entry\n.)x\ny\n'), 'y\n');
    });

    test('and one never closed is read as nothing to the end', () {
      expect(read('.(x\nentry\ny\n'), isEmpty);
    });

    test('the font requests set their arguments, a quotation among them', () {
      expect(
        read('.pp\n.b bold\n.i slant\n.q quoted\n.u under\n'),
        unorderedEquals([
          ('strong', '.b bold'),
          ('em', '.i slant'),
          ('q', '.q quoted'),
          ('u', '.u under'),
          ('p', '.pp\n.b bold\n.i slant\n.q quoted\n.u under'),
        ]),
      );
    });

    test('and the running heads and feet show nothing', () {
      expect(read('.he "Head"\n.fo "Foot"\n.pp\nx\n'), [('p', '.pp\nx')]);
    });
  });

  group('Every roff sample', () {
    for (final (name, syntax) in [
      ('htpasswd.1', const Man()),
      ('markwrite.1', const Man()),
      ('ranges.ms', const Ms()),
    ]) {
      test('$name round-trips, and edits at random read afresh', () {
        final text = File('test/samples/$name').readAsStringSync();
        roundtrip(syntax, text);
        derivable(syntax, text, seed: name.hashCode, edits: 150);
      });
    }

    test('and a stepped heading in an edit reads afresh', () {
      const text = '.sh 1 A\n.pp\nx\n.sh +1 B\n.pp\ny\n.sh +1 C\n.pp\nz\n';
      edited(
        const Me(),
        decoded(const Me(), text),
        Edit(1, Insert(text.indexOf('x'), Text.of('w'))),
      );
    });
  });
}
