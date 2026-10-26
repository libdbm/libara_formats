import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// Positions count code points, so a character outside the Basic
/// Multilingual Plane, which a Dart string holds as two units, is one.
void main() {
  const xml = XML();

  test('a character outside the BMP in text is one position', () {
    final document = decoded(xml, '<p>a\u{1D11E}b</p>');
    expect(
      [for (final range in document.layer(2).items) range.start],
      [0, 3, 6],
    );
    expect(tokens(document)[1], ('#text', 'a\u{1D11E}b'));
  });

  test('and in a tag name and an attribute value', () {
    final document = decoded(
      xml,
      '<\u{1D11E} t="\u{1F600}">x</\u{1D11E}>&amp;',
    );
    expect(said(token(document, 0), ''), '\u{1D11E}');
    expect(said(token(document, 0), 't'), '\u{1F600}');
    expect(
      [for (final range in document.layer(2).items) range.start],
      [0, 9, 10, 14],
    );
  });

  test('an emoji joined with ZWJ and combining marks count every point', () {
    const family = '\u{1F468}‍\u{1F469}‍\u{1F467}';
    final document = decoded(xml, '<b>$family é</b>');
    expect(token(document, 3).length, 8);
    expect(token(document, 11).start, 11);
  });
}
