import 'dart:math';

import 'package:libara/libara.dart';

import '../convert.dart';
import '../editing.dart';
import '../formats.dart';
import '../kinds.dart';
import '../lexing.dart';
import '../limits.dart';
import '../positions.dart';
import '../notation.dart';
import '../safety.dart';
import 'blocks.dart' as md;
import 'inlines.dart' as md;
import 'inlines.dart' show Content, Links;
import 'tables.dart' as md;

part 'edits.dart';
part 'write.dart';

/// Markdown, its blocks read as CommonMark reads them.
///
/// Layer 2 tiles the text. Each mark that is syntax is a token named
/// for the block it belongs to: a heading's hashes and its underline, a
/// quote's angle on every line it carries on, an item's bullet and the
/// indent that carries it on, a fence and code's indent, a rule. What is
/// left is runs of `#text`, cut where a block starts or ends, so that every
/// block covers whole tokens.
///
/// Layer 3 holds the blocks, named as HTML names them: `p`, `h1` to `h6`,
/// `blockquote`, `ul` and `ol`, `li`, `pre`, `hr`, and a pipe table's
/// `table`, `tr`, `th` and `td`, its bars tokens of their rows and the
/// dashes under its head a token of the table. A block ends before
/// the line ending after it. A paragraph, a list, and an item's words have
/// no tokens of their own, and a paragraph inside a tight list is not a
/// block at all, its words being the item's. A code block says its
/// language as `class`, and a numbered list where it starts counting as
/// `start` when that is not one.
///
/// A line means what the lines before it say, so a token cannot be read
/// from its own start. An edit is read again from a place no block spans
/// to one past the edit where the new reading has nothing open: see
/// [_Grammar._window].
final class Markdown implements Syntax {
  /// The Markdown syntax, reading within [limits].
  const Markdown({this.limits = standard});

  /// What reading may build.
  final Limits limits;

  @override
  Result<Layered<int>> decode(Sequence<int> form) => decoded(
    'markdown',
    _Grammar(limits),
    limits,
    form,
    indexed: const ['label'],
  );

  /// [value]'s text, where it was read as Markdown, and otherwise its
  /// content and elements as Markdown represents them.
  @override
  Result<Sequence<int>> encode(Layered<int> value) => value.grammar is _Grammar
      ? Success(value.items)
      : nodes(value, 'markdown').map((tree) {
          final written = _Writer(tree.content)
              .render(0, tree.content.length, tree.roots, '');
          return Text.of(written) as Sequence<int>;
        });
}

/// What a stretch of text reads as, in UTF-16 units of it: its tokens and
/// elements, the links it defines in order, and where the reading stopped
/// at a cap, with why.
typedef _Read = ({
  List<Found> tokens,
  List<Found> elements,
  List<(String, String, String?)> definitions,
  (int, String)? stop,
});

final class _Grammar implements Grammar<int> {
  _Grammar(this.limits);

  final Limits limits;

  /// The text layer 2 last read and what it read as, which layer 3 reads
  /// next when the same stretch is asked of it: within one edit nothing
  /// outside the stretch changes between the two, so neither do the links
  /// defined there. Taken once, so nothing is held after.
  (String, _Read)? _last;

  @override
  int get depth => 3;

  @override
  Derived derive(Layered<int> document, int layer, Range region) =>
      layer == 2 ? _tokens(document, region) : _blocks(document, region);

  /// Layer 2's tokens over [region].
  Derived _tokens(Layered<int> document, Range region) {
    final text = covered(document, region);
    final positions = Positions(text);
    final read = _read(text, _outer(document, region.start, region.end));
    _last = (text, read);
    final names = <String, Str>{};
    Range placed(int from, int to) =>
        span(region.start + positions[from], positions[to] - positions[from]);
    return (
      ranges: [
        for (final (from, to, name, said) in read.tokens)
          ARange.from(placed(from, to), {
            '': names[name] ??= literal(name),
            for (final MapEntry(:key, :value) in said.entries)
              key: literal(value),
          }),
      ],
      diagnostics: [
        if (read.stop case (final at, final why))
          limited(placed(at, text.length), why),
      ],
    );
  }

  /// Layer 3's elements over [region] of layer 2.
  Derived _blocks(Layered<int> document, Range region) {
    final held = [for (final (_, token) in document.span(2, region)) token];
    if (held.isEmpty) {
      return (ranges: const [], diagnostics: const []);
    }
    final from = held.first.start;
    final text = covered(document, span(from, held.last.end - from));
    final positions = Positions(text);
    // The first token starting at or after [at], in code points.
    int index(int at) {
      var (low, high) = (0, held.length);
      while (low < high) {
        final middle = (low + high) ~/ 2;
        if (held[middle].start < at) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      return region.start + low;
    }

    final last = _last;
    _last = null;
    final read = last != null && last.$1 == text
        ? last.$2
        : _read(text, _outer(document, from, held.last.end));
    Range placed(int start, int end) {
      final first = index(from + positions[start]);
      return span(first, index(from + positions[end]) - first);
    }

    return (
      ranges: [
        for (final (start, end, name, said) in read.elements)
          ARange.from(placed(start, end), {
            '': literal(name),
            for (final MapEntry(:key, :value) in said.entries)
              key: literal(value),
          }),
      ],
      diagnostics: [
        for (final (start, end, name, said) in read.elements)
          if (_running(name, said) case final String why)
            ARange.from(placed(start, end), {'message': Str(Text.of(why))}),
      ],
    );
  }

  /// Why an element of [name] saying [said] is one a browser would run,
  /// or null where it is not.
  static String? _running(String name, Map<String, String> said) {
    if (active.contains(name)) {
      return 'markdown: an element named $name, which a browser runs';
    }
    for (final key in const ['href', 'src']) {
      if (said[key] case final String target when runs(target)) {
        return 'markdown: a $key that runs rather than goes somewhere';
      }
    }
    return null;
  }

  /// The links the tokens of [document] define before item [from] of the
  /// text and after item [to], the first of a name counting: gathered only
  /// once a name is looked up, since most stretches look none up, and found
  /// by the key a definition says, so the cost follows the definitions.
  static (Links, Links) _outer(Layered<int> document, int from, int to) {
    Map<String, (String, String?)>? early;
    final late = <String, (String, String?)>{};
    Map<String, (String, String?)> gathered() {
      if (early case final held?) {
        return held;
      }
      final held = <String, (String, String?)>{};
      for (final (_, token) in document.having(2, 'label')) {
        // A token of no length is text an edit took away, carried over
        // collapsed until it is read again.
        if (token.get('label') case final label? when token.length > 0) {
          final said = ('${token.get('href')}', token.get('title')?.toString());
          if (token.end <= from) {
            held.putIfAbsent('$label', () => said);
          } else if (token.start >= to) {
            late.putIfAbsent('$label', () => said);
          }
        }
      }
      return early = held;
    }

    return (
      (label) => gathered()[label],
      (label) {
        gathered();
        return late[label];
      },
    );
  }

  /// What [text] reads as, the links defined before it and after it being
  /// [outer].
  _Read _read(String text, (Links, Links) outer) {
    final (root, deep) = md.blocked(text, deepest: limits.depth ?? 1 << 30);
    final reach = deep ?? text.length;
    final marks = <Found>[];
    final elements = <Found>[];
    final definitions = <(String, String, String?)>[];
    // The words of each paragraph and heading, with the markers that stand
    // inside them: their own, and those of the blocks they stand in.
    final leaves = <Content>[];
    // In pre-order, each block with whether it stands in a tight list and
    // the markers of the blocks above it.
    final stack = [
      for (final child in root.children.reversed)
        (child, false, const <md.Span>[]),
    ];
    while (stack.isNotEmpty) {
      final (block, tight, above) = stack.removeLast();
      final name = _named(block);
      for (final (start, end) in block.markers) {
        marks.add((start, end, name!, const {}));
      }
      var end = min(block.end, text.length);
      while (end > block.start &&
          (text.codeUnitAt(end - 1) == 0x0A ||
              text.codeUnitAt(end - 1) == 0x0D)) {
        end--;
      }
      var shown = true;
      if (block.kind == md.Kind.paragraph || block.kind == md.Kind.heading) {
        final holes = [
          ...block.markers,
          for (final (from, to) in above)
            if (from < end && block.start < to) (from, to),
        ];
        var content = Content.of(text, block.start, end, holes);
        if (block.kind == md.Kind.paragraph) {
          // What a paragraph opens with may say where links go, which shows
          // nothing: each definition is a token, and a paragraph holding
          // nothing else is no block.
          var at = 0;
          while (true) {
            final found = md.defined(content.text, at);
            if (found == null) {
              break;
            }
            final (over, label, href, title) = found;
            final said = {'label': label, 'href': href, 'title': ?title};
            // The first piece says what is defined, as the one token a
            // definition is where nothing stands inside it.
            for (final (index, (start, stop)) in _pieces(
              content,
              at,
              over,
            ).indexed) {
              marks.add((start, stop, '#definition', index == 0 ? said : {}));
              holes.add((start, stop));
            }
            definitions.add((label, href, title));
            at = over;
          }
          if (at > 0) {
            shown = at < content.text.length;
            content = Content.of(text, block.start, end, holes);
          }
        }
        final found = block.kind == md.Kind.paragraph && shown
            ? md.tables(content.text)
            : const <md.Table>[];
        for (final (:extent, :ruling, :rows) in found) {
          // The lines of the paragraph before the table are a paragraph of
          // their own, ending with the line before the head.
          if (extent.$1 > 0) {
            final last = extent.$1 - 1;
            if (!tight) {
              final (start, stop) = content.reach(0, last);
              elements.add((start, stop, 'p', _saying(block)));
            }
            leaves.add(
              Content(
                content.text.substring(0, last),
                content.at.sublist(0, last),
              ),
            );
          }
          for (final (start, stop) in _pieces(content, ruling.$1, ruling.$2)) {
            marks.add((start, stop, 'table', const {}));
          }
          final (start, stop) = content.reach(extent.$1, extent.$2);
          elements.add((start, stop, 'table', const {}));
          for (final (index, (:line, :cells, :bars)) in rows.indexed) {
            for (final (from, to) in bars) {
              for (final (start, stop) in _pieces(content, from, to)) {
                marks.add((start, stop, 'tr', const {}));
              }
            }
            final (start, stop) = content.reach(line.$1, line.$2);
            elements.add((start, stop, 'tr', const {}));
            // The first row is the head, which is what the dashes under it
            // say.
            for (final (from, to) in cells) {
              final (start, stop) = content.reach(from, to);
              elements.add((start, stop, index == 0 ? 'th' : 'td', const {}));
              if (to > from) {
                leaves.add(
                  Content(
                    content.text.substring(from, to),
                    content.at.sublist(from, to),
                  ),
                );
              }
            }
          }
        }
        if (found.isNotEmpty) {
          // A paragraph whose words are a table is the table.
          shown = false;
        } else if (shown) {
          leaves.add(content);
        }
      }
      if (name != null &&
          shown &&
          !(tight && block.kind == md.Kind.paragraph)) {
        elements.add((block.start, end, name, _saying(block)));
      }
      final inner = switch (block.kind) {
        md.Kind.list => !block.loose,
        md.Kind.item => tight,
        _ => false,
      };
      final under = block.markers.isEmpty
          ? above
          : [...above, ...block.markers];
      for (final child in block.children.reversed) {
        stack.add((child, inner, under));
      }
    }
    final own = <String, (String, String?)>{};
    for (final (label, href, title) in definitions) {
      own.putIfAbsent(label, () => (href, title));
    }
    final (before, after) = outer;
    (String, String?)? links(String label) =>
        before(label) ?? own[label] ?? after(label);
    for (final content in leaves) {
      final (:tokens, elements: made) = md.inlined(content, links);
      marks.addAll(tokens);
      elements.addAll(made);
    }
    marks.sort((one, other) => one.$1.compareTo(other.$1));
    // Where a line follows a blank one, which is where a stretch read again
    // may start or stop, so that it stops between two tokens whatever
    // stands indented at the head of the line.
    final lines = md.lines(text);
    final heads = [
      for (var at = 1; at < lines.length; at++)
        if (md.vacant(text, lines[at - 1].start, lines[at - 1].end) &&
            !md.vacant(text, lines[at].start, lines[at].end))
          lines[at].start,
    ];
    // A list sorted, its repeats passed over, rather than a set: a book
    // has a hundred thousand of them.
    final cuts = <int>[0, reach, ...heads];
    for (final (start, end, _, _) in marks) {
      cuts
        ..add(start)
        ..add(end);
    }
    for (final (start, end, _, _) in elements) {
      cuts
        ..add(start)
        ..add(end);
    }
    cuts.sort();
    final tokens = <Found>[];
    var mark = 0;
    var from = 0;
    for (final to in cuts) {
      if (to <= from || to > reach) {
        continue;
      }
      while (mark < marks.length && marks[mark].$2 <= from) {
        mark++;
      }
      tokens.add(
        mark < marks.length && marks[mark].$1 <= from
            ? (from, to, marks[mark].$3, marks[mark].$4)
            : (from, to, prose, const {}),
      );
      from = to;
    }
    (int, String)? stop = deep == null
        ? null
        : (reach, 'blocks nested deeper than ${limits.depth}');
    final most = limits.markers;
    if (most != null && tokens.length > most) {
      final at = tokens[most - 1].$1;
      tokens.length = most - 1;
      stop = (at, 'more than $most tokens');
    }
    if (stop case (final at, _) when at < text.length) {
      tokens.add((at, text.length, prose, const {}));
    }
    return (
      tokens: tokens,
      elements: elements,
      definitions: definitions,
      stop: stop,
    );
  }

  /// The stretches of the text read under characters [from] to [to] of
  /// [content]'s words, split where a hole stands between them.
  static List<md.Span> _pieces(Content content, int from, int to) {
    final pieces = <md.Span>[];
    for (var at = from; at < to; at++) {
      final place = content.at[at];
      if (pieces.isNotEmpty && pieces.last.$2 == place) {
        pieces.last = (pieces.last.$1, place + 1);
      } else {
        pieces.add((place, place + 1));
      }
    }
    return pieces;
  }

  /// The name of [block]'s element and of its markers.
  static String? _named(md.Block block) => switch (block.kind) {
    md.Kind.paragraph => 'p',
    md.Kind.heading => 'h${block.level}',
    md.Kind.rule => 'hr',
    md.Kind.quote => 'blockquote',
    md.Kind.code => 'pre',
    md.Kind.list => block.ordered ? 'ol' : 'ul',
    md.Kind.item => 'li',
    md.Kind.document || md.Kind.table || md.Kind.definition => null,
  };

  /// What [block] says of itself: the language a fence named, its escapes
  /// and references read, and where a numbered list starts counting.
  static Map<String, String> _saying(md.Block block) => {
    if (block.kind == md.Kind.code && block.language.isNotEmpty)
      'class': 'language-${md.says(block.language)}',
    if (block.kind == md.Kind.list && block.ordered && block.number != 1)
      'start': '${block.number}',
  };

  /// At layer 2, the [_window] of [changed]; at layer 3, the tokens it
  /// covers.
  @override
  Range affected(Layered<int> document, int layer, Range changed) {
    if (layer == 2) {
      // Every link written by name may go somewhere else once what the
      // window defines changes, so the whole text is read again.
      final window = _window(document, changed);
      final none = ((String _) => null, (String _) => null);
      final now = _read(covered(document, window), none).definitions;
      final before = [
        for (final (_, token) in document.within(2, window))
          if (token.get('label') case final label?)
            ('$label', '${token.get('href')}', token.get('title')?.toString()),
      ];
      return '$now' == '$before' ? window : span(0, document.items.length);
    }
    final from = nth(document, changed.start)?.start ?? document.items.length;
    final to = changed.length > 0 ? nth(document, changed.end - 1)!.end : from;
    final window = _window(document, span(from, to - from));
    final first = earliest(document, (token) => token.end > window.start);
    final last = earliest(document, (token) => token.start >= window.end);
    return span(first, last - first);
  }

  /// The text to read again when [changed] items of it changed: from the
  /// boundary before the one at or before the change, to the first
  /// boundary past it where the new reading has nothing open.
  ///
  /// A boundary is a line that is not blank, that a blank line stands
  /// before, where a token starts and that no block spans:
  /// the reading there has nothing open, so a stretch read from one is
  /// read as the whole text reads it. One boundary back, since what is
  /// typed at a block's head can carry on the list before it. Forward past
  /// the change, since a line starting where something was deleted says
  /// something new, to where the old reading and the new both had nothing
  /// open, since from there on both read the same text alike.
  Range _window(Layered<int> document, Range changed) {
    final length = document.items.length;
    final first = _boundary(document, min(changed.start + 1, length));
    final from = first == 0 ? 0 : _boundary(document, first);
    for (var size = changed.end - from + seed; ; size *= 2) {
      final end = min(from + size, length);
      final text = covered(document, span(from, end - from));
      final positions = Positions(text);
      final reading = md.Reading(text);
      final held = md.lines(text);
      var blank = false;
      for (final (index, line) in held.indexed) {
        final at = from + positions[line.start];
        if (index > 0 &&
            blank &&
            !md.vacant(text, line.start, line.end) &&
            at > changed.end &&
            reading.depth == 1 &&
            _clean(document, at)) {
          return span(from, at - from);
        }
        if (index == held.length - 1 && end < length) {
          break;
        }
        blank = reading.read(line);
      }
      if (end == length) {
        return span(from, length - from);
      }
    }
  }

  /// The last boundary before [before], or the start of the text.
  int _boundary(Layered<int> document, int before) {
    for (var size = seed; ; size *= 2) {
      final low = max(0, before - size);
      final text = covered(document, span(low, before - low));
      final positions = Positions(text);
      var end = text.lastIndexOf('\n');
      while (end >= 0) {
        final start = end == 0 ? -1 : text.lastIndexOf('\n', end - 1);
        if (start < 0 && low > 0) {
          break;
        }
        final at = low + positions[end + 1];
        final next = text.indexOf('\n', end + 1);
        if (at < before &&
            md.vacant(text, start + 1, end) &&
            !md.vacant(text, end + 1, next < 0 ? text.length : next) &&
            _clean(document, at)) {
          return at;
        }
        end = start;
      }
      if (low == 0 && end < 0) {
        return 0;
      }
    }
  }

  /// Whether a token starts at item [at] of the text and no block spans
  /// it. A token, since libara reads again only the tokens a region holds,
  /// and keeps one that crosses its end.
  bool _clean(Layered<int> document, int at) {
    if (at == 0 || at >= document.items.length) {
      return true;
    }
    final index = earliest(document, (token) => token.end > at);
    // Text past the last token was typed at the end, and no block spans it.
    final token = nth(document, index);
    if (token == null) {
      return true;
    }
    return token.start == at && document.crossing(3, index).isEmpty;
  }

  @override
  Result<Derivation<int>> edit(Layered<int> document, Edit<int> change) {
    final derived = restructure(const _Markdown(), document, change);
    final tabular = switch (change.command) {
      Mark(:final range) => const {
        'table',
        'tr',
        'td',
        'th',
      }.contains('${range.get('')}'),
      Delete() => true,
      _ => false,
    };
    if (derived case Success(:final value) when tabular) {
      return _ruled(
            document,
            change.layer,
            value.below,
            opened: switch (change.command) {
              Mark(:final range)
                  when range is Open && '${range.get('')}' == 'table' =>
                range.start,
              _ => null,
            },
          ) ??
          derived;
    }
    return derived;
  }

  /// What [change] makes of [document] where it leaves the markup as it
  /// stands.
  @override
  Result<Change<int>> valid(Layered<int> document, Edit<int> change) =>
      checked(document, change, 'markdown', tags: false);

  /// [text] as words alone, escaped where this syntax would read markup,
  /// and a bar, which would end a cell.
  @override
  List<int> escaped(List<int> text, {bool raw = false}) => escaping(
    text,
    (words) => _Writer._escaped(words).replaceAll('|', r'\|'),
    raw: raw,
  );

  @override
  Crossing crossing(Layered<int> document, int layer, ARange range) =>
      crossed(document, layer, range);
}

/// [document] with [below] made, the bar rows it touched written as rows
/// are and the ruling put under the first row of their table, as wide as
/// it: the edit at [layer] that writes that; or null where it touched no
/// table, or left nothing to put right.
///
/// The ruling is never asked for. It follows from the head, so a row or a
/// cell written or taken away anywhere in a table, in any order, leaves it
/// ruled as a fresh table would be. Rows with no ruling among them are bars
/// in a paragraph, and are ruled only when the table itself is opened, at
/// [opened].
Result<Derivation<int>>? _ruled(
  Layered<int> document,
  int layer,
  List<Edit<int>> below, {
  int? opened,
}) {
  var after = document;
  for (final edit in below) {
    switch (after.apply(edit)) {
      case Failure():
        return null;
      case Success(:final value):
        after = value.document;
    }
  }
  final old = document.items.items.toList();
  final now = after.items.items.toList();
  var head = 0;
  while (head < old.length && head < now.length && old[head] == now[head]) {
    head++;
  }
  var tail = 0;
  while (tail < old.length - head &&
      tail < now.length - head &&
      old[old.length - 1 - tail] == now[now.length - 1 - tail]) {
    tail++;
  }
  // A table opened writes nothing of its own, and touches where it opens.
  if (opened != null && head == old.length && old.length == now.length) {
    head = opened;
    tail = now.length - opened;
  }
  final lines = String.fromCharCodes(now).split('\n');
  final before = String.fromCharCodes(old).split('\n');
  // Each line's place in the text, and the lines the edit touched.
  final starts = <int>[];
  var at = 0;
  for (final line in lines) {
    starts.add(at);
    at += line.runes.length + 1;
  }
  bool touched(int index) =>
      starts[index] <= now.length - tail &&
      head <= starts[index] + lines[index].runes.length;
  bool barred(int index) => _bar.hasMatch(lines[index]);
  // The runs of bar lines, from first to last, the edit touched.
  final runs = <(int, int)>[];
  for (var index = 0; index < lines.length; index++) {
    if (!barred(index) || (index > 0 && barred(index - 1))) {
      continue;
    }
    var last = index;
    while (last + 1 < lines.length && barred(last + 1)) {
      last++;
    }
    if ([for (var one = index; one <= last; one++) one].any(touched)) {
      runs.add((index, last));
    }
  }
  if (runs.isEmpty) {
    return null;
  }
  final written = <int, List<String>>{};
  for (final (first, last) in runs) {
    final rows = [
      for (var index = first; index <= last; index++)
        if (_rowed(lines[index])) index,
    ];
    final ruled = [
      for (var index = first; index <= last; index++)
        if (_ruling.hasMatch(lines[index])) index,
    ].isNotEmpty;
    if (rows.isEmpty || !(ruled || opened != null)) {
      continue;
    }
    final kept = [
      for (var index = first; index <= last; index++)
        if (_ruling.hasMatch(lines[index])) lines[index],
    ].firstOrNull;
    // The head as it stood, where nothing before its line changed.
    final was = starts[rows.first] < head && rows.first < before.length
        ? before[rows.first]
        : null;
    for (var index = first; index <= last; index++) {
      final line = lines[index];
      if (_ruling.hasMatch(line)) {
        written[index] = const [];
        continue;
      }
      final row = rows.contains(index) && touched(index) ? _row(line) : line;
      written[index] = [row, if (index == rows.first) _ruler(row, kept, was)];
    }
  }
  if (written.isEmpty) {
    return null;
  }
  // From the first line written or touched to the last, the lines between
  // as they stand: the stretch begins before what the edit wrote, and ends
  // after it, so only its end moves.
  final touching = [
    for (var index = 0; index < lines.length; index++)
      if (touched(index)) index,
  ];
  final first = min(written.keys.reduce(min), touching.first);
  final last = max(written.keys.reduce(max), touching.last);
  final was = lines.sublist(first, last + 1).join('\n');
  final will = [
    for (var index = first; index <= last; index++)
      ...written[index] ?? [lines[index]],
  ].join('\n');
  if (was == will) {
    return null;
  }
  final start = starts[first];
  final end =
      starts[last] + lines[last].runes.length - (now.length - old.length);
  return rewritten(
    const _Markdown(),
    document,
    layer,
    span(start, end - start),
    will,
  );
}

/// The ruling under [head], a row of bars: [kept], the ruling the table
/// had, as it is written while it says as many cells as the head, since its
/// alignment is the author's; and otherwise given or relieved of a cell
/// where the head gained or lost one against [was], the head as it stood, a
/// cell given written as the one beside it without its alignment. Written
/// afresh where the table had none, or one this cannot read cell by cell.
String _ruler(String head, String? kept, String? was) {
  final prefix = _bar.firstMatch(head)![1];
  final count = _cells(head).length;
  final cells = kept == null || !kept.trimRight().endsWith('|')
      ? <String>[]
      : [..._cells(kept)];
  if (kept == null || cells.isEmpty || !_bar.hasMatch(kept)) {
    return '$prefix|${' --- |' * count}';
  }
  if (cells.length == count) {
    return kept;
  }
  final now = [for (final cell in _cells(head)) cell.trim()];
  final then = was == null
      ? null
      : [for (final cell in _cells(was)) cell.trim()];
  var at = min(count, cells.length);
  if (then != null && then.length - now.length == cells.length - count) {
    at = 0;
    while (at < now.length && at < then.length && now[at] == then[at]) {
      at++;
    }
  }
  while (cells.length < count) {
    final beside = cells[at == 0 ? 0 : at - 1];
    cells.insert(at.clamp(0, cells.length), beside.replaceAll(':', '-'));
  }
  while (cells.length > count) {
    cells.removeAt(at.clamp(0, cells.length - 1));
  }
  return '${_bar.firstMatch(kept)![1]}|${cells.join('|')}|';
}

/// A line that is a row of bars, or a ruling, with what holds it in.
final _bar = RegExp(r'^([ \t>]*)\|');

/// The ruling under a table's head.
final _ruling = RegExp(
  r'^[ \t>]*\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$',
);

/// Whether [line] is a whole row of bars: a cell or more between them, and
/// no ruling.
bool _rowed(String line) =>
    !_ruling.hasMatch(line) &&
    _bar.hasMatch(line) &&
    line.trimRight().endsWith('|') &&
    _cells(line).isNotEmpty;

/// The cells of [line], a row of bars, each as it is written.
List<String> _cells(String line) {
  final parts = line.trimRight().split(RegExp(r'(?<!\\)\|'));
  return parts.length < 3 ? const [] : parts.sublist(1, parts.length - 1);
}

/// [line], a row of bars, written as a row is: a space either side of
/// each cell's words.
String _row(String line) =>
    '${_bar.firstMatch(line)![1]}|'
    '${[for (final cell in _cells(line)) ' ${cell.trim()} |'].join()}';
