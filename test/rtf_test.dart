import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:libara_formats/src/convert.dart' show projected, structure;
import 'package:libara_formats/src/import/rtf.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// RTF: tokens as Word, LibreOffice and Cocoa write them, kept as written.
void main() {
  const rtf = RTF();

  /// [text], each character one byte, read as RTF.
  Layered<int> read(String text) => decoded(rtf, text);

  /// The RTF samples, each as its bytes, one character a byte.
  final samples = {
    for (final file in Directory(
      'test/samples/rtf',
    ).listSync().whereType<File>())
      if (file.path.endsWith('.rtf'))
        file.uri.pathSegments.last: String.fromCharCodes(
          file.readAsBytesSync(),
        ),
  };

  /// The tokens of [text] read as RTF, each its name, what it shows, if
  /// anything, and the text it covers.
  List<(String, String?, String)> scanned(String text) {
    final document = read(text);
    return [
      for (final range in document.layer(2).items.cast<ARange>())
        (
          said(range, '')!,
          said(range, 'shows'),
          string(document.items.slice(range.start, range.length)),
        ),
    ];
  }

  group('The text', () {
    test('every sample is written back as it was read', () {
      expect(samples, hasLength(greaterThanOrEqualTo(12)));
      for (final MapEntry(key: name, value: text) in samples.entries) {
        roundtrip(rtf, text);
        expect(problems(read(text), 2), isEmpty, reason: name);
      }
    });

    test('a form not beginning {\\rtf is refused', () {
      expect(
        rtf.decode(Text.of('{\\rtx1 a}')),
        isA<Failure<Layered<int>>>().having(
          (failure) => failure.kind,
          'kind',
          Kind.syntax,
        ),
      );
    });

    test('a form holding an item past 255 is refused', () {
      expect(
        rtf.decode(Text.of('{\\rtf1 é😀}')),
        isA<Failure<Layered<int>>>().having(
          (failure) => failure.kind,
          'kind',
          Kind.syntax,
        ),
      );
    });

    test('arbitrary bytes behind the signature are read alike twice', () {
      final random = Random(0x52544);
      const alphabet = [
        'a', ' ', '\n', '\r', '{', '}', r'\', "'", '-', '1', '9', 'b', //
        'u', 'i', 'n', '?', '*', '~', '\u0092', 'é', 'f', '0',
      ];
      for (var sample = 0; sample < 300; sample++) {
        final source =
            '{\\rtf1 ${[for (var index = random.nextInt(120); index > 0; index--) alphabet[random.nextInt(alphabet.length)]].join()}';
        final one = read(source);
        expect(string(one.items), source);
        expect(layers(one), layers(read(source)), reason: source);
        var at = 0;
        for (final range in one.layer(2).items.cast<ARange>()) {
          expect(range.start, at, reason: source);
          at = range.end;
        }
        expect(at, one.items.length, reason: source);
      }
    });
  });

  group('Tokens', () {
    test('braces, control words with a parameter, and text', () {
      expect(tokens(read(r'{\rtf1\ansi\b0 bold\par}')), [
        ('{', '{'),
        ('rtf', r'\rtf1'),
        ('ansi', r'\ansi'),
        ('b', r'\b0 '),
        ('#text', 'bold'),
        ('par', r'\par'),
        ('}', '}'),
      ]);
      final word = read(r'{\rtf1\fs-24 x}')
          .layer(2)
          .items
          .cast<ARange>()
          .toList()[2];
      expect(said(word, ''), 'fs');
      expect(said(word, 'value'), '-24');
    });

    test('a control word that shows a character says it', () {
      expect(scanned(r'{\rtf1\tab\emdash\rquote\line}'), [
        ('{', null, '{'),
        ('rtf', null, r'\rtf1'),
        ('tab', '\t', r'\tab'),
        ('emdash', '—', r'\emdash'),
        ('rquote', '’', r'\rquote'),
        ('line', '\n', r'\line'),
        ('}', null, '}'),
      ]);
    });

    test('control symbols, and a backslash before a line break', () {
      expect(scanned('{\\rtf1 a\\{\\}\\\\\\~\\-\\*b\\\nc}'), [
        ('{', null, '{'),
        ('rtf', null, '\\rtf1 '),
        ('#text', null, 'a'),
        ('#symbol', '{', '\\{'),
        ('#symbol', '}', '\\}'),
        ('#symbol', '\\', '\\\\'),
        ('#symbol', ' ', '\\~'),
        ('#symbol', null, '\\-'),
        ('#symbol', null, '\\*'),
        ('#text', null, 'b'),
        ('par', '\n', '\\\n'),
        ('#text', null, 'c'),
        ('}', null, '}'),
      ]);
    });

    test('line breaks, which RTF ignores, are a token of their own', () {
      expect(tokens(read('{\\rtf1 a\r\n\nb}'))[3], ('#break', '\r\n\n'));
    });

    test('a byte past 127 is a character of its own', () {
      expect(scanned('{\\rtf1 café}')[3], ('#character', 'é', 'é'));
    });

    test('the data after \\bin is part of its token', () {
      final tokens = scanned('{\\rtf1 \\bin3 {}\\x}');
      expect(tokens[2], ('bin', null, '\\bin3 {}\\'));
      expect(tokens[3], ('#text', null, 'x'));
    });

    test('a \\bin past the end is a diagnostic', () {
      expect(problems(read('{\\rtf1 \\bin30 ab}'), 2), isNotEmpty);
    });

    test('what does not scan is an error, and a diagnostic', () {
      final document = read("{\\rtf1 \\'zz}");
      expect(tokens(document)[2], ('#error', '\\\''));
      expect(problems(document, 2), isNotEmpty);
    });
  });

  group('Code pages and Unicode', () {
    /// What [text]'s third token, after the brace and \rtf1, shows.
    String? shown(String text) => scanned(text)[2].$2;

    test('a byte past 127 is a character of Windows-1252 by default', () {
      for (final (byte, shows) in [
        (0x80, '€'),
        (0x92, '’'),
        (0x96, '–'),
        (0xE9, 'é'),
        (0x81, '�'),
      ]) {
        expect(
          shown('{\\rtf1 ${String.fromCharCode(byte)}}'),
          shows,
          reason: '$byte',
        );
        final hex = byte.toRadixString(16);
        expect(shown("{\\rtf1 \\'$hex}"), shows, reason: hex);
      }
    });

    test('and of MacRoman where the header says \\mac', () {
      for (final (byte, shows) in [(0x80, 'Ä'), (0xA5, '•'), (0xD5, '’')]) {
        final hex = byte.toRadixString(16);
        expect(scanned("{\\rtf1\\mac \\'$hex}")[3].$2, shows, reason: hex);
        expect(
          scanned("{\\rtf1\\ansicpg10000 \\'$hex}")[3].$2,
          shows,
          reason: hex,
        );
      }
    });

    test('\\uN is a signed 16-bit character, its fallback taken with it', () {
      expect(scanned('{\\rtf1 \\u-3913?x}')[2], ('#unicode', '', r'\u-3913?'));
      expect(scanned("{\\rtf1 \\u8217\\'92x}")[2], (
        '#unicode',
        '’',
        "\\u8217\\'92",
      ));
      expect(scanned('{\\rtf1\\uc0 \\u8226 x}')[3], (
        '#unicode',
        '•',
        r'\u8226 ',
      ));
    });

    test('a surrogate pair is one character, a lone surrogate U+FFFD', () {
      expect(scanned('{\\rtf1 \\u-10179?\\u-8704?}')[2], (
        '#unicode',
        '😀',
        r'\u-10179?\u-8704?',
      ));
      final lone = read('{\\rtf1 \\u-10179?x}');
      expect(scanned('{\\rtf1 \\u-10179?x}')[2].$2, '�');
      expect(problems(lone, 2), isNotEmpty);
    });
  });

  /// [document]'s elements, each its name, what it says and the content it
  /// covers, in pre-order.
  List<String> elements(Layered<int> document) {
    final (:content, :offsets, :elements) = projected(document);
    return [
      for (final element in elements)
        '${element.name} ${element.said} '
            '"${content.substring(offsets[element.first], offsets[element.last])}"',
    ];
  }

  /// A sample's paragraphs: its elements but those of its header.
  List<String> paragraphs(String name) => [
    for (final one in elements(read(samples['$name.rtf']!)))
      if (RegExp(r'^(p|h\d|li|blockquote|pre) ').hasMatch(one)) one,
  ];

  group('Paragraphs', () {
    test('header groups are elements that show nothing', () {
      final document = read(
        r'{\rtf1{\fonttbl{\f0 Times;}}{\*\generator Word;}\pard x\par}',
      );
      expect(elements(document), [
        'fonttbl {} ""',
        'generator {} ""',
        'p {} "x\n"',
      ]);
    });

    test('what a hidden destination holds is not the content', () {
      final (:content, offsets: _, elements: _) = projected(
        read(r'{\rtf1{\fonttbl{\f0 Times;}}{\info{\title T}}a{\*\x b}c\par}'),
      );
      expect(content, 'ac\n');
    });

    test('a paragraph is named by its style, and says the style', () {
      const sheet =
          r'{\stylesheet{\ql Normal;}{\s1\outlinelevel0 heading 1;}'
          r'{\s2 Quote;}{\*\cs10 Default Paragraph Font;}}';
      expect(
        elements(
          read('{\\rtf1$sheet\\pard\\s1 A\\par\\pard\\s2 B\\par\\pard C\\par}'),
        ).skip(1),
        [
          'h1 {class: heading 1} "A\n"',
          'blockquote {class: Quote} "B\n"',
          'p {class: Normal} "C\n"',
        ],
      );
    });

    test('an outline level makes a heading, whatever the style', () {
      expect(elements(read(r'{\rtf1\pard\outlinelevel2 A\par}')), [
        'h3 {} "A\n"',
      ]);
    });

    test('a paragraph no style names, as Cocoa writes, is a p', () {
      expect(elements(read('{\\rtf1\\pard\\f0\\fs24 A\\\nB}')), [
        'p {} "A\n"',
        'p {} "B"',
      ]);
    });

    test('Word, LibreOffice and TextEdit headings, as their files say', () {
      for (final name in ['features-word', 'features-libreoffice']) {
        expect(paragraphs(name).take(2), [
          'h1 {class: Title, size: 28} "Lorem Ipsum\n"',
          'h1 {class: heading 1, size: 16} "Dolor sit amet\n"',
        ], reason: name);
      }
      expect(paragraphs('features-textedit').take(2), [
        'p {} "Lorem Ipsum\n"',
        'p {} "Dolor sit amet\n"',
      ]);
    });
  });

  group('Font size', () {
    test('a paragraph all of one size but the body says it, in points', () {
      final sizes = [
        for (final one in elements(
          read(
            '{\\rtf1\\pard\\fs36 A\\par\\pard\\fs24 B\\par\\pard\\fs23 C\\par'
            '\\pard\\fs24 D\\par}',
          ),
        ))
          one,
      ];
      expect(sizes, [
        'p {size: 18} "A\n"',
        'p {} "B\n"',
        'p {size: 11.5} "C\n"',
        'p {} "D\n"',
      ]);
    });

    test('one of mixed sizes says none', () {
      expect(
        elements(read(r'{\rtf1\pard\fs24 a {\fs36 b} c\par\pard\fs24 d\par}')),
        ['p {} "a b c\n"', 'p {} "d\n"'],
      );
    });

    test('the body size is the default style\'s where it says one', () {
      // Most characters are 12 points, but the default style says 18.
      expect(
        elements(
          read(
            r'{\rtf1{\stylesheet{\s0\fs36 Normal;}}'
            r'\pard\fs36 A\par\pard\fs24 many more characters\par}',
          ),
        ).skip(1),
        [
          'p {class: Normal} "A\n"',
          'p {class: Normal, size: 12} "many more characters\n"',
        ],
      );
    });

    test('hand-formatted headings from Word and TextEdit say their size', () {
      for (final name in ['degenerate-word', 'degenerate-textedit']) {
        final found = paragraphs(name);
        expect(
          found[0],
          endsWith('size: 16} "Lorem Ipsum Dolor\n"'),
          reason: name,
        );
        expect(found[1], isNot(contains('size')), reason: name);
        expect(found[4], isNot(contains('size')), reason: name);
      }
    });

    test('a document all of one size has that as its body', () {
      for (final one in paragraphs('revisions-pages')) {
        expect(one, isNot(contains('size')));
      }
    });
  });

  group('Faces', () {
    /// [document]'s faces, each its name and the content it covers.
    List<String> faces(String text) => [
      for (final one in elements(read(text)))
        if (RegExp(r'^(strong|em|u|s|sup|sub|code) ').hasMatch(one))
          one.replaceFirst(' {}', ''),
    ];

    test('each control word turns its face on, and 0 turns it off', () {
      for (final (word, face) in [
        ('b', 'strong'),
        ('i', 'em'),
        ('ul', 'u'),
        ('uldb', 'u'),
        ('ulwave', 'u'),
        ('strike', 's'),
        ('super', 'sup'),
        ('sub', 'sub'),
      ]) {
        expect(faces('{\\rtf1\\pard a\\$word b\\${word}0 c\\par}'), [
          '$face "b"',
        ], reason: word);
      }
    });

    test('a face closes at its off word, at \\plain, or with its group', () {
      expect(faces(r'{\rtf1\pard a\b b\plain c\par}'), ['strong "b"']);
      expect(faces(r'{\rtf1\pard a{\i b}c\par}'), ['em "b"']);
      expect(faces(r'{\rtf1\pard \ul a\ulnone b\par}'), ['u "a"']);
      expect(
        faces(r'{\rtf1\pard \super a\nosupersub b\sub c\nosupersub\par}'),
        ['sup "a"', 'sub "c"'],
      );
    });

    test('a face turned off within a group is on again past it', () {
      expect(faces(r'{\rtf1\pard \b a{\b0 b}c\b0\par}'), [
        'strong "a"',
        'strong "c"',
      ]);
    });

    test('a face is not cut at a paragraph mark', () {
      expect(faces(r'{\rtf1\pard \b a\par\pard b\b0\par}'), ['strong "a\nb"']);
    });

    test('a monospaced font is code, by its family or its name', () {
      const tables = [
        r'{\fonttbl{\f0 Times;}{\f1\fmodern Fixed;}}',
        r'{\fonttbl{\f0 Times;}{\f1{\*\panose 0207}Courier New;}}',
        r'{\fonttbl\f0\froman Times-Roman;\f1\fnil Menlo-Regular;}',
        r'{\fonttbl\f0\froman Times-Roman;\f1\fswiss CourierNewPSMT;}',
      ];
      for (final table in tables) {
        expect(faces('{\\rtf1$table\\pard\\f0 a\\f1 b\\f0 c\\par}'), [
          'code "b"',
        ], reason: table);
      }
    });

    test('a face the paragraph\'s style sets is the style\'s', () {
      const sheet = r'{\stylesheet{\s1\b heading 1;}}';
      expect(
        faces('{\\rtf1$sheet\\pard\\s1\\b A\\par\\pard\\plain\\b B\\b0\\par}'),
        ['strong "B"'],
      );
    });

    test('a face over nothing that shows is none', () {
      expect(faces(r'{\rtf1\pard a{\super\chftn}\par}'), isEmpty);
    });

    test('the samples\' faces are their references\'', () {
      for (final name in ['features-word', 'features-libreoffice']) {
        expect(faces(samples['$name.rtf']!).take(8), [
          'strong "ipsum"',
          'em "sit"',
          'u "consectetur"',
          's "elit"',
          'sup "2"',
          'sub "2"',
          'code "tempor()"',
          anyOf('strong "bold italic"', 'em "bold italic"'),
        ], reason: name);
      }
    });
  });

  group('Lists', () {
    /// [document]'s lists and items, each its depth, name and the first
    /// words of its content, in pre-order.
    List<String> outline(Layered<int> document) {
      final (:content, :offsets, elements: _) = projected(document);
      return [
        for (final one in structure(document))
          if (const {'ul', 'ol', 'li'}.contains('${one.element.get('')}'))
            '${one.depth} ${one.element.get('')} '
                '${content.substring(offsets[one.element.start], offsets[one.element.end]).split('\n').first}',
      ];
    }

    const tables =
        r'{\*\listtable{\list{\listlevel\levelnfc23}{\listlevel\levelnfc0}'
        r'\listid7}{\list{\listlevel\levelnfc0}\listid8}}'
        r'{\*\listoverridetable{\listoverride\listid7\ls1}'
        r'{\listoverride\listid8\ls2}}';

    test('a bullet is a ul, anything else an ol, by level', () {
      expect(
        outline(
          read(
            '{\\rtf1$tables\\pard\\ls1 a\\par\\pard\\ls1\\ilvl1 b\\par'
            '\\pard\\ls2 c\\par}',
          ),
        ),
        ['0 ul a', '1 li a', '2 ol b', '3 li b', '0 ol c', '1 li c'],
      );
    });

    test('a Cocoa marker says a bullet', () {
      const cocoa =
          r'{\*\listtable{\list{\listlevel\levelnfc0{\*\levelmarker \{disc\}}}'
          r'\listid1}}{\*\listoverridetable{\listoverride\listid1\ls1}}';
      expect(outline(read('{\\rtf1$cocoa\\pard\\ls1 a\\\n}')), [
        '0 ul a',
        '1 li a',
      ]);
    });

    test('two lists of one kind are two lists', () {
      const two =
          r'{\*\listtable{\list{\listlevel\levelnfc23}\listid1}'
          r'{\list{\listlevel\levelnfc23}\listid2}}'
          r'{\*\listoverridetable{\listoverride\listid1\ls1}'
          r'{\listoverride\listid2\ls2}}';
      expect(
        outline(read('{\\rtf1$two\\pard\\ls1 a\\par\\pard\\ls2 b\\par}')),
        ['0 ul a', '1 li a', '0 ul b', '1 li b'],
      );
    });

    test('a list no table defines is a diagnostic, and its item a p', () {
      final document = read(r'{\rtf1\pard\ls9 a\par}');
      expect(elements(document), ['p {} "a\n"']);
      expect(problems(document, 3), contains(contains('ls9')));
    });

    test('the samples nest to three levels, as each application wrote', () {
      for (final name in ['features-word', 'features-textedit']) {
        expect(outline(read(samples['$name.rtf']!)).take(8), [
          '0 ul Sed do eiusmod',
          '1 li Sed do eiusmod',
          '2 ul Tempor incididunt',
          '3 li Tempor incididunt',
          '4 ul Ut labore',
          '5 li Ut labore',
          '3 li Et dolore',
          '1 li Magna aliqua',
        ], reason: name);
      }
    });
  });

  group('Tables, fields, footnotes and pictures', () {
    /// [text]'s elements of these names.
    List<String> found(String text, Set<String> names) => [
      for (final one in elements(read(text)))
        if (names.contains(one.split(' ').first)) one,
    ];

    const parts = {'table', 'tr', 'td'};

    test('cells, rows, and the rows together a table', () {
      expect(
        found(
          r'{\rtf1\trowd\cellx1\cellx2\pard\intbl a\cell b\cell\row'
          r'\trowd\cellx1\pard\intbl c\cell\row}',
          parts,
        ),
        [
          'table {} "abc"',
          'tr {} "ab"',
          'td {} "a"',
          'td {} "b"',
          'tr {} "c"',
          'td {} "c"',
        ],
      );
    });

    test('a row whose definition follows its cells, as Word writes it', () {
      expect(found(r'{\rtf1\pard\intbl a\cell{\trowd\cellx1\row}}', parts), [
        'table {} "a"',
        'tr {} "a"',
        'td {} "a"',
      ]);
    });

    test('a paragraph between two rows parts their tables', () {
      expect(
        found(
          r'{\rtf1\trowd\pard\intbl a\cell\row\pard b\par'
          r'\trowd\pard\intbl c\cell\row}',
          {'table'},
        ),
        ['table {} "a"', 'table {} "c"'],
      );
    });

    test('a table within a table is a diagnostic, and its text is read', () {
      final document = read(
        r'{\rtf1\trowd\pard\intbl\itap2 a\nestcell\cell\row}',
      );
      expect(problems(document, 3), contains(contains('within a table')));
      expect(found(r'{\rtf1\trowd\pard\intbl\itap1 a\cell\row}', parts), [
        'table {} "a"',
        'tr {} "a"',
        'td {} "a"',
      ]);
    });

    test('a HYPERLINK field is a link over its result', () {
      for (final instruction in [
        r'{\*\fldinst HYPERLINK "https://x.org"}',
        r'{\*\fldinst {HYPERLINK "https://x.org"}}',
        r'{\*\fldinst{ HYPERLINK "https://x.org" \o "tip"}}',
      ]) {
        expect(
          found(
            '{\\rtf1\\pard a {\\field$instruction{\\fldrslt site}} b\\par}',
            {'a', 'p'},
          ),
          ['p {} "a site b\n"', 'a {href: https://x.org} "site"'],
          reason: instruction,
        );
      }
    });

    test('another field is its result alone', () {
      expect(
        found(r'{\rtf1\pard {\field{\*\fldinst PAGE}{\fldrslt 3}}\par}', {
          'a',
          'p',
        }),
        ['p {} "3\n"'],
      );
    });

    test('a footnote, starred or not, holds its text', () {
      for (final mark in [r'\footnote', r'\*\footnote']) {
        expect(
          found('{\\rtf1\\pard a{$mark\\pard b\\par}c\\par}', {
            'footnote',
            'p',
          }),
          ['p {} "ab\nc\n"', 'footnote {} "b\n"'],
          reason: mark,
        );
      }
    });

    test(
      'a picture is an img, but the one Word gives again for old readers',
      () {
        expect(
          found(
            r'{\rtf1\pard a{\*\shppict{\pict 89ab}}{\nonshppict{\pict 89ab}}\par}',
            {'img', 'p'},
          ),
          ['p {} "a\n"', 'img {} ""'],
        );
      },
    );

    test('Cocoa\'s graphic is an img saying its file', () {
      expect(
        found(
          r'{\rtf1\pard {{\NeXTGraphic photo.png \width40 \height40}'
          '¬}\\par}',
          {'img'},
        ),
        ['img {src: photo.png} ""'],
      );
    });

    test('the samples\' tables and links, as each application wrote', () {
      for (final name in [
        'features-word',
        'features-libreoffice',
        'features-textedit',
      ]) {
        final tables = found(samples['$name.rtf']!, {'table', 'tr'});
        expect(tables, [
          'table {} "LoremIpsumDolorSit ametConsecteturAdipiscing"',
          'tr {} "LoremIpsum"',
          'tr {} "DolorSit amet"',
          'tr {} "ConsecteturAdipiscing"',
        ], reason: name);
      }
      expect(found(samples['features-word.rtf']!, {'a'}), [
        'a {href: https://example.com/lorem} "the lorem site"',
      ]);
    });
  });

  group('Revisions', () {
    /// [text]'s revisions, each its name, what it says and its content.
    List<String> revisions(String text) => [
      for (final one in elements(read(text)))
        if (RegExp(r'^(ins|del|format) ').hasMatch(one)) one,
    ];

    const table = r'{\*\revtbl {Unknown;}{Ann;}{Bob;}}';

    test('an insertion and a deletion say who made them, and when', () {
      expect(
        revisions(
          '{\\rtf1$table\\pard a{\\revised\\revauth1\\revdttm-1478421888 b}'
          '{\\deleted\\revauthdel2\\revdttmdel-941548834 c}d\\par}',
        ),
        [
          'ins {author: Ann, date: 2026-01-02T10:00} "b"',
          'del {author: Bob, date: 2026-01-03T11:30} "c"',
        ],
      );
    });

    test('a change of formatting says what it was before', () {
      expect(
        revisions(
          '{\\rtf1$table\\pard {\\b\\crauth1\\crdate132195072 '
          '{\\*\\oldcprops \\b0\\crauth1\\crdate132195072 }x}\\par}',
        ),
        ['format {author: Ann, date: 2026-01-04T12:00, was: \\b0} "x"'],
      );
    });

    test('an author past the table is a diagnostic', () {
      final document = read(
        '{\\rtf1$table\\pard {\\revised\\revauth7 x}\\par}',
      );
      expect(revisions('{\\rtf1$table\\pard {\\revised\\revauth7 x}\\par}'), [
        'ins {} "x"',
      ]);
      expect(problems(document, 3), contains(contains('author 7')));
    });

    test('Word\'s and LibreOffice\'s, as the samples have them', () {
      const both = [
        'ins {author: Ann Author, date: 2026-01-02T10:00} '
            '"consectetur adipiscing elit, "',
        'del {author: Bob Editor, date: 2026-01-03T11:30} '
            '"sed do eiusmod tempor, "',
      ];
      expect(revisions(samples['revisions-libreoffice.rtf']!), both);
      expect(revisions(samples['revisions-word.rtf']!), [
        ...both,
        'format {author: Ann Author, date: 2026-01-04T12:00, was: \\b0} '
            '"incididunt ut labore"',
      ]);
    });
  });

  group('Edits and writing', () {
    test('no text edit is valid, and no structural edit is made', () {
      final document = read(r'{\rtf1\pard ab\par}');
      expect(
        document.grammar.valid(document, Edit(1, Insert(13, Text.of('x')))),
        isA<Failure<Change<int>>>(),
      );
      refused(
        document,
        Edit(3, Mark(over(at(document, 'ab'), 1, {'': 'em'}))),
        'not edited',
      );
    });

    test('a document read in another syntax is not written as RTF', () {
      expect(
        rtf.encode(decoded(const Markdown(), '# a\n')),
        isA<Failure<Sequence<int>>>().having(
          (failure) => failure.message,
          'message',
          contains('only a document read as RTF'),
        ),
      );
    });
  });

  group('After an edit', () {
    test('every sample, typed in at random, reads as a fresh read does', () {
      for (final (index, MapEntry(key: name, value: text))
          in samples.entries.indexed) {
        final random = Random(0x7E77 + index);
        var document = read(text);
        for (var step = 0; step < 25; step++) {
          final length = document.items.length;
          // Past the signature, which an edit that took it away would
          // leave no RTF to read.
          final start = 5 + random.nextInt(length - 5);
          final Command<int> command = random.nextBool()
              ? Insert(
                  start,
                  Text.of(
                    text
                        .substring(random.nextInt(text.length - 8))
                        .substring(0, 1 + random.nextInt(7)),
                  ),
                )
              : Delete(
                  value(
                    Range.create(
                      start,
                      min(length - start, 1 + random.nextInt(8)),
                    ),
                  ),
                );
          document = value(document.apply(Edit(1, command))).document;
          expect(
            layers(document),
            layers(read(string(document.items))),
            reason: '$name, step $step, after $command',
          );
        }
      }
    });
  });

  group('Importing', () {
    const blocks = {
      'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'td', 'th', 'pre', //
      'blockquote',
    };
    const faces = {'strong', 'em', 'u', 's', 'sup', 'sub', 'code', 'a'};
    String words(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

    /// [document]'s blocks, each its name and its own words: those of no
    /// list or footnote within it.
    List<String> owned(Layered<int> document) {
      final (:content, :offsets, :elements) = projected(document);
      final apart = [
        for (final element in elements)
          if (const {'ul', 'ol', 'footnote'}.contains(element.name))
            (offsets[element.first], offsets[element.last]),
      ];
      return [
        for (final element in elements)
          if (blocks.contains(element.name))
            if (words(
                  [
                    for (
                      var at = offsets[element.first];
                      at < offsets[element.last];
                      at++
                    )
                      if (!apart.any(
                        (one) =>
                            one.$1 <= at &&
                            at < one.$2 &&
                            one.$1 >= offsets[element.first] &&
                            one.$2 <= offsets[element.last] &&
                            !(one.$1 == offsets[element.first] &&
                                one.$2 == offsets[element.last]),
                      ))
                        content[at],
                  ].join(),
                )
                case final text when text.isNotEmpty)
              '${element.name} $text',
      ];
    }

    for (final name in [
      for (final file in Directory(
        'test/samples/rtf',
      ).listSync().whereType<File>())
        if (file.path.endsWith('.rtf'))
          file.uri.pathSegments.last.replaceAll('.rtf', ''),
    ]..sort()) {
      test('$name agrees with its reference', () {
        final reference = jsonDecode(
          File('test/samples/rtf/$name.json').readAsStringSync(),
        ) as Map<String, Object?>;
        // The references keep what was deleted, as the import does where
        // it keeps revisions.
        final document = value(
          RTFImport(revisions: name.startsWith('revisions'))
              .decode(Text.of(samples['$name.rtf']!)),
        );
        final theirs = [
          for (final block in (reference['blocks'] as List).cast<Map>())
            '${block['name']} ${words('${block['text']}')}',
        ];
        // The style table makes a title a heading and a quotation a
        // blockquote, and a header row's cells are th, as LibreOffice's
        // reading does not have them.
        final blocked = owned(document);
        expect([
          for (final one in blocked)
            one
                .replaceFirst(RegExp(r'^h1 (?=Lorem Ipsum$)'), 'p ')
                .replaceFirst(RegExp(r'^blockquote '), 'p ')
                .replaceFirst(RegExp(r'^th '), 'td '),
        ], theirs);
        // A face over a whole heading or quotation is its style's, which
        // the import keeps as the block's and no face of its own.
        final styled = {
          for (final one in blocked)
            if (RegExp(r'^(h\d|blockquote) ').hasMatch(one))
              one.substring(one.indexOf(' ') + 1),
        };
        final (:content, :offsets, :elements) = projected(document);
        final ours = [
          for (final element in elements)
            if (faces.contains(element.name))
              (
                element.name,
                words(
                  content.substring(
                    offsets[element.first],
                    offsets[element.last],
                  ),
                ),
              ),
        ];
        for (final face in (reference['faces'] as List).cast<Map>()) {
          if (faces.contains(face['name']) &&
              !styled.contains(words('${face['text']}'))) {
            expect(
              ours.any(
                (one) =>
                    one.$1 == face['name'] &&
                    one.$2.contains(words('${face['text']}')),
              ),
              isTrue,
              reason: '${face['name']} "${face['text']}"',
            );
          }
        }
      });
    }
  });

  group('The importer', () {
    const kept = {
      'p', 'h1', 'h2', 'h3', 'li', 'ul', 'ol', 'td', 'th', 'tr', 'table', //
      'blockquote', 'strong', 'em', 'u', 's', 'sup', 'sub', 'code', 'a',
      'footnote',
    };

    /// [document]'s elements of [kept], each its name and its words.
    List<String> held(Layered<int> document) {
      final (:content, :offsets, :elements) = projected(document);
      return [
        for (final element in elements)
          if (kept.contains(element.name))
            '${element.name} ${element.said['href'] ?? ''}'
                '${content.substring(offsets[element.first], offsets[element.last])}',
      ]..sort();
    }

    test('reads what the format reads, but its header', () {
      for (final name in samples.keys.where((one) => !one.startsWith('rev'))) {
        expect(
          held(value(const RTFImport().decode(Text.of(samples[name]!)))),
          held(read(samples[name]!)),
          reason: name,
        );
      }
    });

    test('accepts every revision unless asked to keep them', () {
      final (:content, offsets: _, elements: _) = projected(
        value(
          const RTFImport().decode(Text.of(samples['revisions-word.rtf']!)),
        ),
      );
      expect(content, contains('consectetur adipiscing elit, incididunt'));
      expect(content, isNot(contains('sed do eiusmod tempor, ')));
    });

    test('keeps revisions as annotations that move with their text', () {
      final document = value(
        const RTFImport(revisions: true)
            .decode(Text.of(samples['revisions-word.rtf']!)),
      );
      List<String> noted(Layered<int> document) => [
        for (final (_, range) in document.annotations(1))
          '${said(range, '')} ${said(range, 'author')} ${said(range, 'date')} '
              '"${string(document.items.slice(range.start, range.length)).replaceAll(RegExp(r'\[[^\]]*[}\]]|\{[^\]]*\]'), '')}"',
      ];
      const expected = [
        'ins Ann Author 2026-01-02T10:00 "consectetur adipiscing elit, "',
        'del Bob Editor 2026-01-03T11:30 "sed do eiusmod tempor, "',
        'format Ann Author 2026-01-04T12:00 "incididunt ut labore"',
      ];
      expect(noted(document), expected);
      final typed = value(document.apply(Edit(1, Insert(4, Text.of('xyz')))))
          .document;
      expect(noted(typed), expected);
    });
  });

  group('Hostile input', () {
    /// That reading [text] gives a document or a failure, and no exception.
    void survives(String text) {
      final result = rtf.decode(Text.of(text));
      expect(
        result,
        anyOf(isA<Success<Layered<int>>>(), isA<Failure<Layered<int>>>()),
      );
      if (result case Success(value: final document)) {
        expect(string(document.items), text);
        expect(
          value(const RTFImport().decode(Text.of(text))),
          isA<Layered<int>>(),
        );
      }
    }

    test('a \\bin past the end', () {
      survives(r'{\rtf1\pard \bin999999999 ab\par}');
      expect(problems(read(r'{\rtf1\pard \bin999999999 ab}'), 2), isNotEmpty);
    });

    test(
      'a \\uc of a million',
      () => survives(r'{\rtf1섀0000 \pard \u233?a\par}'),
    );

    test('groups nested ten thousand deep, and never closed', () {
      survives('{\\rtf1 ${'{\\b ' * 10000}a');
      survives('{\\rtf1 ${'{\\b ' * 10000}a${'}' * 10000}}');
    });

    test('a parameter past ten digits, and a control word past 32 letters', () {
      survives('{\\rtf1\\fs${'9' * 40} a\\${'x' * 50} b}');
    });

    test('a style, font, list or author table that is not what it says', () {
      survives(
        r'{\rtf1{\stylesheet{\s}{;}}{\fonttbl\f;}{\*\listtable{\list}}'
        r'{\*\listoverridetable{\listoverride\ls}}{\*\revtbl}'
        r'\pard\s99\ls5\ilvl99 {\revised\revauth99\revdttm-1 a}\par}',
      );
    });
  });
}
