import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

void main() {
  test('every key of formats is lower case', () {
    for (final key in formats.keys) {
      expect(key, key.toLowerCase());
    }
  });

  test('every syntax is found by its name and by each extension', () {
    const found = {
      'xml': [XML, 'xml'],
      'html': [HTML, 'html', 'htm'],
      'json': [JSON, 'json'],
      'dart': [Dart, 'dart'],
      'lmnl': [LMNL, 'lmnl'],
      'markdown': [Markdown, 'markdown', 'md'],
      'man': [Man, 'man', '1', '2', '3', '4', '5', '6', '7', '8', '9'],
      'ms': [Ms, 'ms'],
      'me': [Me, 'me'],
      'latex': [LaTeX, 'latex', 'tex'],
      'rtf': [RTF, 'rtf'],
    };
    for (final [type, ...keys] in found.values) {
      for (final key in keys) {
        expect(formats[key].runtimeType, type, reason: '$key');
      }
    }
    expect(formats.keys.toSet(), {
      for (final [_, ...keys] in found.values) ...keys.cast<String>(),
    });
  });

  test('every syntax is a Readable and a Writable', () {
    for (final MapEntry(:key, :value) in formats.entries) {
      expect(value, isA<Readable>(), reason: key);
      expect(value, isA<Writable>(), reason: key);
    }
  });

  test('every importer is found by its name and each extension', () {
    expect(importers, isA<Map<String, Readable>>());
    expect(importers.keys.toSet(), {'rtf'});
  });
}
