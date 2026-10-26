import 'dart:io';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// What a move owes in every tag syntax: an element moved past its next
/// sibling keeps its marker, and leaves what a fresh read of the text would
/// find; one cut in two is refused.
void main() {
  for (final file in Directory('test/samples').listSync().whereType<File>()) {
    final extension = file.path.split('.').last;
    if (!const {'xml', 'html', 'lmnl'}.contains(extension)) {
      continue;
    }
    final syntax = formats[extension]!;
    final name = file.path.split('/').last;
    final document = decoded(syntax, file.readAsStringSync());

    final tokens = document.layer(2).items.cast<ARange>().toList();

    /// Whether [element] has a start tag and an end tag of its own.
    bool tagged(Nested element) {
      final first = tokens.where(
        (token) => token.start == element.extent.start,
      );
      final last = tokens.where((token) => token.end == element.extent.end);
      return first.isNotEmpty &&
          last.isNotEmpty &&
          first.first != last.last &&
          first.first.get('') == element.element.get('') &&
          last.last.get('') == element.element.get('');
    }

    /// An element with tags of its own, and the sibling after it, standing
    /// against it.
    (Nested, Nested)? pair() {
      final elements = structure(document);
      for (final (index, one) in elements.indexed) {
        if (!tagged(one)) {
          continue;
        }
        for (final other in elements.skip(index + 1)) {
          if (other.depth < one.depth) {
            break;
          }
          if (other.depth == one.depth &&
              other.extent.start == one.extent.end &&
              other.extent.length > 0) {
            return (one, other);
          }
        }
      }
      return null;
    }

    test('$name moves an element past its sibling, marker and all', () {
      final found = pair();
      if (found == null) {
        markTestSkipped('no element stands against a sibling');
        return;
      }
      final (one, other) = found;
      final moved = value(
        document.apply(Edit(1, Move(one.extent, other.extent.end))),
      ).document;

      expect(
        moved.markers(3).map((pair) => pair.$1),
        contains(one.marker),
        reason: 'the element moved lost its marker',
      );
      final again = decoded(syntax, string(moved.items));
      expect(moved.layer(2).items, again.layer(2).items);
      expect(moved.layer(3).items, again.layer(3).items);
      expect(string(moved.previous!.items), string(document.items));
    });

    test('$name refuses a move cutting an element in two', () {
      final found = pair();
      if (found == null) {
        markTestSkipped('no element stands against a sibling');
        return;
      }
      final (one, other) = found;
      // Its start tag alone.
      final tag = tokens.firstWhere((token) => token.start == one.extent.start);
      expect(
        document.apply(Edit(1, Move(tag, other.extent.end))),
        isA<Failure<Change<int>>>(),
      );
    });
  }
}
