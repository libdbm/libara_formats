import 'dart:io';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

/// Every manual page the machine holds, read as man: none may throw, every
/// one read keeps its text, and the whole shelf reads within a budget.
/// Skipped where there is no shelf, as on a runner. Ported from markwrite's
/// `man_corpus_test`.
void main() {
  final shelf = Directory('/usr/share/man/man1');
  test(
    'the machine\'s manual pages all read, or are refused, and never throw',
    () {
      final pages = [
        for (final held in shelf.listSync())
          if (held is File && held.path.endsWith('.1')) held,
      ];
      if (pages.isEmpty) {
        return;
      }
      var read = 0;
      var refused = 0;
      var elements = 0;
      final watch = Stopwatch()..start();
      for (final page in pages) {
        final String text;
        try {
          text = page.readAsStringSync();
        } on FileSystemException {
          continue;
        } on FormatException {
          continue;
        }
        switch (const Man().decode(Text.of(text))) {
          case Failure(:final message):
            refused += 1;
            expect(message, isNotEmpty, reason: page.path);
          case Success(:final value):
            read += 1;
            expect(
              String.fromCharCodes(value.items.items),
              text,
              reason: page.path,
            );
            elements += value.layer(3).length;
        }
      }
      watch.stop();
      // ignore: avoid_print
      print(
        'man corpus: $read read, $refused refused, $elements elements, '
        '${watch.elapsedMilliseconds}ms',
      );
      expect(read, greaterThan(refused));
      expect(watch.elapsed, lessThan(const Duration(seconds: 30)));
    },
    skip: !shelf.existsSync(),
  );
}
