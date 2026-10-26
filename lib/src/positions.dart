import 'dart:typed_data';

/// The code-point positions of the UTF-16 offsets of one string.
///
/// A scanner works over a Dart `String`, so the offsets it finds count
/// UTF-16 units, while libara counts code points. Every offset a scanner
/// hands back goes through here before it becomes a range, so the two
/// counts meet in one place.
///
/// Built in one pass over the string, after which each lookup is constant
/// time and in any order. A string with no surrogate pair, which is most
/// text, needs no table at all: there its offsets already are positions.
final class Positions {
  /// The positions of [text]'s offsets.
  Positions(String text) : _table = _build(text);

  /// Each offset's position, or null where they are the same.
  final Int32List? _table;

  /// The code-point position of UTF-16 [offset], from 0 to the string's
  /// length. An offset between the halves of a surrogate pair is the
  /// position of the character it splits.
  int operator [](int offset) => _table?[offset] ?? offset;

  static Int32List? _build(String text) {
    final length = text.length;
    var paired = false;
    for (var unit = 0; unit + 1 < length; unit++) {
      if (_high(text.codeUnitAt(unit)) && _low(text.codeUnitAt(unit + 1))) {
        paired = true;
        break;
      }
    }
    if (!paired) {
      return null;
    }
    final table = Int32List(length + 1);
    var point = 0;
    var unit = 0;
    while (unit < length) {
      table[unit] = point;
      if (unit + 1 < length &&
          _high(text.codeUnitAt(unit)) &&
          _low(text.codeUnitAt(unit + 1))) {
        table[unit + 1] = point;
        unit += 2;
      } else {
        unit += 1;
      }
      point += 1;
    }
    table[length] = point;
    return table;
  }

  static bool _high(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  static bool _low(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
}
