import 'named.dart';

/// The character `&name;` stands for, or null for a name this does not know.
///
/// The names are HTML5's, all two thousand one hundred and twenty five of
/// them, which is the list the standard names. A name outside it is left
/// alone rather than guessed at, so it shows as itself and can be noticed.
String? entity(String name) {
  if (name.startsWith('#')) {
    final hex = name.startsWith('#x') || name.startsWith('#X');
    final digits = name.substring(hex ? 2 : 1);
    // Digits alone: the parse would also read a sign.
    final point = (hex ? _hex : _decimal).hasMatch(digits)
        ? int.tryParse(digits, radix: hex ? 16 : 10)
        : null;
    if (point == null || point > 0x10FFFF) {
      return null;
    }
    // Nought is not a character. The standard says to show the one a reader
    // is shown for anything that is not, rather than to drop it.
    if (point == 0) {
      return '�';
    }
    // Surrogates are not characters on their own.
    if (point >= 0xD800 && point <= 0xDFFF) {
      return null;
    }
    return String.fromCharCode(point);
  }
  return named[name];
}

final _hex = RegExp(r'^[0-9A-Fa-f]+$');
final _decimal = RegExp(r'^[0-9]+$');

/// The longest a reference runs between its `&` and its `;`: the longest of
/// the standard's names, which is thirty-one characters, and room for a
/// number past it.
const longest = 32;

/// The first [character] in [text] at or after [from] and before [to], or
/// -1.
///
/// By hand, because `String.indexOf` takes where to begin and not where to
/// stop, so it reads to the end of the text whatever stretch was asked
/// about, which makes reading a book quadratic.
int found(String text, int character, int from, int to) {
  for (var at = from; at < to; at += 1) {
    if (text.codeUnitAt(at) == character) {
      return at;
    }
  }
  return -1;
}

/// The entity references in [text] between [from] and [to], one at a time,
/// each as where it starts, where it ends, and what it stands for.
///
/// Only ones that are understood are returned. `&` followed by something
/// that is not a reference is ordinary text, which is what a document full
/// of URLs is mostly made of. Read out rather than gathered up, so a caller
/// counting against a limit stops when it is reached.
Iterable<(int, int, String)> references(String text, int from, int to) sync* {
  var at = from;
  while (at < to) {
    final mark = found(text, 0x26, at, to);
    if (mark < 0) {
      break;
    }
    // A name is short; anything longer than this is an ampersand in prose,
    // and the search is bounded to say so rather than finding a semicolon a
    // paragraph away.
    final end = mark + longest + 2;
    final close = found(text, 0x3B, mark + 1, to < end ? to : end);
    if (close < 0) {
      at = mark + 1;
      continue;
    }
    final shows = entity(text.substring(mark + 1, close));
    if (shows == null) {
      at = mark + 1;
      continue;
    }
    yield (mark, close + 1, shows);
    at = close + 1;
  }
}

/// [text] with every reference in it read as the character it stands for.
///
/// For an attribute value, which is held as what it says rather than as it
/// was written.
String resolved(String text) {
  if (!text.contains('&')) {
    return text;
  }
  final out = StringBuffer();
  var at = 0;
  for (final (start, end, shows) in references(text, 0, text.length)) {
    out
      ..write(text.substring(at, start))
      ..write(shows);
    at = end;
  }
  out.write(text.substring(at));
  return out.toString();
}
