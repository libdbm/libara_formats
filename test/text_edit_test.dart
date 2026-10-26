import 'dart:io';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:libara_formats/src/convert.dart';
import 'package:libara_formats/src/lexing.dart' show span;
import 'package:test/test.dart';

import 'harness.dart';

/// What a syntax says a text edit may do, and how it writes text alone:
/// every sample takes escaped punctuation into its words as the same words
/// and no markup, and refuses markup typed raw and an edit reaching into a
/// tag.
void main() {
  /// Every character that some syntax here reads as markup, and one it may
  /// represent by name.
  const typed =
      r'<>&"'
      "'"
      r'*_[]`\{}$#%^~|!-+=()é';

  /// Markup written raw in each syntax.
  const raw = {
    'xml': '<b>x</b>',
    'html': '<b>x</b>',
    'lmnl': '[b}x{b]',
    'md': '`x`',
    'tex': r'\textbf{x}',
    '1': r'\fBx\fR',
    'ms': r'\fBx\fR',
  };

  /// [change] at layer 1, as [document]'s grammar says it may make it.
  Result<Change<int>> valid(Layered<int> document, Command<int> change) =>
      document.grammar.valid(document, Edit(1, change));

  for (final file in Directory('test/samples').listSync().whereType<File>()) {
    final extension = file.path.split('.').last;
    final syntax = formats[extension];
    if (syntax == null) {
      continue;
    }
    final name = file.path.split('/').last;
    final document = decoded(syntax, file.readAsStringSync());
    final tokens = document.layer(2).items.cast<ARange>().toList();

    final written = document.grammar.escaped(typed.runes.toList());

    /// Between the first two letters of a word, from the middle of the text
    /// outward, the first place the escaped text may go: a place in the
    /// words, and not in code, say, where what is written is read as it
    /// stands.
    (int, Result<Change<int>>)? place() {
      final words = [
        for (final (index, token) in tokens.indexed)
          if (token.get('') == Str(Text.of('#text')) &&
              token.length > 1 &&
              _letter(document.items.items.elementAt(token.start)) &&
              _letter(document.items.items.elementAt(token.start + 1)))
            index,
      ];
      final middle = words.length ~/ 2;
      final outward = [
        ...words.skip(middle),
        ...words.take(middle).toList().reversed,
      ];
      for (final index in outward) {
        final made = valid(
          document,
          Insert(tokens[index].start + 1, Items.of(written)),
        );
        if (made is Success) {
          return (index, made);
        }
      }
      return null;
    }

    test('$name takes escaped text as the same text, and no markup', () {
      final placed = place();
      expect(placed, isNotNull, reason: 'nowhere took $written');
      final (index, made) = placed!;
      final before = projected(document);
      final after = projected(value(made).document);
      final head = before.content.substring(0, before.offsets[index] + 1);
      expect(
        after.content,
        head + typed + before.content.substring(head.length),
      );
    });

    test('$name writes raw text as it stands', () {
      final written = document.grammar.escaped(typed.runes.toList(), raw: true);
      expect(String.fromCharCodes(written), typed);
    });

    test('$name refuses markup typed raw, and an edit inside a tag', () {
      final at = tokens[place()!.$1].start + 1;
      final markup = raw[extension] ?? raw['1']!;
      expect(
        valid(document, Insert(at, Text.of(markup))),
        isA<Failure<Change<int>>>(),
      );
      final tag = tokens.firstWhere(
        (token) =>
            token.get('') != Str(Text.of('#text')) &&
            token.get('shows') == null &&
            token.length > 1,
      );
      expect(
        valid(document, Insert(tag.start + 1, Text.of('x'))),
        isA<Failure<Change<int>>>(),
      );
    });
  }

  group('Taking markup away', () {
    /// Whether deleting from [start] to [end] of [source], read as
    /// [syntax], is valid.
    bool taken(String syntax, String source, int start, int end) {
      final document = decoded(formats[syntax]!, source);
      return valid(document, Delete(span(start, end - start))) is Success;
    }

    test('in a tag syntax, goes where what is left still pairs', () {
      expect(taken('xml', '<a><b>x</b></a>', 3, 6), isFalse);
      expect(taken('xml', '<a><b>x</b></a>', 3, 11), isTrue);
      expect(taken('xml', '<a><p>a</p><p>b</p></a>', 7, 14), isTrue);
      expect(taken('lmnl', '[a}[b}x{b]{a]', 3, 6), isFalse);
    });

    test('where markup is written in the words, goes', () {
      expect(taken('md', '*a* b', 0, 1), isTrue);
      expect(taken('tex', r'\emph{a} b', 0, 6), isTrue);
    });

    test('and is refused where it reaches into a tag', () {
      expect(taken('xml', '<a><b>x</b></a>', 4, 7), isFalse);
      expect(taken('md', '**a** b', 0, 1), isFalse);
    });
  });

  test('Words that change the markup beyond them are refused', () {
    // A space before the closing star leaves it closing nothing, and the
    // opening star, outside the edit, is words again.
    final document = decoded(formats['md']!, '*a* b');
    expect(valid(document, Insert(2, Text.of(' '))), isA<Failure>());
    expect(valid(document, Insert(4, Text.of(' '))), isA<Success>());
  });

  test('A tag typed into code is refused', () {
    // A backtick in a code span closes it early, leaving the one that
    // closed it as words.
    final document = decoded(formats['md']!, '`ab` c');
    expect(valid(document, Insert(2, Text.of('`'))), isA<Failure>());
    expect(valid(document, Insert(2, Text.of('*'))), isA<Success>());
  });
}

/// Whether [point] is a letter of the Latin alphabet.
bool _letter(int point) =>
    (point >= 0x41 && point <= 0x5A) || (point >= 0x61 && point <= 0x7A);
