import 'dart:io';
import 'dart:isolate';

import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'dart_syntax.dart';
import 'harness.dart';

/// The analyzer's own source, a corpus of real Dart larger and more varied
/// than this package's, read as the analyzer reads it. It is found through
/// this package's resolved dependencies, where the analyzer is a dev
/// dependency.
Future<void> main() async {
  final root = await Isolate.resolvePackageUri(Uri.parse('package:analyzer/'));
  final files = [
    for (final file in Directory.fromUri(root!).listSync(recursive: true))
      if (file is File && file.path.endsWith('.dart')) file,
  ]..sort((one, other) => one.path.compareTo(other.path));
  for (final file in files) {
    final name = file.path.substring(root.toFilePath().length);
    test('analyzer $name reads as the analyzer parses it', () {
      final text = file.readAsStringSync();
      expect(ourSyntax(decoded(const Dart(), text)), theirSyntax(text));
    });
  }
}
