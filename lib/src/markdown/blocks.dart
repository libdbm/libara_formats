/// Markdown's block structure: the standard's first phase, a walk down the
/// lines opening and closing the blocks that hold each other.
///
/// Ported from markwrite's `blocks.dart`, with offsets in UTF-16 units of
/// the text read.
library;

/// A stretch of the text read, from its start to its end.
typedef Span = (int, int);

/// What a Markdown block is.
///
/// The standard's own list, less what this does not yet read: an HTML block
/// and a link reference definition are paragraphs here and are named in the
/// suite's own count.
enum Kind {
  /// The whole text.
  document,

  /// A block quote.
  quote,

  /// A list, holding its items.
  list,

  /// One item of a list.
  item,

  /// A paragraph.
  paragraph,

  /// An ATX or setext heading.
  heading,

  /// Fenced or indented code.
  code,

  /// A thematic break.
  rule,

  /// A pipe table.
  table,

  /// A paragraph that turned out to say where a link goes rather than
  /// anything a reader sees.
  definition,
}

/// One block of a Markdown document: what it is, where it stands, what of it
/// is syntax rather than words, and what stands inside it.
///
/// The syntax is kept as ranges rather than cut out, because the stream is
/// the source and stays the source: a marker is marked and then hidden, and
/// what a block says is what is left when the markers are taken away.
final class Block {
  /// What this block is. Not settled at once: a paragraph becomes a heading
  /// when the line under it says so, and by then it has been read.
  Kind kind;

  /// Where this block starts and ends in the text read.
  int start;

  /// Where this block ends, its line ending included.
  int end;

  /// The marks inside this block that are syntax: a quote's angle on
  /// every line it covers, a heading's hashes, a fence, an item's bullet,
  /// the indent that carries a block on.
  final List<Span> markers = [];

  /// The blocks this one holds, in order.
  final List<Block> children = [];

  /// A heading's level, one to six.
  int level = 0;

  /// Whether a list is numbered.
  bool ordered = false;

  /// Where a numbered list starts counting.
  int number = 1;

  /// Whether a blank line stands between this list's items.
  bool loose = false;

  /// The character a list's items are marked with, since a list ends where
  /// the mark changes.
  String marker = '';

  /// Whether a blank line has been met inside this since the last block was
  /// added to it, which is what makes a list loose once anything follows.
  bool blank = false;

  /// What a fence said of itself, which is the language a code block is in.
  String info = '';

  /// Whether a fenced block is still open, and what closes it.
  String fence = '';

  /// The column a fence stands at, or that an item's content is indented
  /// to.
  int indent = 0;

  /// A block of [kind] from [start] to [end], or empty where [end] is not
  /// given.
  Block(this.kind, this.start, [int? end]) : end = end ?? start;

  /// How long this block is.
  int get length => end - start;

  /// The language a fenced block said it is in, which is the first word of
  /// what it said of itself.
  String get language {
    final held = info.trim();
    final at = held.indexOf(RegExp(r'[ \t]'));
    return at < 0 ? held : held.substring(0, at);
  }

  @override
  String toString() => '$kind($start..$end)';
}

/// One line of the source: where it stands, and where its text begins once
/// the indent has been counted.
final class Line {
  /// Where the line starts.
  final int start;

  /// Where its text ends, before any line ending.
  final int end;

  /// Where the newline ending it stands, or the end of the source.
  final int over;

  /// The line from [start] to [end], its ending running to [over].
  const Line(this.start, this.end, this.over);
}

/// The lines of [source], each with the newline that ends it.
///
/// A return before the newline is part of the ending rather than of the
/// line: a file written on Windows ends every line that way, and a heading
/// or a rule is still one where its line stops before the return.
List<Line> lines(String source) {
  final held = <Line>[];
  var at = 0;
  while (at <= source.length) {
    final end = source.indexOf('\n', at);
    if (end < 0) {
      held.add(Line(at, source.length, source.length));
      break;
    }
    final text = end > at && source.codeUnitAt(end - 1) == 0x0D ? end - 1 : end;
    held.add(Line(at, text, end + 1));
    at = end + 1;
  }
  return held;
}

/// The blocks [source] is made of, and where a line opened more than
/// [deepest] of them, if one did.
///
/// The standard's first phase: a walk down the lines, opening and closing
/// the blocks that hold each other. What comes out is a tree whose leaves
/// are the paragraphs, the headings and the code, and whose branches are the
/// quotes and the lists. A line opens at most as many blocks as it has
/// markers, so asking after each line stops the walk before anything walks
/// the tree; the blocks read up to that line are closed where it starts.
(Block, int?) blocked(String source, {int deepest = 4096}) {
  final reading = Reading(source);
  for (final line in lines(source)) {
    reading.read(line);
    if (reading.depth > deepest) {
      return (reading.closed(line.start), line.start);
    }
  }
  return (reading.closed(source.length), null);
}

/// A walk down the lines of [source], one line at a time.
final class Reading {
  /// A walk with nothing read yet.
  Reading(this.source) : root = Block(Kind.document, 0, source.length) {
    _open.add(root);
  }

  /// The text read.
  final String source;

  /// The document, holding what has been read.
  final Block root;

  final _open = <Block>[];

  /// How many blocks stand open, the document included.
  int get depth => _open.length;

  /// Reads [line], and says whether it was blank.
  bool read(Line line) {
    _line(source, line, _open, root);
    return vacant(source, line.start, line.end);
  }

  /// The tree, every block closed at [at].
  Block closed(int at) {
    _closed(_open, 1, at);
    return root;
  }
}

/// How many columns of indent stand at [at], and where they end.
///
/// A tab stands to the next stop four columns apart, which is what makes an
/// indented code block written with tabs the same block as one written with
/// spaces.
(int, int) _indent(String source, int at, int end) {
  var columns = 0;
  var index = at;
  while (index < end) {
    if (source[index] == ' ') {
      columns += 1;
    } else if (source[index] == '\t') {
      columns += 4 - columns % 4;
    } else {
      break;
    }
    index += 1;
  }
  return (columns, index);
}

/// Whether [source] holds nothing but spaces, tabs and returns from [at]
/// to [end].
bool vacant(String source, int at, int end) {
  for (var index = at; index < end; index += 1) {
    if (source[index] != ' ' &&
        source[index] != '\t' &&
        source[index] != '\r') {
      return false;
    }
  }
  return true;
}

/// One line, against the blocks standing open.
///
/// The standard's own two steps: how far down the open blocks the line
/// carries by its own markers, and then what is left of it.
void _line(String source, Line line, List<Block> open, Block root) {
  var at = line.start;
  var matched = 1;
  for (var depth = 1; depth < open.length; depth += 1) {
    final block = open[depth];
    final (columns, from) = _indent(source, at, line.end);
    switch (block.kind) {
      case Kind.quote:
        if (columns <= 3 && from < line.end && source[from] == '>') {
          var to = from + 1;
          if (to < line.end && (source[to] == ' ' || source[to] == '\t')) {
            to += 1;
          }
          block.markers.add((at, to));
          at = to;
          matched = depth + 1;
          continue;
        }
      case Kind.item:
        // An item may begin with one blank line and no more. A marker with
        // nothing after it opens an item whose words are on the next line,
        // and where that line is blank too the item holds nothing and what
        // follows stands outside the list.
        if (vacant(source, at, line.end) && block.children.isEmpty) {
          break;
        }
        if (vacant(source, at, line.end)) {
          at = from;
          matched = depth + 1;
          continue;
        }
        if (columns >= block.indent) {
          final to = _column(source, at, line.end, block.indent);
          block.markers.add((at, to));
          at = to;
          matched = depth + 1;
          continue;
        }
      case Kind.list || Kind.document:
        // A list carries on wherever its items do, and holds nothing of its
        // own to match.
        matched = depth + 1;
        continue;
      default:
        // A leaf. Nothing nests inside one, so the walk stops here and what
        // is left of the line is the leaf's business.
        break;
    }
    break;
  }
  _rest(source, line, open, matched, at, root);
}

/// Where the column [want] stands from [at], counting a tab to its stop.
int _column(String source, int at, int end, int want) {
  var columns = 0;
  var index = at;
  while (index < end && columns < want) {
    if (source[index] == ' ') {
      columns += 1;
    } else if (source[index] == '\t') {
      columns += 4 - columns % 4;
    } else {
      break;
    }
    index += 1;
  }
  return index;
}

/// Whether the line at [at] begins a block of its own, which is what a
/// paragraph cannot be carried on across.
bool _starts(String source, int at, int end, {bool listed = false}) {
  final (columns, index) = _indent(source, at, end);
  if (columns > 3 || index >= end) {
    return false;
  }
  if (source[index] == '>' ||
      _broken(source, index, end) ||
      _atx(source, index, end) > 0 ||
      _fence(source, index, end) != null) {
    return true;
  }
  final item = _item(source, index, end);
  // An item that begins a list has to have something in it, and a numbered
  // one has to begin at one, so that a paragraph is not cut in two by a
  // sentence ending in a year. Neither holds inside a list already: there
  // the item is the next one, empty or not and numbered whatever it is.
  return item != null &&
      (listed || !vacant(source, item.after, end)) &&
      (!item.ordered || item.number == 1 || listed);
}

/// What is left of the line once the open containers have had their markers.
void _rest(
  String source,
  Line line,
  List<Block> open,
  int matched,
  int from,
  Block root,
) {
  var at = from;
  final held = open.last;
  // A fenced block takes every line until its own fence closes it. Every
  // container it stands in has to have carried the line: a fence inside a
  // quotation ends where the quotation does.
  if (held.kind == Kind.code &&
      held.fence.isNotEmpty &&
      matched >= open.length - 1) {
    final (columns, index) = _indent(source, at, line.end);
    if (columns <= 3 && _fenced(source, index, line.end, held.fence)) {
      held.markers.add((at, line.end));
      held.end = line.over;
      open.removeLast();
      return;
    }
    if (held.indent > 0) {
      final to = _column(source, at, line.end, held.indent);
      if (to > at) {
        held.markers.add((at, to));
      }
    }
    held.end = line.over;
    return;
  }
  // An indented code block takes every line that keeps its indent, and every
  // blank line between them.
  if (held.kind == Kind.code && held.fence.isEmpty) {
    final (columns, _) = _indent(source, at, line.end);
    if (columns >= 4 || vacant(source, at, line.end)) {
      // Four columns of every line belong to the block rather than to the
      // code, a line holding nothing else included: what a blank line inside
      // a code block shows is whatever it has past the fourth column, which
      // is usually nothing at all.
      final to = _column(source, at, line.end, 4);
      if (to > at) {
        held.markers.add((at, to));
      }
      if (!vacant(source, at, line.end)) {
        held.end = line.over;
      }
      return;
    }
  }
  // A line of equals or dashes under a paragraph makes it a heading of what
  // stands above, which is why this is asked before a paragraph is closed
  // and before a line of dashes is read as a break.
  if (held.kind == Kind.paragraph && matched >= open.length - 1) {
    final (columns, index) = _indent(source, at, line.end);
    final level = columns <= 3 ? _setext(source, index, line.end) : 0;
    if (level > 0) {
      held.markers.add((at, line.end));
      held.end = line.over;
      open.removeLast();
      _heading(held, level);
      return;
    }
  }
  // A line that starts nothing of its own carries the paragraph on, whether
  // or not it carried on the blocks the paragraph was written under. That is
  // the standard's lazy continuation, and it is why a quotation may be
  // written with the angle on its first line alone.
  if (held.kind == Kind.paragraph &&
      !vacant(source, at, line.end) &&
      !_starts(
        source,
        at,
        line.end,
        listed: open.any((block) => block.kind == Kind.list),
      )) {
    held.end = line.over;
    return;
  }
  // Everything else the line did not carry on is closed.
  _closed(open, matched, line.start);
  // A list that no item carries on ends here. The list itself has nothing to
  // match on a line, so it is closed by what follows it rather than by what
  // it holds: anything but another item ends it.
  while (open.last.kind == Kind.list && !vacant(source, at, line.end)) {
    final (_, index) = _indent(source, at, line.end);
    // A rule is a rule before it is an item, so a list of bullets ends at
    // the line of stars under it rather than holding one.
    if (!_broken(source, index, line.end) &&
        _item(source, index, line.end) != null) {
      break;
    }
    _closed(open, open.length - 1, line.start);
  }
  var blank = vacant(source, at, line.end);
  if (blank) {
    // A blank line inside a list is what makes it loose, but only once
    // something follows it: a list is not loose for the blank line that ends
    // it.
    for (final block in open) {
      if (block.kind == Kind.list || block.kind == Kind.item) {
        block.blank = true;
      }
    }
  }
  // New containers, as deep as the line opens them.
  while (true) {
    if (blank) {
      break;
    }
    final (columns, index) = _indent(source, at, line.end);
    if (columns >= 4 && open.last.kind != Kind.paragraph) {
      break;
    }
    if (columns > 3) {
      break;
    }
    if (index < line.end && source[index] == '>') {
      var to = index + 1;
      if (to < line.end && (source[to] == ' ' || source[to] == '\t')) {
        to += 1;
      }
      final quote = Block(Kind.quote, at);
      quote.markers.add((at, to));
      _added(open, quote);
      at = to;
      blank = vacant(source, at, line.end);
      continue;
    }
    final item = _item(source, index, line.end);
    if (item != null && !_broken(source, index, line.end)) {
      var list = open.last.kind == Kind.list ? open.last : null;
      if (list != null &&
          (list.ordered != item.ordered || list.marker != item.marker)) {
        // A list ends where its mark changes: a bullet list and the list of
        // pluses under it are two lists, which is what the mark is for.
        _closed(open, open.length - 1, at);
        list = null;
      }
      if (list == null) {
        final held = Block(Kind.list, at)
          ..ordered = item.ordered
          ..number = item.number;
        held.marker = item.marker;
        _added(open, held);
      }
      final one = Block(Kind.item, at);
      // A marker with nothing after it on its line opens an item whose words
      // begin on the next one, so what is left of this line is the marker's
      // too, the line ending included. Otherwise the item would say a line
      // ending before it said anything at all.
      one.markers.add((
        at,
        vacant(source, item.after, line.end) ? line.over : item.after,
      ));
      // What the item's content is indented to, which every line it carries
      // on with has to reach.
      final (_, text) = _indent(source, item.after, line.end);
      // How far into the line the item's content stands, which every line
      // carrying it on has to reach. Where the marker is followed by more
      // than four spaces the content begins one space after the marker and
      // the rest is code, since five spaces after a bullet is a bullet and
      // then an indented block.
      final spaces = _width(source, item.after, text);
      final wide = vacant(source, item.after, line.end) || spaces > 4
          ? columns + item.width + 1
          : columns + item.width + spaces;
      one.indent = wide;
      _added(open, one);
      at = item.after;
      // Only as far as the content stands. Everything past that is the
      // item's own words, and five spaces after a bullet is a bullet
      // followed by an indented block.
      final next = _column(source, at, line.end, wide - columns - item.width);
      if (next > at) {
        one.markers.add((at, next));
        at = next;
      }
      blank = vacant(source, at, line.end);
      continue;
    }
    break;
  }
  _leaf(source, line, open, at, blank);
}

/// How many columns stand between [at] and [to].
int _width(String source, int at, int to) {
  var columns = 0;
  for (var index = at; index < to; index += 1) {
    columns += source[index] == '\t' ? 4 - columns % 4 : 1;
  }
  return columns;
}

void _added(List<Block> open, Block block) {
  // Anything added after a blank line makes the list it stands in loose: the
  // blank now stands between two blocks rather than at the end of one. The
  // innermost list alone, since a blank line inside the deepest item says
  // nothing about the lists that hold it.
  var settled = false;
  for (var at = open.length - 1; at >= 0; at -= 1) {
    final held = open[at];
    if (settled) {
      // Outside the list this block landed in. The blank line stood inside
      // that list rather than between this one's items, so it says nothing
      // here and must not be waiting when this list takes its next item.
      if (held.kind == Kind.list || held.kind == Kind.item) {
        held.blank = false;
      }
      continue;
    }
    if (held.kind == Kind.list) {
      if (held.blank) {
        held
          ..loose = true
          ..blank = false;
      }
      settled = true;
      continue;
    }
    if (held.kind == Kind.item && held.blank) {
      held.blank = false;
    }
  }
  open.last.children.add(block);
  open.add(block);
}

/// Everything from [depth] down, closed at [at].
void _closed(List<Block> open, int depth, int at) {
  while (open.length > depth) {
    final held = open.removeLast();
    if (held.end < at) {
      held.end = at;
    }
  }
}

/// The leaf the rest of the line is.
void _leaf(String source, Line line, List<Block> open, int from, bool blank) {
  // Where the line's own words begin, once the blocks it stands in have had
  // their markers. A leaf inside a quotation begins after the angle, not at
  // the start of the line: a heading that began before the angle that holds
  // it would be a heading crossing a quotation, which is not a thing markup
  // can be.
  var at = from;
  final held = open.last;
  if (blank) {
    if (held.kind == Kind.paragraph) {
      open.removeLast();
    }
    return;
  }
  final (columns, index) = _indent(source, at, line.end);
  if (columns >= 4 && held.kind != Kind.paragraph) {
    final code = held.kind == Kind.code && held.fence.isEmpty
        ? held
        : (Block(Kind.code, from)..indent = 4);
    if (!identical(code, held)) {
      _added(open, code);
    }
    final to = _column(source, at, line.end, 4);
    code.markers.add((at, to));
    code.end = line.over;
    return;
  }
  at = index;
  if (_broken(source, at, line.end)) {
    if (held.kind == Kind.paragraph) {
      open.removeLast();
    }
    final rule = Block(Kind.rule, from, line.over);
    rule.markers.add((from, line.end));
    open.last.children.add(rule);
    return;
  }
  final level = _atx(source, at, line.end);
  if (level > 0) {
    if (held.kind == Kind.paragraph) {
      open.removeLast();
    }
    final heading = Block(Kind.heading, from, line.over)..level = level;
    var to = at + level;
    // Every space between the hashes and the words belongs to the marker,
    // however many a writer lined the heading up with.
    while (to < line.end && (source[to] == ' ' || source[to] == '\t')) {
      to += 1;
    }
    heading.markers.add((from, to));
    // A heading may be closed as well as opened, and the hashes that close
    // it are syntax like the ones that open it.
    var back = line.end;
    while (back > to && (source[back - 1] == ' ' || source[back - 1] == '\t')) {
      back -= 1;
    }
    var hashes = back;
    while (hashes > to && source[hashes - 1] == '#') {
      hashes -= 1;
    }
    if (hashes < back &&
        (hashes == to ||
            source[hashes - 1] == ' ' ||
            source[hashes - 1] == '\t')) {
      var space = hashes;
      while (space > to &&
          (source[space - 1] == ' ' || source[space - 1] == '\t')) {
        space -= 1;
      }
      heading.markers.add((space, line.end));
    } else if (back < line.end) {
      heading.markers.add((back, line.end));
    }
    open.last.children.add(heading);
    return;
  }
  final fence = _fence(source, at, line.end);
  if (fence != null) {
    if (held.kind == Kind.paragraph) {
      open.removeLast();
    }
    final code = Block(Kind.code, from, line.over)
      ..fence = fence.mark
      ..indent = columns
      ..info = fence.info;
    // The line ending too: the fence is a line of syntax, and the newline
    // that ends it is the fence's rather than the first line of the code.
    code.markers.add((from, line.over));
    _added(open, code);
    return;
  }
  final paragraph = Block(Kind.paragraph, at, line.over);
  _added(open, paragraph);
}

/// A heading, once a line under a paragraph has said it is one.
///
/// The paragraph becomes the heading where it stands: what it holds is what
/// the heading says, and the line under it is the marker that said so.
void _heading(Block held, int level) {
  held
    ..kind = Kind.heading
    ..level = level;
}

/// Whether the line at [at] is nothing but three or more of one mark.
bool _broken(String source, int at, int end) {
  if (at >= end) {
    return false;
  }
  final mark = source[at];
  if (mark != '*' && mark != '-' && mark != '_') {
    return false;
  }
  var count = 0;
  for (var index = at; index < end; index += 1) {
    final held = source[index];
    if (held == mark) {
      count += 1;
    } else if (held != ' ' && held != '\t') {
      return false;
    }
  }
  return count >= 3;
}

/// The level of the ATX heading at [at], or nought where there is none.
int _atx(String source, int at, int end) {
  var hashes = at;
  while (hashes < end && source[hashes] == '#') {
    hashes += 1;
  }
  final level = hashes - at;
  if (level < 1 || level > 6) {
    return 0;
  }
  if (hashes == end || source[hashes] == ' ' || source[hashes] == '\t') {
    return level;
  }
  return 0;
}

/// The level a line of equals or dashes under a paragraph makes it.
int _setext(String source, int at, int end) {
  if (at >= end) {
    return 0;
  }
  final mark = source[at];
  if (mark != '=' && mark != '-') {
    return 0;
  }
  var index = at;
  while (index < end && source[index] == mark) {
    index += 1;
  }
  while (index < end && (source[index] == ' ' || source[index] == '\t')) {
    index += 1;
  }
  return index == end ? (mark == '=' ? 1 : 2) : 0;
}

/// The fence at [at], as what closes it and what it said of itself.
({String mark, String info})? _fence(String source, int at, int end) {
  if (at >= end) {
    return null;
  }
  final mark = source[at];
  if (mark != '`' && mark != '~') {
    return null;
  }
  var index = at;
  while (index < end && source[index] == mark) {
    index += 1;
  }
  if (index - at < 3) {
    return null;
  }
  final info = source.substring(index, end).trim();
  // A backtick fence's information may not hold a backtick, which is what
  // keeps a code span from being read as one.
  if (mark == '`' && info.contains('`')) {
    return null;
  }
  return (mark: source.substring(at, index), info: info);
}

/// Whether the line at [at] closes a fence of [mark].
bool _fenced(String source, int at, int end, String mark) {
  var index = at;
  while (index < end && source[index] == mark[0]) {
    index += 1;
  }
  if (index - at < mark.length) {
    return false;
  }
  return vacant(source, index, end);
}

/// The list item at [at]: which kind, how wide its marker is, and where the
/// marker ends.
({bool ordered, int number, String marker, int width, int after})? _item(
  String source,
  int at,
  int end,
) {
  if (at >= end) {
    return null;
  }
  final held = source[at];
  if (held == '-' || held == '+' || held == '*') {
    if (at + 1 < end && source[at + 1] != ' ' && source[at + 1] != '\t') {
      return null;
    }
    return (ordered: false, number: 1, marker: held, width: 1, after: at + 1);
  }
  var index = at;
  while (index < end && index - at < 9 && _digit(source[index])) {
    index += 1;
  }
  if (index == at || index >= end) {
    return null;
  }
  final mark = source[index];
  if (mark != '.' && mark != ')') {
    return null;
  }
  if (index + 1 < end &&
      source[index + 1] != ' ' &&
      source[index + 1] != '\t') {
    return null;
  }
  return (
    ordered: true,
    number: int.tryParse(source.substring(at, index)) ?? 1,
    marker: mark,
    width: index + 1 - at,
    after: index + 1,
  );
}

bool _digit(String held) =>
    held.compareTo('0') >= 0 && held.compareTo('9') <= 0;
