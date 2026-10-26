/// Markdown's pipe tables: a line holding a bar, a line of dashes under it
/// with as many cells, and the rows that follow to the paragraph's end.
///
/// Ported from markwrite's `markdown.dart`. Positions are in the words of
/// the paragraph a table is read from, as stretches from start to end.
library;

/// One row of a pipe table: the whole line, the content of each cell with
/// the bars and the spaces around them left out, and each bar with the
/// spaces around it.
typedef Row = ({
  (int, int) line,
  List<(int, int)> cells,
  List<(int, int)> bars,
});

/// One pipe table: all of it, the line of dashes under its head, and its
/// rows, the head first.
typedef Table = ({(int, int) extent, (int, int) ruling, List<Row> rows});

/// The pipe tables in [text].
///
/// This is the extended Markdown that everything from GitHub to pandoc
/// reads, and the only block construct here that is found in the words of
/// a paragraph rather than by the walk down the lines.
List<Table> tables(String text) {
  final found = <Table>[];
  final lines = _lines(text);
  var at = 0;
  while (at < lines.length - 1) {
    final head = lines[at];
    if (!_barred(text, head) ||
        !_dashed(text, lines[at + 1]) ||
        _row(text, head).cells.length !=
            _row(text, lines[at + 1]).cells.length) {
      at += 1;
      continue;
    }
    // Every line after the ruling is a row, with a bar or without one: what
    // would end the table, a blank line or another block, has already ended
    // the paragraph.
    final rows = <Row>[_row(text, head)];
    var end = at + 2;
    while (end < lines.length) {
      rows.add(_row(text, lines[end]));
      end += 1;
    }
    found.add((
      extent: (head.$1, lines[end - 1].$2),
      ruling: _trimmed(text, lines[at + 1]),
      rows: rows,
    ));
    at = end;
  }
  return found;
}

/// The lines of [text], each without its newline.
List<(int, int)> _lines(String text) {
  final lines = <(int, int)>[];
  var start = 0;
  for (var at = 0; at <= text.length; at += 1) {
    if (at == text.length || text[at] == '\n') {
      lines.add((start, at));
      start = at + 1;
    }
  }
  return lines;
}

bool _barred(String text, (int, int) line) {
  // A line opening with an ATX marker is a heading, whatever else it holds,
  // and a bar on it is a bar in a heading.
  if (_headed(text, line)) {
    return false;
  }
  for (var at = line.$1; at < line.$2; at += 1) {
    if (text[at] == r'\') {
      at += 1;
      continue;
    }
    if (text[at] == '|') {
      return true;
    }
  }
  return false;
}

/// Whether [line] opens with an ATX heading marker: one to six hashes and a
/// space.
bool _headed(String text, (int, int) line) {
  var at = line.$1;
  while (at < line.$2 && at - line.$1 < 6 && text[at] == '#') {
    at += 1;
  }
  return at > line.$1 && at < line.$2 && text[at] == ' ';
}

/// Whether [line] is the row of dashes that makes the line above it a head.
bool _dashed(String text, (int, int) line) {
  final said = text.substring(line.$1, line.$2).trim();
  if (said.isEmpty || !said.contains('-')) {
    return false;
  }
  for (final character in said.split('')) {
    if (character != '-' &&
        character != '|' &&
        character != ':' &&
        character != ' ') {
      return false;
    }
  }
  return true;
}

/// The cells and bars of [line].
Row _row(String text, (int, int) line) {
  final marks = <int>[];
  for (var at = line.$1; at < line.$2; at += 1) {
    if (text[at] == r'\') {
      at += 1;
      continue;
    }
    if (text[at] == '|') {
      marks.add(at);
    }
  }
  final cells = <(int, int)>[];
  for (var at = 0; at <= marks.length; at += 1) {
    final from = at == 0 ? line.$1 : marks[at - 1] + 1;
    final to = at == marks.length ? line.$2 : marks[at];
    if (to <= from) {
      continue;
    }
    var start = from;
    var end = to;
    while (start < end && text[start] == ' ') {
      start += 1;
    }
    while (end > start && text[end - 1] == ' ') {
      end -= 1;
    }
    // A cell between two bars is a cell however little it says, and the
    // caret stands in it where its words would begin: after the first
    // space, as a bar is written. What lies outside the outer bars is not a
    // cell at all.
    if (end > start) {
      cells.add((start, end));
    } else if (at > 0 && at < marks.length) {
      cells.add((from + 1, from + 1));
    }
  }
  final bars = <(int, int)>[];
  for (final at in marks) {
    var start = at;
    var end = at + 1;
    // Back over the spaces before it, but not over those the bar before
    // already took: two bars with nothing but spaces between them, which is
    // an empty cell, would otherwise cross.
    final taken = bars.isEmpty ? line.$1 : bars.last.$2;
    while (start > taken && text[start - 1] == ' ') {
      start -= 1;
    }
    // Forward over the spaces after it, but not into an empty cell.
    while (end < line.$2 && text[end] == ' ' && !cells.contains((end, end))) {
      end += 1;
    }
    bars.add(_trimmed(text, (start, end)));
  }
  return (line: line, cells: cells, bars: bars);
}

/// [range] with the whitespace at the head of a line taken off it, which is
/// the indent of the block the table stands in rather than a bar's.
(int, int) _trimmed(String text, (int, int) range) {
  if (range.$1 != 0 && text[range.$1 - 1] != '\n') {
    return range;
  }
  var start = range.$1;
  while (start < range.$2 && (text[start] == ' ' || text[start] == '\t')) {
    start += 1;
  }
  return (start, range.$2);
}
