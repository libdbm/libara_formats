import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// What a structural edit owes a mark over the text it does not change: an
/// annotation over words inside an element keeps them when the element is
/// taken off, however much of the markup around them is written again.
void main() {
  for (final (syntax, source, name) in [
    ('md', 'a *b quick c* d\n', 'em'),
    ('xml', '<p>a <em>b quick c</em> d</p>', 'em'),
    ('html', '<p>a <em>b quick c</em> d</p>', 'em'),
    ('lmnl', '[p}a [em}b quick c{em] d{p]', 'em'),
    ('tex', r'a \emph{b quick c} d', 'em'),
  ]) {
    test('$syntax: an annotation keeps its words when $name is taken off', () {
      final document = decoded(formats[syntax]!, source);
      final at = source.indexOf('quick');
      final marked = document.apply(
        Edit.annotation(
          1,
          Mark<Object?>(ARange.from(extent(at, 5), {'': Str(Text.of('x'))})),
        ),
      );
      final annotated = (marked as Success<Change<int>>).value.document;
      final element = annotated
          .markers(3)
          .firstWhere((pair) => '${pair.$2.get('')}' == name)
          .$1;
      final applied = annotated.apply(Edit(3, Unmark(element)));
      expect(applied, isA<Success<Change<int>>>(), reason: '$applied');
      final after = (applied as Success<Change<int>>).value.document;
      final text = after.items.items.toList();
      expect(String.fromCharCodes(text), isNot(contains('<em>')));
      expect(
        [
          for (final (_, one) in after.annotations(1))
            String.fromCharCodes(text.sublist(one.start, one.end)),
        ],
        ['quick'],
      );
    });
  }
}

/// [length] items from [start].
Range extent(int start, int length) => switch (Range.create(start, length)) {
  Success(:final value) => value,
  Failure(:final message) => throw StateError(message),
};
