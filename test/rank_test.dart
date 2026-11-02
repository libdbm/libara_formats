import 'dart:io';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:libara_formats/src/rank.dart';
import 'package:test/test.dart';

/// Which names are blocks, which a tree writer keeps whole where an inline
/// crosses them.
void main() {
  test('every name in the table of blocks is a block', () {
    for (final name in blocks) {
      expect(block(name), isTrue, reason: name);
    }
  });

  test('inlines, and a name in neither table, are not blocks', () {
    for (final name in ['em', 'strong', 'a', 'code', 'footnote', 'chapter']) {
      expect(block(name), isFalse, reason: name);
    }
    expect(blocks.intersection(inlines), isEmpty);
  });

  test('every name Markdown, roff and HTML make has a rank', () {
    // XML, LMNL and LaTeX keep the names they read, and Dart's and JSON's
    // elements are code, which never overlaps, so only these are closed.
    final syntaxes = <String, Syntax>{
      'md': const Markdown(),
      '1': const Man(),
      'ms': const Ms(),
      'html': const HTML(),
    };
    final unknown = <String>{};
    for (final file in Directory('test/samples').listSync().whereType<File>()) {
      final syntax = syntaxes[file.path.split('.').last];
      if (syntax == null) {
        continue;
      }
      final read = syntax.decode(Text.of(file.readAsStringSync()));
      if (read case Success(value: final document)) {
        for (final range in document.layer(3).items) {
          final name = '${(range as ARange).get('')}';
          if (!blocks.contains(name) && !inlines.contains(name)) {
            unknown.add('$name in ${file.path}');
          }
        }
      }
    }
    expect(unknown, isEmpty);
  });
}
