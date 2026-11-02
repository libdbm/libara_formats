@Tags(['perf'])
library;

import 'dart:io';
import 'dart:math';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// Ported from markwrite's `codec_scale_test`, with its budgets: what reading
/// a book costs, how that grows, and what a keystroke into one costs.

/// What an operation is allowed, in microseconds.
const budget = 10000;

/// What reading a whole book is allowed, which is one act at the start of a
/// session, so it is held to its order of magnitude rather than to the bar.
const opening = 250000;

/// About a book.
const paragraphs = 8000;

/// One paragraph, written in each syntax, so what differs between them is
/// the syntax and not the document.
const syntaxes = {
  'xml': '<p>one two <em>three</em> four five six</p>\n',
  'lmnl': '[p}one two [em}three{em] four five six{p]\n',
  'html': '<p>one two <em>three</em> four five six</p>\n',
  'markdown': 'one two *three* four five six\n\n',
  'man': '.PP\none two \\fIthree\\fP four five six\n',
  'latex': 'one two \\emph{three} four five six\n\n',
};

/// The middle and the ninety-ninth percentile of [rounds] timings of
/// [doing], in microseconds.
(int, int) cost(int rounds, void Function(int round) doing) {
  final samples = <int>[];
  for (var round = 0; round < rounds; round += 1) {
    final watch = Stopwatch()..start();
    doing(round);
    watch.stop();
    samples.add(watch.elapsedMicroseconds);
  }
  samples.sort();
  return (
    samples[samples.length ~/ 2],
    samples[min(samples.length - 1, (samples.length * 99) ~/ 100)],
  );
}

void main() {
  for (final MapEntry(key: name, value: paragraph) in syntaxes.entries) {
    final syntax = formats[name]!;

    test('$name reading a book', () {
      final text = paragraph * paragraphs;
      final (middle, tail) = cost(5, (_) => decoded(syntax, text));
      print('$name reading a book: middle ${middle}us, tail ${tail}us');
      expect(middle, lessThan(opening));
    });

    test('$name reading four times the book in about four times as long', () {
      final (near, _) = cost(3, (_) => decoded(syntax, paragraph * 2000));
      final (far, _) = cost(3, (_) => decoded(syntax, paragraph * 8000));
      print('$name reading 2,000 paragraphs ${near}us, 8,000 ${far}us');
      expect(far, lessThan(near * 8));
    });

    test('$name a keystroke into a book', () {
      var document = decoded(syntax, paragraph * paragraphs);
      final at = string(document.items).indexOf('four');
      final (middle, tail) = cost(200, (_) {
        document = value(document.apply(Edit(1, Insert(at, Text.of('x')))))
            .document;
      });
      print('$name a keystroke: middle ${middle}us, tail ${tail}us');
      expect(tail, lessThan(budget));
    });
  }

  test('markdown a keystroke beside a name nothing defines', () {
    // A name in brackets is looked up among the definitions of the whole
    // text, outside the stretch a keystroke reads again.
    const paragraph = 'one two [three] four five six\n\n';
    var document = decoded(const Markdown(), paragraph * paragraphs);
    final at = string(document.items).indexOf('four', paragraph.length * 4000);
    final (middle, tail) = cost(200, (_) {
      document = value(document.apply(Edit(1, Insert(at, Text.of('x')))))
          .document;
    });
    print(
      'markdown a keystroke beside a name: middle ${middle}us, '
      'tail ${tail}us',
    );
    expect(tail, lessThan(budget));
  });

  group('dart', () {
    // The largest source file here, which is code rather than a book.
    final source = File('lib/src/html/tree.dart').readAsStringSync();

    test('dart reading a large source file', () {
      final (middle, tail) = cost(5, (_) => decoded(const Dart(), source));
      print('dart reading a source file: middle ${middle}us, tail ${tail}us');
      expect(middle, lessThan(opening));
    });

    test('dart a keystroke into a large source file', () {
      var document = decoded(const Dart(), source);
      final at = source.length ~/ 2;
      final (middle, tail) = cost(200, (round) {
        document = value(
          document.apply(Edit(1, Insert(at + round, Text.of('x')))),
        ).document;
      });
      print('dart a keystroke: middle ${middle}us, tail ${tail}us');
      expect(tail, lessThan(budget));
    });

    /// What typing [rounds] letters into a name costs, the first after
    /// [after]'s first [into] characters: a keystroke within a name, which
    /// reads again only the name and what starts or ends at it.
    (int, int) typing(String after, int into) {
      var document = decoded(const Dart(), source);
      final at = source.indexOf(after) + into;
      return cost(200, (round) {
        document = value(
          document.apply(Edit(1, Insert(at + round, Text.of('x')))),
        ).document;
      });
    }

    test('dart typing in the name of a class 1,700 lines long', () {
      final (middle, tail) = typing('class _Builder', 8);
      print('dart typing in a class name: middle ${middle}us, tail ${tail}us');
      expect(middle, lessThan(1000));
      expect(tail, lessThan(budget));
    });

    test('dart typing in a name within a body', () {
      final (middle, tail) = typing('_adopt(name);', 2);
      print('dart typing in a name: middle ${middle}us, tail ${tail}us');
      expect(middle, lessThan(1000));
      expect(tail, lessThan(budget));
    });
  });

  group('json', () {
    // A paragraph as a row of an array that holds the book, since a JSON
    // text is one value.
    const row = '  ["one two", {"em": "three"}, "four five six"]';
    final book = '[\n${List.filled(paragraphs, row).join(',\n')}\n]\n';

    test('json reading a book', () {
      final (middle, tail) = cost(5, (_) => decoded(const JSON(), book));
      print('json reading a book: middle ${middle}us, tail ${tail}us');
      expect(middle, lessThan(opening));
    });

    test('json a keystroke into a book', () {
      var document = decoded(const JSON(), book);
      final at = string(document.items).indexOf('four', book.length ~/ 2);
      final (middle, tail) = cost(200, (_) {
        document = value(document.apply(Edit(1, Insert(at, Text.of('x')))))
            .document;
      });
      print('json a keystroke: middle ${middle}us, tail ${tail}us');
      expect(tail, lessThan(budget));
    });
  });

  group('writing a tree', () {
    // Splitting elements that cross was measured against the code before
    // it, alternately on one machine: the two were within 1% of each other
    // writing huck.lmnl, where nothing crosses. What is held here is the
    // budget for reading a book, which load on the machine does not upset.
    test('huck.lmnl written as XML', () {
      final document = decoded(
        formats['lmnl']!,
        File('test/samples/huck.lmnl').readAsStringSync(),
      );
      final (middle, _) = cost(5, (_) => formats['xml']!.encode(document));
      print('huck.lmnl as XML: middle $middle us');
      expect(middle, lessThan(opening));
    });

    test('a book whose every paragraph an em crosses into the next', () {
      // 8,000 paragraphs, each with an em from its middle to the middle of
      // the next: every em is cut in two.
      final text = StringBuffer('[p}one ');
      for (var index = 0; index < paragraphs; index++) {
        text.write('[em=$index}two{p][p}three{em=$index] four ');
      }
      text.write('{p]');
      final document = decoded(formats['lmnl']!, text.toString());
      final (middle, _) = cost(5, (_) => formats['xml']!.encode(document));
      print('crossing book as XML: middle $middle us');
      expect(middle, lessThan(opening));
    });
  });

  group('rtf', () {
    test('rtf reading a 1MB file', () {
      final sample = String.fromCharCodes(
        File('test/samples/rtf/features-word.rtf').readAsBytesSync(),
      );
      final body = sample.substring(0, sample.lastIndexOf('}'));
      final paragraph =
          r'\pard Lorem ipsum dolor {\b sit} amet, consectetur elit.\par'
          '\n';
      final text =
          '$body${paragraph * ((1000000 - body.length) ~/ paragraph.length)}}';
      final (middle, _) = cost(5, (_) => decoded(formats['rtf']!, text));
      print('rtf reading ${text.length} bytes: middle $middle us');
      expect(middle, lessThan(500000));
    });
  });
}
