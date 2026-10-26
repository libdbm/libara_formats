part of 'inlines.dart';

/// A link written by name rather than by destination: `[words][name]`,
/// `[name][]`, or `[name]` on its own, as where it ends, where it goes and
/// what it is called.
///
/// The three forms the standard has, and all three come to the same
/// thing: a name looked up among what the document said its links are.
(int, String, String?)? _referred(
  String text,
  int opens,
  int closes,
  Links links,
  _Spent spent,
) {
  final inside = text.substring(opens + 1, closes - 1);
  // A name of its own, standing after the words.
  if (closes < text.length && text[closes] == '[') {
    final second = _bracketed(text, closes, spent);
    if (second != null) {
      final name = text.substring(closes + 1, second - 1);
      final wanted = name.isEmpty ? inside : name;
      if (!_nameable(wanted)) {
        return null;
      }
      final held = links(labelled(wanted));
      return held == null ? null : (second, held.$1, held.$2);
    }
  }
  // The words themselves are the name.
  if (!_nameable(inside)) {
    return null;
  }
  final held = links(labelled(inside));
  return held == null ? null : (closes, held.$1, held.$2);
}

/// Where the name opened at [at] closes, just past its bracket, counting the
/// brackets inside it.
///
/// A bracket standing in something already read is not a bracket: a code
/// span holding one says it, and does not close a name with it.
int? _bracketed(String text, int at, _Spent spent) {
  var depth = 0;
  var index = at;
  // A name is at most 999 characters, the standard says, so the search for
  // its closing bracket stops there rather than at the end of the block.
  final until = at + 1001 < text.length ? at + 1001 : text.length;
  while (index < until) {
    final past = spent.past(index);
    if (past > index) {
      index = past;
      continue;
    }
    final character = text[index];
    if (character == r'\') {
      index += 2;
      continue;
    }
    if (character == '[') {
      depth += 1;
    } else if (character == ']') {
      depth -= 1;
      if (depth == 0) {
        return index + 1;
      }
    }
    index += 1;
  }
  return null;
}

/// The destination standing after a closed bracket at [at]: where it ends,
/// where it goes, and what it was called.
(int, String, String?)? _target(String text, int at) {
  if (at >= text.length || text[at] != '(') {
    return null;
  }
  var index = at + 1;
  while (index < text.length && _space(text[index])) {
    index += 1;
  }
  final String destination;
  if (index < text.length && text[index] == '<') {
    final close = _angled(text, index);
    if (close < 0) {
      return null;
    }
    destination = text.substring(index + 1, close);
    index = close + 1;
  } else {
    final from = index;
    var depth = 0;
    while (index < text.length) {
      final character = text[index];
      if (character == r'\') {
        index += 2;
        continue;
      }
      if (_space(character)) {
        break;
      }
      if (character == '(') {
        depth += 1;
      } else if (character == ')') {
        if (depth == 0) {
          break;
        }
        depth -= 1;
      }
      index += 1;
    }
    destination = text.substring(
      from,
      index < text.length ? index : text.length,
    );
  }
  while (index < text.length && _space(text[index])) {
    index += 1;
  }
  String? title;
  if (index < text.length &&
      (text[index] == '"' || text[index] == "'" || text[index] == '(')) {
    final closer = text[index] == '(' ? ')' : text[index];
    final close = _closes(text, index + 1, closer);
    if (close < 0) {
      return null;
    }
    title = says(text.substring(index + 1, close));
    index = close + 1;
    while (index < text.length && _space(text[index])) {
      index += 1;
    }
  }
  if (index >= text.length || text[index] != ')') {
    return null;
  }
  return (index + 1, _unescaped(destination), title);
}

/// Where the destination opened at [at] with an angle closes, or less than
/// nothing where it does not.
///
/// An escaped angle does not close it, and a line ending ends the try, since
/// a destination stands on one line.
int _angled(String text, int at) {
  var index = at + 1;
  while (index < text.length) {
    final character = text[index];
    if (character == r'\') {
      index += 2;
      continue;
    }
    if (character == '\n' || character == '\r' || character == '<') {
      return -1;
    }
    if (character == '>') {
      return index;
    }
    index += 1;
  }
  return -1;
}

/// Where a title opened before [at] and closed by [closer] ends, or less
/// than nothing where it does not close.
///
/// An escaped closer is one of the title's own characters, which is the only
/// way a title says the mark it is held in.
int _closes(String text, int at, String closer) {
  var index = at;
  while (index < text.length) {
    if (text[index] == r'\') {
      index += 2;
      continue;
    }
    if (text[index] == closer) {
      return index;
    }
    index += 1;
  }
  return -1;
}
