import 'dart:io';

import 'package:_fe_analyzer_shared/src/scanner/scanner.dart' as reference;
import 'package:_fe_analyzer_shared/src/scanner/token.dart' as reference;
import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'dart_syntax.dart';
import 'harness.dart';

/// Dart: tokens as the Dart scanner reads them, checked against that
/// scanner on real source, and brackets paired over them.
void main() {
  const dart = Dart();

  /// The token names of [text], whitespace left out.
  List<String> named(String text) => [
    for (final (name, _) in tokens(decoded(dart, text)))
      if (name != '#space') name,
  ];

  /// [document]'s pairs, each as its name and the text it covers.
  List<(String, String)> pairs(Layered<int> document) => [
    for (final (pair, text) in covering(document))
      if (const {
        'parens', 'brackets', 'braces', 'string', 'interpolation', //
      }.contains(said(pair, '')))
        (said(pair, '')!, text),
  ];

  group('Tokens', () {
    test('the text is kept verbatim', () {
      roundtrip(dart, "void main() {\n  print('hi \$name');\n}\n");
    });

    test('words, numbers, operators and comments', () {
      expect(
        tokens(decoded(dart, 'final x = 0x1F >> 2; // done\n/* a /* b */ */')),
        [
          ('#keyword', 'final'),
          ('#space', ' '),
          ('#name', 'x'),
          ('#space', ' '),
          ('=', '='),
          ('#space', ' '),
          ('#number', '0x1F'),
          ('#space', ' '),
          ('>>', '>>'),
          ('#space', ' '),
          ('#number', '2'),
          (';', ';'),
          ('#space', ' '),
          ('#comment', '// done'),
          ('#space', '\n'),
          ('#comment', '/* a /* b */ */'),
        ],
      );
    });

    test('a string is its quotes, characters, escapes and interpolations', () {
      expect(named(r"""'a\n$b${c + "d"}' r'$e'"""), [
        "'",
        '#text',
        '#escape',
        r'$',
        '#name',
        r'${',
        '#name',
        '+',
        '"',
        '#text',
        '"',
        '}',
        "'",
        "r'",
        '#text',
        "'",
      ]);
    });

    test('a token within a string says what is open where it starts', () {
      final document = decoded(dart, r"""'${"x"}'""");
      expect(
        [
          for (final range in document.layer(2).items)
            said(range as ARange, 'in'),
        ],
        [null, "'", "' {0", "' {0 \"", "' {0 \"", "' {0", "'"],
      );
    });

    test('a string of three quotes holds line breaks, its characters a token a '
        'line; of one, it ends there', () {
      expect(named("'''a\nb''' 'c\nd'"), [
        "'''",
        '#text',
        '#text',
        "'''",
        "'",
        '#text',
        '#name',
        "'",
      ]);
    });
  });

  group('Against the Dart scanner', () {
    final sources = [
      for (final directory in ['lib', 'test', '../libara/lib'])
        if (Directory(directory).existsSync())
          for (final file in Directory(directory).listSync(recursive: true))
            if (file is File && file.path.endsWith('.dart')) file,
    ];
    for (final file in sources) {
      test('${file.path} reads as the Dart scanner reads it', () {
        final text = file.readAsStringSync();
        expect(ours(decoded(dart, text)), theirs(text));
      });
    }
  });

  group('Declarations', () {
    test('each kind, with its name', () {
      const text = '''
import 'a.dart';
@immutable
abstract class A<T> extends B implements C {
  const A(this.x);
  A.named() : x = 1 { }
  factory A.from(int x) => A(x);
  final int x, y;
  static const Map<String, int> table = {'a': 1};
  final void Function(int) handler = (v) {};
  int get size => 1;
  set size(int value) {}
  bool operator ==(Object other) => true;
  @override
  String toString() { return ''; }
  List<List<int>> nested<E>(E e) => [];
}
mixin M on A<int> {}
enum E { a, b; void f() {} }
extension on String {}
extension type Id(int value) {}
typedef F = void Function();
typedef void G(int x);
final top = 1;
void main() {}
''';
      final ours = ourSyntax(decoded(dart, text));
      expect(ours, theirSyntax(text));
      expect(
        [
          for (final written in ours)
            if (written.split(' ') case [final kind, _, ...final name])
              kind == 'name' ? 'name:${name.join(' ')}' : kind,
        ],
        [
          'directive',
          'class', 'annotation', 'name:A', 'generic', 'name:T', //
          'constructor', 'name:A', 'parameter', 'name:x',
          'constructor', 'name:A.named', 'initializer', 'block',
          'constructor', 'name:A.from', 'parameter', 'name:x', 'call',
          'field', 'name:x', 'name:y',
          'field', 'type', 'name:table', 'map', 'entry',
          'field', 'type', 'parameter', 'name:handler',
          'closure', 'parameter', 'name:v', 'block',
          'getter', 'name:size',
          'setter', 'name:size', 'parameter', 'name:value', 'block',
          'method', 'name:operator ==', 'parameter', 'name:other',
          'method', 'annotation', 'name:toString', 'block', 'return',
          'method', 'type', 'type', 'name:nested', 'generic', 'name:E',
          'parameter', 'name:e', 'list',
          'mixin', 'name:M', 'type',
          'enum', 'name:E',
          'value', 'name:a',
          'value', 'name:b',
          'method', 'name:f', 'block',
          'extension',
          'extension', 'name:Id', 'parameter', 'name:value',
          'typedef', 'name:F', 'type',
          'typedef', 'name:G', 'parameter', 'name:x',
          'variable', 'name:top',
          'function', 'name:main', 'block',
        ],
      );
    });

    test('found by name without walking every token', () {
      final document = decoded(dart, 'class A { void b() {} }\nint c = 1;');
      expect(
        [
          for (final (_, range) in document.having(3, 'name'))
            said(range, 'name'),
        ],
        ['A', 'b', 'c'],
      );
    });
  });

  group('What a keystroke reads again', () {
    /// The stretches of layer 2's tokens that [edit] read layer 3 again
    /// over, having checked that the layers are a fresh read's.
    List<Range> regions(String text, Command<int> edit) {
      final document = decoded(dart, text);
      final change = value(document.apply(Edit(1, edit)));
      expect(
        layers(change.document),
        layers(decoded(dart, string(change.document.items))),
      );
      return change.layers[2].regions;
    }

    final members = [
      for (var index = 0; index < 200; index++)
        '  int method$index(int value) {\n    return value + $index;\n  }\n',
    ].join();
    final text = 'class Alpha {\n  Alpha();\n$members}\n';

    /// How many tokens the regions of [edit] to [text] take in.
    int read(Command<int> edit) =>
        regions(text, edit).fold(0, (count, region) => count + region.length);

    test('typing in a class name reads only that name', () {
      final at = text.indexOf('Alpha') + 2;
      expect(read(Insert(at, Text.of('x'))), lessThanOrEqualTo(3));
    });

    test('typing in a name within a body reads only what starts or ends '
        'at it', () {
      // `value + 100`, which starts with the name: its five tokens.
      final at = text.indexOf('value + 100') + 2;
      expect(read(Insert(at, Text.of('x'))), lessThanOrEqualTo(6));
    });

    test('a keystroke in a statement reads only the statements around it', () {
      final body = [
        for (var index = 0; index < 100; index++) '    total += $index;\n',
      ].join();
      final text = 'int sum(int total) {\n$body  return total;\n}\n';
      final at = text.indexOf('+= 50');
      // `total += 49;` and `total += 50;`, read from where one starts.
      expect(
        regions(
          text,
          Replace(value(Range.create(at, 1)), Text.of('-')),
        ).fold(0, (count, region) => count + region.length),
        lessThanOrEqualTo(20),
      );
    });

    test('a keystroke in an expression outside a body reads its '
        'declaration', () {
      final fields = [
        for (var index = 0; index < 100; index++)
          '  final int field$index = g($index + 1);\n',
      ].join();
      final text = 'class Beta {\n$fields}\n';
      final at = text.indexOf('50 + 1') + 3;
      // `final int field50 = g(50 - 1);`: its seventeen tokens, spaces
      // included, the operator among them read again with the rest.
      expect(
        regions(
          text,
          Replace(value(Range.create(at, 1)), Text.of('-')),
        ).fold(0, (count, region) => count + region.length),
        lessThanOrEqualTo(17),
      );
    });
  });

  group('Declarations against the analyzer', () {
    for (final file in [
      for (final directory in ['lib', 'test', '../libara/lib'])
        if (Directory(directory).existsSync())
          for (final file in Directory(directory).listSync(recursive: true))
            if (file is File && file.path.endsWith('.dart')) file,
    ]) {
      test('${file.path} declares what the analyzer says it does', () {
        final text = file.readAsStringSync();
        expect(ourSyntax(decoded(dart, text)), theirSyntax(text));
      });
    }
  });

  group('Statements', () {
    /// The kinds of [text]'s elements other than pairs, in pre-order, a
    /// name as `name:` and what it says.
    List<String> kinds(String text) => [
      for (final written in ourSyntax(decoded(dart, text)))
        if (written.split(' ') case [final kind, _, ...final name])
          kind == 'name' ? 'name:${name.join(' ')}' : kind,
    ];

    test('each form, as the analyzer reads it', () {
      const text = r"""
void f(List<int> xs, Stream<int> stream) async {
  var a = 1, b;
  int g(int x) => x + 1;
  if (a > 0) a++; else { b = a; }
  for (var i = 0; i < 3; i++) {}
  await for (final x in stream) print(x);
  while (a < 9) a += 2;
  do a--; while (a > 0);
  outer: switch (a) { case 1: break outer; default: a = 0; }
  try { throw 1; } on StateError catch (e, s) { rethrow; } finally {}
  assert(a == 0, 'zero');
  xs.forEach((x) { print(x); });
  return;
}
Iterable<int> h() sync* { yield 1; }
""";
      expect(ourSyntax(decoded(dart, text)), theirSyntax(text));
      expect(kinds(text), [
        'function', 'name:f', //
        'parameter', 'type', 'name:xs',
        'parameter', 'type', 'name:stream',
        'block',
        'variable', 'name:a', 'name:b',
        'function', 'name:g', 'parameter', 'name:x', 'binary',
        'if', 'binary', 'statement', 'postfix',
        'block', 'statement', 'assignment',
        'for', 'variable', 'name:i', 'binary', 'postfix', 'block',
        'for', 'variable', 'name:x', 'statement', 'call',
        'while', 'binary', 'statement', 'assignment',
        'do', 'statement', 'postfix', 'binary',
        'label', 'switch',
        'case', 'break',
        'case', 'statement', 'assignment',
        'try', 'block', 'statement', 'throw',
        'catch', 'name:e', 'name:s', 'block', 'statement',
        'finally', 'block',
        'assert', 'binary',
        'statement', 'call', 'closure', 'parameter', 'name:x', 'block',
        'statement', 'call',
        'return',
        'function', 'type', 'name:h', 'block', 'yield',
      ]);
    });

    group('what does not read as it should', () {
      /// The diagnostics of layer 3 of a function whose body holds
      /// [body], having checked that its body still holds [standing].
      List<String> read(String body, List<String> standing) {
        final document = decoded(dart, 'void f() {\n  $body\n}\n');
        expect(kinds(string(document.items)).skip(3), standing);
        return problems(document, 3);
      }

      test('a statement with no `;`', () {
        expect(read('return x', ['return']), ['expected ;']);
        expect(read('do a(); while (c)', ['do', 'statement', 'call']), [
          'expected ;',
        ]);
      });

      test('an unfinished expression', () {
        expect(read('x = 1 +', ['assignment', 'statement', 'binary']), [
          'expected an expression',
          'expected ;',
        ]);
        expect(read('var x = ;', ['variable', 'name:x']), [
          'expected an expression',
        ]);
      });

      test('a stray `else`', () {
        expect(
          read('if (c) a(); else b(); else c();', [
            'if', 'statement', 'call', 'statement', 'call', //
            'statement', 'call',
          ]),
          ['unexpected else'],
        );
      });

      test('a statement that should follow', () {
        expect(read('if (c)', ['if']), ['expected a statement']);
        expect(read('if (c', ['if']), [
          'expected a statement',
          'unclosed parens',
        ]);
      });

      test('a block nothing closes', () {
        expect(read('while (c) {', ['while', 'block']), ['unclosed braces']);
      });

      test(
        'a statement\'s diagnostic is read again with a block within it',
        () {
          // The closure's block, read again alone, would leave out the
          // `expected ;` of the statement that holds it.
          const text = "n(){(){['' ]";
          edited(
            dart,
            decoded(dart, text),
            Edit(1, Insert(text.indexOf("''") + 2, Text.of('isN'))),
          );
        },
      );

      test('what a closure is turns on the whole of what `=>` returns', () {
        // Once `while` is a name, the braces after `(...)` are a closure's.
        const text = "g()=>( ( while(''){)";
        edited(
          dart,
          decoded(dart, text),
          Edit(1, Delete(value(Range.create(text.indexOf('ile'), 3)))),
        );
      });

      test('a switch a block ends with, nothing closing either', () {
        const text = 'd(){switch(r){ i(){}e:n m,';
        edited(
          dart,
          decoded(dart, text),
          Edit(1, Delete(value(Range.create(text.indexOf(' m'), 1)))),
        );
      });

      test('typing in an unexpected name keeps what is said of it', () {
        // Read again from the name alone, the diagnostic is the one read
        // before, so it says what the name is rather than its text.
        const text = 'void f() { a = (b c); }';
        final document = edited(
          dart,
          decoded(dart, text),
          Edit(1, Insert(text.indexOf('c)') + 1, Text.of('d'))),
        );
        expect(problems(document, 3), ['unexpected name']);
      });

      test('a try with nothing after its block', () {
        expect(read('try {}', ['try', 'block']), ['expected catch or finally']);
        expect(read('try {} catch {}', ['try', 'block', 'catch', 'block']), [
          'expected (',
        ]);
      });
    });
  });

  group('Expressions', () {
    /// The kinds of [text]'s elements other than pairs, in pre-order, a
    /// name as `name:` and what it says.
    List<String> kinds(String text) => [
      for (final written in ourSyntax(decoded(dart, text)))
        if (written.split(' ') case [final kind, _, ...final name])
          kind == 'name' ? 'name:${name.join(' ')}' : kind,
    ];

    test('each form, as the analyzer reads it', () {
      const text = r"""
f(a, b, c, List<int> xs) async {
  a = b ?? c ? -a : !b;
  a += b is int? ? 1 : 2;
  c = (a as num) < 2 || b != null && xs[0] > 1;
  await g<int>(1, named: [...xs, if (a) 1 else 2, for (final x in xs) x]);
  final m = const <String, int>{'k': 1}, s = {1, ?a}, r = (1, n: 2);
  xs..add(1)..[0] = 2;
  a?.b.c!(d)++;
  b = [new p.A<int>.named(), List<int>.filled(1, 0), f<int>, #a.b];
  c = 'a' "b ${a.b}";
  final v = switch (a) { 1 => 'one', _ => throw StateError('') };
  b = (x) => x;
  c = .red;
}
""";
      expect(ourSyntax(decoded(dart, text)), theirSyntax(text));
      expect(kinds(text), [
        'function', 'name:f', //
        'parameter', 'name:a', 'parameter', 'name:b', 'parameter', 'name:c',
        'parameter', 'type', 'name:xs',
        'block',
        'statement', 'assignment', 'conditional', 'binary', 'prefix',
        'prefix',
        'statement', 'assignment', 'conditional', 'is', 'type',
        'statement', 'assignment', 'binary', 'binary', 'as', 'binary',
        'binary', 'binary', 'index',
        'statement', 'prefix', 'call', 'argument', 'list', 'spread', 'if',
        'for', 'variable', 'name:x',
        'variable', 'name:m', 'map', 'entry', 'name:s', 'set', 'aware',
        'name:r', 'record', 'argument',
        'statement', 'cascade', 'call', 'section', 'assignment', 'section',
        'index',
        'statement', 'postfix', 'call', 'postfix', 'property', 'property',
        'statement', 'assignment', 'list', 'call', 'type', 'call', 'type',
        'instantiation', 'symbol',
        'statement', 'assignment', 'strings', 'property',
        'variable', 'name:v', 'switch', 'case', 'case', 'throw', 'call',
        'statement', 'assignment', 'closure', 'parameter', 'name:x',
        'statement', 'assignment', 'property',
      ]);
    });

    test('what does not read as it should', () {
      final cases = {
        'a = 1 b = 2;': (
          ['assignment', 'statement', 'statement', 'assignment'],
          ['expected ;'],
        ),
        'a = b ? c;': (
          ['statement', 'assignment', 'conditional'],
          ['expected :'],
        ),
        'f(a b);': (['statement', 'call'], ['unexpected name']),
        'x = a is;': (['statement', 'assignment', 'is'], ['expected a type']),
        'x = [1, 2 3];': (
          ['statement', 'assignment', 'list'],
          ['unexpected number'],
        ),
        'x = 1 +;': (
          ['statement', 'assignment', 'binary'],
          ['expected an expression'],
        ),
        'x = switch (a) { 1 2 };': (
          ['statement', 'assignment', 'switch', 'case'],
          ['expected =>'],
        ),
      };
      for (final MapEntry(key: body, value: (standing, said))
          in cases.entries) {
        final text = 'void f() {\n  $body\n}\n';
        expect(kinds(text).skip(3), standing, reason: body);
        expect(problems(decoded(dart, text), 3), said, reason: body);
      }
    });
  });

  group('Patterns', () {
    /// The kinds of [text]'s elements other than pairs, in pre-order, a
    /// name as `name:` and what it says, and a pattern as `pattern:` and
    /// its form.
    List<String> kinds(String text) => [
      for (final written in ourSyntax(decoded(dart, text)))
        if (written.split(' ') case [final kind, _, ...final said])
          said.isEmpty ? kind : '$kind:${said.join(' ')}',
    ];

    test('each form, as the analyzer reads it', () {
      const text = r"""
f(o) {
  switch (o) {
    case Point(:x, y: var b) when b > 0:
    case [1, ...var rest] || {'k': _}:
    case (int a, String _) && (var c, final d?):
    case > 1 && < 9 || == -1:
    case a.b.c as int:
    case final int e!:
    case const Foo(1):
    case (5):
    case x:
      break;
  }
  if (o case int n when n > 0) {}
  var (p, q) = o;
  final [r, ...] = o;
  for (var (s, t) in o) {}
  (p, q) = (q, p);
  var v = switch (o) { Point(:var x) => x, _ => 0 };
}
""";
      expect(ourSyntax(decoded(dart, text)), theirSyntax(text));
      expect(kinds(text), [
        'function', 'name:f', 'parameter', 'name:o', 'block', 'switch', //
        'case', 'pattern:object', 'argument', 'argument', 'pattern:variable',
        'name:b', 'binary',
        'case', 'pattern:logical', 'pattern:list', 'pattern:rest',
        'pattern:variable', 'name:rest', 'pattern:map', 'entry',
        'case', 'pattern:logical', 'pattern:record', 'pattern:variable',
        'name:a', 'pattern:wildcard', 'pattern:record', 'pattern:variable',
        'name:c', 'pattern:check', 'pattern:variable', 'name:d',
        'case', 'pattern:logical', 'pattern:logical', 'pattern:relational',
        'pattern:relational', 'pattern:relational', 'prefix',
        'case', 'pattern:cast', 'pattern:constant', 'property', 'property',
        'case', 'pattern:assert', 'pattern:variable', 'name:e',
        'case', 'pattern:constant', 'call',
        'case',
        'case', 'break',
        'if', 'pattern:variable', 'name:n', 'binary', 'block',
        'variable', 'pattern:record', 'name:p', 'name:q',
        'variable', 'pattern:list', 'name:r',
        'for', 'pattern:record', 'name:s', 'name:t', 'block',
        'statement', 'assignment', 'pattern:record', 'record',
        'variable', 'name:v', 'switch',
        'case', 'pattern:object', 'argument', 'pattern:variable', 'name:x',
        'case',
      ]);
    });

    test('a guard ends at the `=>` of its arm', () {
      // `(b) =>` would be a closure anywhere else.
      const text = 'f(o) => switch (o) { (a, b) when a > (b) => 1, _ => 2 };';
      expect(ourSyntax(decoded(dart, text)), theirSyntax(text));
    });

    test('what does not read as it should', () {
      final cases = {
        'switch (o) { case : break; }': (
          ['switch', 'case', 'break'],
          ['expected a pattern'],
        ),
        'var (a, b);': (
          ['variable', 'pattern:record', 'name:a', 'name:b'],
          ['expected ='],
        ),
        'if (o case [1, 2 3]) {}': (
          ['if', 'pattern:list', 'block'],
          ['unexpected number'],
        ),
        'switch (o) { case final : break; }': (
          ['switch', 'case', 'break'],
          ['expected a name'],
        ),
      };
      for (final MapEntry(key: body, value: (standing, said))
          in cases.entries) {
        final text = 'void f() {\n  $body\n}\n';
        expect(kinds(text).skip(3), standing, reason: body);
        expect(problems(decoded(dart, text), 3), said, reason: body);
      }
    });
  });

  group('Pairs', () {
    test('brackets, strings and interpolations over their tokens', () {
      expect(pairs(decoded(dart, r"f(a[0], {'k': '$x${y}'})")), [
        ('parens', r"(a[0], {'k': '$x${y}'})"),
        ('brackets', '[0]'),
        ('braces', r"{'k': '$x${y}'}"),
        ('string', "'k'"),
        ('string', r"'$x${y}'"),
        ('interpolation', r'${y}'),
      ]);
    });

    test('what does not pair is said, and the rest is paired', () {
      final cases = {
        'f(a]': ['unclosed parens', '] closes nothing'],
        'f(a': ['unclosed parens'],
        // A line break ends the string, so `y` stands where `;` should.
        "x = 'a\ny;": ['unexpected name', 'unclosed string'],
        // The second quote opens a string within the interpolation.
        r"'${a'": [
          'unclosed string',
          'unclosed interpolation',
          'unclosed string',
        ],
        '{(}': ['unclosed parens'],
        ')': [') closes nothing'],
      };
      for (final MapEntry(key: text, value: said) in cases.entries) {
        expect(problems(decoded(dart, text), 3), said, reason: text);
      }
    });
  });

  group('Editing', () {
    test('the layers after random edits are those a fresh read gives', () {
      for (final (index, name) in [
        'lib/src/json/json.dart',
        'lib/src/dart/dart.dart',
        'test/dart_test.dart',
      ].indexed) {
        derivable(dart, File(name).readAsStringSync(), seed: index + 1);
      }
      // Source broken by the edits, around a token in error that a
      // keystroke elsewhere leaves as it was.
      derivable(
        dart,
        File('test/roff_edit_test.dart').readAsStringSync(),
        seed: 14,
      );
      // A `<` the edits leave unclosed, with a `>` in a later declaration.
      derivable(
        dart,
        File('test/harness_test.dart').readAsStringSync(),
        seed: 11,
      );
      // A declaration whose kind turns on the item after it, past the
      // stretch read again.
      derivable(
        dart,
        File('lib/libara_formats.dart').readAsStringSync(),
        seed: 14,
      );
      // A class body and a method's body the edits leave ending together.
      derivable(
        dart,
        File('test/harness_test.dart').readAsStringSync(),
        seed: 19,
      );
    });

    test('characters a broken quote no longer ends join those before it', () {
      const text = "f(r'''abc''');";
      final document = decoded(dart, text);
      edited(
        dart,
        document,
        Edit(1, Insert(text.indexOf("''');") + 1, Text.of(' x'))),
      );
    });

    test('a \$ is read with the name after it, however the reading ends', () {
      const text = "f('MARK:\$text', 1);";
      final document = decoded(dart, text);
      edited(
        dart,
        document,
        Edit(1, Insert(text.indexOf(r'$'), Text.of('goes'))),
      );
    });

    test(
      'a string a line break ends stays ended where a comment becomes code',
      () {
        const text = "x = 'a\n// one\n// note\ny;";
        final document = decoded(dart, text);
        edited(
          dart,
          document,
          Edit(1, Delete(value(Range.create(text.indexOf('// note'), 2)))),
        );
      },
    );

    test('a token reads the same however soon the text after it ends', () {
      // A reading of a stretch ends where the stretch does, so what a token
      // is may depend on no more than the character after it; a `\$` is
      // the one exception, and a reading never ends just after one.
      const samples = [
        r"'\u{1x}'",
        r"'\u{1234567}'",
        r"'\x4g' '\u12'",
        r"f(1.e5, .5e, 0x, a?..b, r'q', '\$a');",
      ];
      for (final text in samples) {
        final whole = tokens(decoded(dart, text));
        var end = 0;
        for (final (index, (name, covered)) in whole.indexed) {
          end += covered.length;
          if (name == r'$') {
            continue;
          }
          expect(
            tokens(decoded(dart, text.substring(0, end))),
            whole.take(index + 1).toList(),
            reason: text.substring(0, end),
          );
        }
      }
    });

    test('a member whose name loses its capital is a method', () {
      const text = 'class Rendering {\n  Rendering(this.data);\n}\n';
      edited(
        dart,
        decoded(dart, text),
        Edit(1, Delete(value(Range.create(text.indexOf('Rendering('), 8)))),
      );
    });

    test('a declaration ended by what follows it takes in what now does', () {
      // `int en` ends at the comma, which no name follows, until the `-`
      // after it, past comments, goes.
      const text = 'int en, /* a */ /* b */ -order;\nvoid f() {}\n';
      edited(
        dart,
        decoded(dart, text),
        Edit(1, Delete(value(Range.create(text.indexOf('-'), 1)))),
      );
    });

    test('a member first in a body left open is read with the body', () {
      // The open brace's diagnostic touches the stretch read again, which
      // takes in the brace but not the rest of its pair.
      const text = 'class W {\n  /// x.\n  final String c;\n';
      edited(
        dart,
        decoded(dart, text),
        Edit(1, Delete(value(Range.create(text.indexOf('final') + 3, 1)))),
      );
    });

    test(
      'the characters of strings and comments are text, and nothing else is',
      () {
        const text = "var s = 'word'; // note\n";
        final document = decoded(dart, text);
        Result<Change<int>> typed(String after, String typed) =>
            document.grammar.valid(
              document,
              Edit(
                1,
                Insert(text.indexOf(after) + after.length, Text.of(typed)),
              ),
            );
        expect(typed("'wo", 'x'), isA<Success<Change<int>>>());
        expect(typed('// no', 'x'), isA<Success<Change<int>>>());
        expect(typed("'wo", "'"), isA<Failure<Change<int>>>());
        expect(typed('va', 'x'), isA<Failure<Change<int>>>());
        expect(typed('// no', '\n'), isA<Failure<Change<int>>>());
      },
    );

    test('escaped text goes into a string as the same characters', () {
      const typed = "it's \"quoted\" \\ \$cost\nend";
      final document = decoded(dart, "var s = '';");
      final written = document.grammar.escaped(typed.runes.toList());
      final made = value(
        document.grammar.valid(document, Edit(1, Insert(9, Items.of(written)))),
      ).document;
      final shown = [
        for (final range in made.layer(2).items.cast<ARange>())
          if (said(range, '') == '#text')
            string(made.slice(range))
          else if (said(range, '') == '#escape')
            said(range, 'shows')!,
      ].join();
      expect(shown, typed);
    });

    test('a structural edit is refused', () {
      final document = decoded(dart, 'f();');
      refused(document, Edit(2, Delete(value(Range.create(0, 1)))), 'dart');
    });
  });
}

/// What [document] reads as, in the Dart scanner's terms: each token as
/// its kind and its text, a string's quotes, characters and escapes between
/// interpolations being one string, and whitespace and comments left out.
List<String> ours(Layered<int> document) {
  final kinds = <String>[];
  final piece = StringBuffer();
  void flush() {
    if (piece.isNotEmpty) {
      kinds.add('STRING:$piece');
      piece.clear();
    }
  }

  for (final range in document.layer(2).items.cast<ARange>()) {
    final name = said(range, '')!;
    final text = string(document.slice(range));
    final quote = const {
      "'", '"', "'''", '"""', "r'", 'r"', "r'''", 'r"""', //
    }.contains(name);
    if (quote || name == '#text' || name == '#escape') {
      // A quote that opens a string starts a piece of its own.
      final within = said(range, 'in');
      final closing =
          quote && within != null && !within.split(' ').last.startsWith('{');
      if (quote && !closing) {
        flush();
      }
      piece.write(text);
      if (closing) {
        flush();
      }
      continue;
    }
    flush();
    if (name == '#space' || name == '#comment' && !text.startsWith('#!')) {
      continue;
    }
    kinds.add(switch (name) {
      '#comment' => 'SCRIPT:$text',
      '#name' => 'NAME:$text',
      '#keyword' => 'KEYWORD:$text',
      '#number' => 'NUMBER:$text',
      _ => 'MARK:$text',
    });
  }
  flush();
  return kinds;
}

/// What the Dart scanner reads [text] as, in the same terms.
List<String> theirs(String text) {
  final kinds = <String>[];
  reference.Token? token = reference.scanString(text).tokens;
  while (token != null && !token.isEof) {
    final type = token.type;
    // It reads an empty piece between two interpolations side by side.
    if (type == reference.TokenType.STRING && token.lexeme.isEmpty) {
      token = token.next;
      continue;
    }
    kinds.add(switch (type) {
      _ when token.isKeyword => 'KEYWORD:${token.lexeme}',
      reference.TokenType.IDENTIFIER => 'NAME:${token.lexeme}',
      reference.TokenType.STRING => 'STRING:${token.lexeme}',
      reference.TokenType.SCRIPT_TAG => 'SCRIPT:${token.lexeme}',
      reference.TokenType.INT ||
      reference.TokenType.INT_WITH_SEPARATORS ||
      reference.TokenType.DOUBLE ||
      reference.TokenType.DOUBLE_WITH_SEPARATORS ||
      reference.TokenType.HEXADECIMAL ||
      reference.TokenType.HEXADECIMAL_WITH_SEPARATORS =>
        'NUMBER:${token.lexeme}',
      _ => 'MARK:${token.lexeme}',
    });
    token = token.next;
  }
  return kinds;
}
