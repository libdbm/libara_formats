/// Scanning helpers shared by the angle-bracket syntaxes, XML and HTML. Each
/// works on a tag's text or on the text around it, and none alters it.
library;

/// The index of the `>` that closes the tag opening at [from], skipping any
/// `>` inside a quoted attribute value; or -1 if none.
int closing(String text, int from) {
  var quote = 0;
  for (var index = from + 1; index < text.length; index += 1) {
    final unit = text.codeUnitAt(index);
    if (quote != 0) {
      if (unit == quote) {
        quote = 0;
      }
    } else if (unit == 0x22 || unit == 0x27) {
      quote = unit;
    } else if (unit == 0x3E) {
      return index;
    }
  }
  return -1;
}

/// The element name of a tag: the run after `<` or `</`, up to the first
/// whitespace, `/`, or `>`.
String called(String tag) {
  final from = tag.startsWith('</') ? 2 : 1;
  var to = from;
  while (to < tag.length && !_breaks(tag.codeUnitAt(to))) {
    to += 1;
  }
  return from > tag.length ? '' : tag.substring(from, to);
}

/// What the construct from [mark] to [end] is called as a token, by the
/// DOM's names, and what it shows in a reader's place of it.
///
/// A comment, a processing instruction and a declaration say something
/// about the document rather than in it, so they show nothing. A CDATA
/// section's brackets are markup and what stands between them is content,
/// so it shows exactly that.
(String, String) saying(String text, int mark, int end) {
  if (text.startsWith('<!--', mark)) {
    return ('#comment', '');
  }
  if (text.startsWith('<![CDATA[', mark)) {
    return ('#cdata', text.substring(mark + 9, end - 3));
  }
  if (text.startsWith('<?', mark)) {
    return ('#pi', '');
  }
  final doctype =
      end - mark >= 9 &&
      text.substring(mark, mark + 9).toUpperCase() == '<!DOCTYPE';
  return (doctype ? '#doctype' : '#declaration', '');
}

/// The index just past the comment, CDATA section, processing instruction
/// or declaration standing at [mark], or -1 where it is unterminated.
///
/// A CDATA section ends at `]]>` and not at the first `>`, so
/// `<![CDATA[a > b]]>` holds one a scanner must read past.
int skipped(String text, int mark) {
  if (text.startsWith('<!--', mark)) {
    final close = text.indexOf('-->', mark + 4);
    return close < 0 ? -1 : close + 3;
  }
  if (text.startsWith('<![CDATA[', mark)) {
    final close = text.indexOf(']]>', mark + 9);
    return close < 0 ? -1 : close + 3;
  }
  if (text.startsWith('<!DOCTYPE', mark)) {
    return _doctype(text, mark);
  }
  final close = text.indexOf('>', mark + 2);
  return close < 0 ? -1 : close + 1;
}

/// The index just past the doctype standing at [mark], or -1: its `>` is
/// the first outside its internal subset's brackets and outside a quoted
/// value, and the subset's comments and instructions are read whole.
int _doctype(String text, int mark) {
  var depth = 0;
  var index = mark + 9;
  while (index < text.length) {
    final unit = text.codeUnitAt(index);
    if (unit == 0x22 || unit == 0x27) {
      final close = text.indexOf(String.fromCharCode(unit), index + 1);
      if (close < 0) {
        return -1;
      }
      index = close + 1;
    } else if (depth > 0 && text.startsWith('<!--', index)) {
      final close = text.indexOf('-->', index + 4);
      if (close < 0) {
        return -1;
      }
      index = close + 3;
    } else if (depth > 0 && text.startsWith('<?', index)) {
      final close = text.indexOf('?>', index + 2);
      if (close < 0) {
        return -1;
      }
      index = close + 2;
    } else {
      if (unit == 0x5B) {
        depth += 1;
      } else if (unit == 0x5D && depth > 0) {
        depth -= 1;
      } else if (unit == 0x3E && depth == 0) {
        return index + 1;
      }
      index += 1;
    }
  }
  return -1;
}

/// The name and value of every attribute of a start or empty tag, in the
/// order they are written, each value as it was written.
List<(String, String)> pairs(String tag) {
  final found = <(String, String)>[];
  var at = 1;
  while (at < tag.length && !_breaks(tag.codeUnitAt(at))) {
    at += 1;
  }
  while (at < tag.length) {
    while (at < tag.length && space(tag.codeUnitAt(at))) {
      at += 1;
    }
    if (at >= tag.length || tag[at] == '>' || tag[at] == '/') {
      break;
    }
    final from = at;
    while (at < tag.length &&
        tag[at] != '=' &&
        !space(tag.codeUnitAt(at)) &&
        tag[at] != '>' &&
        tag[at] != '/') {
      at += 1;
    }
    final name = tag.substring(from, at);
    while (at < tag.length && space(tag.codeUnitAt(at))) {
      at += 1;
    }
    if (at < tag.length && tag[at] == '=') {
      at += 1;
      while (at < tag.length && space(tag.codeUnitAt(at))) {
        at += 1;
      }
      if (at < tag.length && (tag[at] == '"' || tag[at] == "'")) {
        final quote = tag[at];
        final start = at + 1;
        at = tag.indexOf(quote, start);
        if (at < 0) {
          break;
        }
        found.add((name, tag.substring(start, at)));
        at += 1;
      } else {
        // Unquoted, so it ends at a space or at the tag's own close. A slash
        // ends it only where it is the one that closes the tag, because a
        // slash is the first character of nearly every link.
        final start = at;
        while (at < tag.length &&
            !space(tag.codeUnitAt(at)) &&
            tag[at] != '>' &&
            !_closes(tag, at)) {
          at += 1;
        }
        found.add((name, tag.substring(start, at)));
      }
    } else if (name.isNotEmpty) {
      found.add((name, ''));
    }
  }
  return found;
}

/// Whether the slash at [at] is the one closing an empty tag, rather than a
/// character standing in an unquoted value.
bool _closes(String tag, int at) =>
    tag[at] == '/' && at + 1 < tag.length && tag[at + 1] == '>';

bool _breaks(int unit) => space(unit) || unit == 0x2F || unit == 0x3E;

/// Whether [unit] is the whitespace a tag separates its parts with.
bool space(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;

/// Whether [name] can stand as an element or attribute name inside a tag.
///
/// The XML Name production, near enough: a letter, an underscore or a colon
/// first, then those and digits, hyphens and dots. Anything past ASCII is
/// taken as a letter, since what this guards against is a delimiter, and
/// every delimiter a tag has is ASCII.
bool named(String name) {
  if (name.isEmpty) {
    return false;
  }
  for (var at = 0; at < name.length; at += 1) {
    final unit = name.codeUnitAt(at);
    final letter =
        (unit >= 0x41 && unit <= 0x5A) ||
        (unit >= 0x61 && unit <= 0x7A) ||
        unit == 0x5F ||
        unit == 0x3A ||
        unit >= 0x80;
    final digit = unit >= 0x30 && unit <= 0x39;
    final rest = digit || unit == 0x2D || unit == 0x2E;
    if (at == 0 ? !letter : !(letter || rest)) {
      return false;
    }
  }
  return true;
}

/// [text] with the characters that cannot stand literally in an attribute
/// value written as references.
String escaped(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// A start tag of [name] saying [attributes], or an empty-element tag
/// where [closed].
String opener(
  String name,
  Map<String, String> attributes, {
  bool closed = false,
}) {
  final written = StringBuffer('<$name');
  for (final MapEntry(:key, :value) in attributes.entries) {
    written.write(' $key="${escaped(value)}"');
  }
  written.write(closed ? '/>' : '>');
  return written.toString();
}
