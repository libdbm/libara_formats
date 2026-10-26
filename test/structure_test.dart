import 'dart:io';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:libara_formats/src/html/html.dart' show nested;
import 'package:test/test.dart';

import 'harness.dart';

/// The structure of a version: its elements in pre-order, each with its
/// marker, its depth, and its stretch of the text.
void main() {
  final samples = [
    for (final file in Directory('test/samples').listSync().whereType<File>())
      if (formats[file.path.split('.').last] case final Syntax syntax)
        (file.path.split('/').last, syntax, file.readAsStringSync()),
  ];

  for (final (name, syntax, text) in samples) {
    test('$name: every element once, under its own marker', () {
      final document = decoded(syntax, text);
      final held = structure(document);
      expect(
        {for (final one in held) one.marker},
        {for (final (marker, _) in document.markers(3)) marker},
      );
      expect(held.length, document.markers(3).length);
      for (final one in held) {
        expect(
          document
              .markers(3)
              .any((pair) => pair.$1 == one.marker && pair.$2 == one.element),
          isTrue,
        );
      }
    });

    test('$name: each over the text its tokens cover, held by its parent', () {
      final document = decoded(syntax, text);
      final tokens = document.layer(2).items.cast<ARange>().toList();
      final held = structure(document);
      final open = <Nested>[];
      for (final one in held) {
        if (one.element.length > 0) {
          expect(one.extent.start, tokens[one.element.start].start);
          expect(one.extent.end, tokens[one.element.end - 1].end);
        } else {
          expect(one.extent.length, 0);
        }
        expect(one.depth, lessThanOrEqualTo(open.length));
        open.length = one.depth;
        if (open.isNotEmpty) {
          final parent = open.last;
          expect(parent.element.start, lessThanOrEqualTo(one.element.start));
          expect(parent.element.end, greaterThanOrEqualTo(one.element.end));
        }
        open.add(one);
      }
    });
  }

  test(
    'HTML nests as its tree construction says, implied elements and all',
    () {
      for (final (name, syntax, text) in samples) {
        if (syntax is! HTML) {
          continue;
        }
        final document = decoded(syntax, text);
        expect(
          [for (final one in structure(document)) (one.element, one.depth)],
          [
            for (final (element, depth, _) in nested(document))
              (element, depth),
          ],
          reason: name,
        );
      }
    },
  );

  test('in LaTeX, a cell holds a command that fills it', () {
    // The cell and the command cover the same tokens; the command was
    // written inside the cell.
    final document = decoded(
      const LaTeX(),
      '\\begin{tabular}{ll}\n\\midrule\n'
      '\\multirow{4}{*}{\\minitab[l]{100\\% RCV1-v2\\\\(\$N=804,414\$)}}\n'
      '    & \\texttt{2P} \\\\\n\\end{tabular}\n',
    );
    final held = structure(document);
    final cell = held.firstWhere(
      (one) => one.element.get('') == Str(Text.of('td')),
    );
    final command = held.firstWhere(
      (one) => one.element.get('') == Str(Text.of('multirow')),
    );
    expect(cell.extent, command.extent);
    expect(cell.depth, lessThan(command.depth));
  });

  test('an empty element stands where its place among the tokens is', () {
    final document = decoded(const HTML(), '<p>a</p>');
    final head = structure(document)
        .firstWhere((one) => one.element.get('') == Str(Text.of('head')));
    expect(head.extent.length, 0);
  });
}
