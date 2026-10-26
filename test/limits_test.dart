import 'dart:io';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// Ported from markwrite's `resource_limits_test`: a hostile file is refused
/// once a cap is reached, before the work it would cost is done.
void main() {
  Matcher refused(String why) => isA<Failure<Layered<int>>>()
      .having((failure) => failure.kind, 'kind', Kind.invalid)
      .having((failure) => failure.message, 'message', contains(why));

  Result<Layered<int>> read(Limits limits, String text) =>
      XML(limits: limits).decode(Text.of(text));

  test('a text longer than the limit is refused before it is read', () {
    expect(read(const Limits(items: 8), 'x' * 9), refused('9 characters'));
    expect(read(const Limits(items: 8), 'x' * 8), isA<Success<Layered<int>>>());
  });

  test('so are more tokens than the limit', () {
    expect(read(const Limits(markers: 2), '<a></a><b></b>'), refused('tokens'));
  });

  test('and more elements', () {
    expect(read(const Limits(markers: 4), '<a/><b/><c/>'), refused('elements'));
  });

  test('and elements nested deeper than the limit', () {
    expect(
      read(const Limits(depth: 2), '<a><b><c></c></b></a>'),
      refused('deeper than 2'),
    );
    expect(
      read(const Limits(depth: 3), '<a><b><c></c></b></a>'),
      isA<Success<Layered<int>>>(),
    );
  });

  test('and HTML elements nested deeper than the limit', () {
    Result<Layered<int>> html(String text) =>
        const HTML(limits: Limits(depth: 4)).decode(Text.of(text));
    // The html and body the standard implies count as two.
    expect(html('<div><div><div>x'), refused('deeper than 4'));
    expect(html('<div><div>x'), isA<Success<Layered<int>>>());
  });

  test('and a tag saying more attributes than the limit', () {
    expect(
      read(const Limits(attributes: 1), '<a x="1" y="2"/>'),
      refused('attributes'),
    );
  });

  test('a book is well within what is read by default', () {
    decoded(const XML(), File('test/samples/huck.xml').readAsStringSync());
  });

  test('an edit past a cap is a diagnostic, not a failure', () {
    final document = value(read(const Limits(depth: 2), '<a></a>'));
    final next = value(
      document.apply(Edit(1, Insert(7, Text.of('<x><y><z></z></y></x>')))),
    ).document;
    expect(problems(next, 3), contains('elements nested deeper than 2'));
  });
}
