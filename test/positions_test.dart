import 'package:libara_formats/src/positions.dart';
import 'package:test/test.dart';

/// The code-point position of every UTF-16 offset of [text], counted the
/// slow way, to hold [Positions] to.
List<int> counted(String text) => [
  for (var unit = 0; unit <= text.length; unit++)
    text.substring(0, unit).runes.length -
        (unit > 0 &&
                unit < text.length &&
                _high(text.codeUnitAt(unit - 1)) &&
                _low(text.codeUnitAt(unit))
            ? 1
            : 0),
];

bool _high(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
bool _low(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

void main() {
  void check(String text) {
    final positions = Positions(text);
    final expected = counted(text);
    for (var unit = 0; unit <= text.length; unit++) {
      expect(positions[unit], expected[unit], reason: 'offset $unit');
    }
  }

  test('text in the Basic Multilingual Plane counts the same either way', () {
    check('<p>café</p>');
    check('');
  });

  test('a surrogate pair is one position', () {
    final positions = Positions('a\u{1D11E}b');
    expect(positions[0], 0);
    expect(positions[1], 1);
    expect(positions[3], 2);
    expect(positions[4], 3);
  });

  test('an offset inside a pair belongs to the character it splits', () {
    expect(Positions('a\u{1D11E}b')[2], 1);
  });

  test('an emoji sequence joined with ZWJ counts each code point', () {
    const family = '\u{1F468}‍\u{1F469}‍\u{1F467}';
    check('<b>$family</b>');
    expect(Positions(family)[family.length], 5);
  });

  test('combining marks are code points of their own', () {
    check('é̂ <i>ñ</i>');
  });

  test('a lone surrogate is one position', () {
    check('a\uD834b\uDD1Ec');
  });
}
