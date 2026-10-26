/// The roff family: requests and escapes read as tokens over the text, and
/// the elements they represent, under HTML's names where HTML has one.
///
/// Ported from markwrite's `roff.dart`. Nothing here interprets roff: no
/// register, string, macro definition, condition or diversion is
/// evaluated. A request the package's table does not know is a `#pi`
/// token showing nothing, as an instruction is in XML, so it round-trips
/// byte for byte. What a package knows is its table: which requests open
/// what.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:libara/libara.dart';

import '../convert.dart';
import '../editing.dart';
import '../lexing.dart';
import '../limits.dart';
import '../positions.dart';
import '../notation.dart';

part 'edits.dart';
part 'write.dart';
part 'glyphs.dart';
part 'man.dart';
part 'me.dart';
part 'ms.dart';
part 'scan.dart';

/// What a request does in the package a codec reads.
sealed class _Macro {
  const _Macro();
}

/// A block whose content is the rest of its line, or the next line where
/// the request has no arguments: a section heading.
final class _Lined extends _Macro {
  final String name;

  const _Lined(this.name);
}

/// A tbl table, from its request to `.TE`: its options and format are
/// syntax, and each line after them a row of cells.
final class _Table extends _Macro {
  const _Table();
}

/// A paragraph running on to the next block request.
final class _Paragraph extends _Macro {
  final String name;

  const _Paragraph([this.name = 'p']);
}

/// A heading whose rank is the request's first argument, a number or a
/// step from the last, and whose words are the rest of the line where
/// [inline], else the lines that follow.
final class _Headed extends _Macro {
  final int? level;
  final bool inline;

  const _Headed({this.level, this.inline = false});
}

/// A tagged paragraph: the next line is the tag, and the lines after it the
/// paragraph hanging under it.
final class _Tagged extends _Macro {
  const _Tagged();
}

/// An item: a paragraph with a marker taken from the request's first
/// argument, where it has one, else [tag].
final class _Item extends _Macro {
  final String? tag;

  const _Item({this.tag});
}

/// A request whose lines through the request [until] are read as nothing:
/// an index entry.
final class _Ignored extends _Macro {
  final String until;

  const _Ignored(this.until);
}

/// Opens a container that its partner closes: an indent, a preformatted
/// block, a link.
final class _Opening extends _Macro {
  final String name;

  /// An attribute the element takes from the request's first argument, and
  /// what goes before it.
  final String? attribute;
  final String prefix;

  /// A class the element carries.
  final String? kind;

  /// What else the element says of itself, as attributes.
  final Map<String, String> said;

  /// Whether the lines inside are content as they stand, no paragraph
  /// opened for them.
  final bool verbatim;

  const _Opening(
    this.name, {
    this.attribute,
    this.prefix = '',
    this.kind,
    this.said = const {},
    this.verbatim = false,
  });
}

/// An equation, as every package represents one: a block that eqn reads,
/// carrying its label where it has one.
const _Opening _equation = _Opening(
  'equation',
  attribute: 'id',
  said: {'notation': 'eqn'},
  verbatim: true,
);

/// Closes the container its partner opened.
final class _Closing extends _Macro {
  final String name;

  const _Closing(this.name);
}

/// Sets the rest of the line in the faces named, innermost last.
final class _Font extends _Macro {
  final List<String> names;

  const _Font(this.names);
}

/// Sets the arguments alternately in two faces, with nothing between them.
final class _Alternating extends _Macro {
  final String first;
  final String second;

  const _Alternating(this.first, this.second);
}

/// One element that is the request line itself, its arguments carried as
/// the attributes named, in order.
final class _Titled extends _Macro {
  final String name;
  final List<String> attributes;

  const _Titled(this.name, this.attributes);
}

/// A line break where the request stands.
final class _Breaking extends _Macro {
  /// The element the request is read as: `br` for a line broken bodily,
  /// `bp` for a page begun, which a sheet breaks the page before and which
  /// is a page break and nothing more, since roff has no sections.
  final String name;

  const _Breaking([this.name = 'br']);
}

/// A request that is syntax and shows nothing, said so rather than left to
/// the table's silence.
final class _Hidden extends _Macro {
  const _Hidden();
}

/// What a stretch of text reads as, in UTF-16 units of it: its tokens and
/// elements, whether it holds a delim line, and where the reading stopped
/// at a cap, with why.
typedef _Read = ({
  List<Found> tokens,
  List<Found> elements,
  bool delimited,
  bool defined,
  (int, String)? stop,
});

/// The grammar every roff package shares, over the package's [macros].
///
/// Layer 2 tiles the text: each request line, escape, and quote that is
/// syntax is a token, named for the element it represents, or `#pi` for a
/// request that shows nothing, `#comment` for a comment, and `#escape`,
/// saying what it `shows`, for an escape; the rest is runs of `#text`.
/// Layer 3 holds the elements, from the first token of each to its
/// last; a paragraph no request opened is `p` saying `implied`, with no
/// tokens of its own.
final class _Grammar implements Grammar<int> {
  _Grammar(this.syntax, this.macros, this.notations, this.limits);

  /// The package's name.
  final String syntax;

  final Map<String, _Macro> macros;

  /// How the package represents its elements, for its structural edits.
  final Map<String, (String, String)> notations;
  final Limits limits;

  /// Whether a delim line has been read in any version of the document,
  /// after which [_delimits] asks the version edited whether it still
  /// holds one. Only ever set, so it errs towards asking.
  bool _delimited = false;

  /// Whether [document] sets eqn's delimiters, after which every line may
  /// hold a formula, so the whole text is read again for every edit.
  bool _delimits(Layered<int> document) =>
      _delimited &&
      document
          .layer(2)
          .items
          .any((token) => (token as ARange).get('delim') != null);

  /// Whether a string has been defined in any version of the document,
  /// after which [_strings] looks for the definitions before a stretch.
  /// Only ever set, so it errs towards looking.
  bool _defined = false;

  /// The strings [document] defines before item [before], each as it last
  /// stands there.
  Map<String, String> _strings(Layered<int> document, int before) {
    if (!_defined || before == 0) {
      return const {};
    }
    return {
      for (final (_, token) in document.within(2, span(0, before)))
        if (token.get('string') case final Str name)
          '$name': '${token.get('value')}',
    };
  }

  /// The text layer 2 last read and what it read as, which layer 3 reads
  /// next when the same stretch is asked of it. Taken once.
  (String, _Read)? _last;

  @override
  int get depth => 3;

  @override
  Derived derive(Layered<int> document, int layer, Range region) =>
      layer == 2 ? _tokens(document, region) : _elements(document, region);

  /// Layer 2's tokens over [region].
  Derived _tokens(Layered<int> document, Range region) {
    final text = covered(document, region);
    final positions = Positions(text);
    final read = _read(text, _strings(document, region.start));
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
  Derived _elements(Layered<int> document, Range region) {
    final held = [for (final (_, token) in document.span(2, region)) token];
    if (held.isEmpty) {
      return (ranges: const [], diagnostics: const []);
    }
    final from = held.first.start;
    final text = covered(document, span(from, held.last.end - from));
    final positions = Positions(text);
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
        : _read(text, _strings(document, from));
    return (
      ranges: [
        for (final (start, end, name, said) in read.elements)
          if (index(from + positions[start]) case final first)
            ARange.from(span(first, index(from + positions[end]) - first), {
              '': literal(name),
              for (final MapEntry(:key, :value) in said.entries)
                key: literal(value),
            }),
      ],
      diagnostics: const [],
    );
  }

  /// What [text] reads as, the strings defined before it being [strings].
  _Read _read(String text, [Map<String, String> strings = const {}]) {
    final scan = _Scan(text, macros, limits)
      ..strings = {...strings}
      ..read();
    if (scan.defined) {
      _defined = true;
    }
    if (scan.delimited) {
      _delimited = true;
    }
    final reach = scan.stop?.$1 ?? text.length;
    // The scanner marks in the order of the text all but where a block
    // closes behind it, so they are sorted only where they need it; and
    // where tokens are cut is flagged over the text rather than sorted.
    final marks = scan.marks;
    for (var at = 1; at < marks.length; at++) {
      if (marks[at].$1 < marks[at - 1].$1) {
        marks.sort((one, other) => one.$1.compareTo(other.$1));
        break;
      }
    }
    final cuts = Uint8List(reach + 1)..[reach] = 1;
    for (final (start, end, _, _) in marks) {
      cuts[min(start, reach)] = 1;
      cuts[min(end, reach)] = 1;
    }
    for (final (start, end, _, _) in scan.elements) {
      cuts[min(start, reach)] = 1;
      cuts[min(end, reach)] = 1;
    }
    final tokens = <Found>[];
    var mark = 0;
    var from = 0;
    for (var to = 1; to <= reach; to++) {
      if (cuts[to] == 0) {
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
    var stop = scan.stop;
    final most = limits.markers;
    if (most != null && tokens.length > most) {
      final at = tokens[most - 1].$1;
      tokens.length = most - 1;
      stop = (at, 'more than $most tokens');
    }
    if (stop case (final at, _) when at < text.length) {
      tokens.add((at, text.length, prose, const {}));
    }
    // Outermost first: of two over the same tokens, the one that closed
    // later opened first, and holds the other.
    final closed = [...scan.elements.indexed]
      ..sort(
        (one, other) => one.$2.$1 != other.$2.$1
            ? one.$2.$1.compareTo(other.$2.$1)
            : one.$2.$2 != other.$2.$2
            ? other.$2.$2.compareTo(one.$2.$2)
            : other.$1.compareTo(one.$1),
      );
    return (
      tokens: tokens,
      elements: [for (final (_, element) in closed) element],
      delimited: scan.delimited,
      defined: scan.defined,
      stop: stop,
    );
  }

  /// At layer 2, the [_window] of [changed], or the whole text where eqn's
  /// delimiters are set or the window sets or unsets them. At layer 3, the
  /// tokens of the window.
  @override
  Range affected(Layered<int> document, int layer, Range changed) {
    final whole = span(0, document.items.length);
    if (layer == 2) {
      if (_delimits(document)) {
        return whole;
      }
      final window = _window(document, changed);
      final read = window == null ? null : _read(covered(document, window));
      if (window == null ||
          read!.delimited ||
          read.defined ||
          document
              .within(2, window)
              .any(
                (pair) =>
                    pair.$2.get('delim') != null ||
                    pair.$2.get('string') != null,
              )) {
        _delimited = _delimited || window != null;
        return whole;
      }
      return window;
    }
    final from = nth(document, changed.start)?.start ?? document.items.length;
    final to = changed.length > 0 ? nth(document, changed.end - 1)!.end : from;
    final window = _delimits(document)
        ? whole
        : _window(document, span(from, to - from)) ?? whole;
    final first = earliest(document, (token) => token.end > window.start);
    final last = earliest(document, (token) => token.start >= window.end);
    return span(first, last - first);
  }

  /// The text to read again when [changed] items of it changed: from the
  /// last boundary at or before the change to the first past it that still
  /// reads as one and that the text before the edit and after it reach
  /// with the same face for `\fP` to bring back; or null where the window
  /// reaches for what stood before it, a face `\fP` brings back or a
  /// heading ranked as a step from the last.
  ///
  /// A boundary is a paragraph request or a heading that no element spans:
  /// it closes every paragraph and every face, so with no container open
  /// what is read from it is read as the whole text reads it, save the face
  /// `\fP` brings back, which nothing closes, and the rank a stepped
  /// heading counts from.
  Range? _window(Layered<int> document, Range changed) {
    final window = _stretch(document, changed);
    // A face brought back that stood before the window is read only by
    // reading from before it.
    final read = _Scan(covered(document, window), macros, limits)
      ..previous = _before
      ..read();
    return read.marks.any((mark) => mark.$3 == _before.single) ||
            read.elements.any((element) => element.$3 == _before.single)
        ? null
        : window;
  }

  /// The [_window] of [changed], before what it reaches for is asked.
  Range _stretch(Layered<int> document, Range changed) {
    final length = document.items.length;
    final from = _since(document, changed.start);
    for (var size = changed.end - from + seed; ; size *= 2) {
      final end = min(from + size, length);
      final text = covered(document, span(from, end - from));
      final positions = Positions(text);
      if (_stepped.hasMatch(text)) {
        return span(0, length);
      }
      // A reading of the stretch from its start says, for each line it
      // reaches, what stood open before it and whether a boundary's token
      // starts it: what a reading up to the line, and one through it, would
      // say. It reads twice as far each time a line lies past it, so the
      // whole costs about what reading to the boundary found does.
      var states = <int, ({bool contained, List<String> previous})>{};
      var heads = <int>{};
      var reach = 0;
      void reading(int limit) {
        final found = <int, ({bool contained, List<String> previous})>{};
        final read = _Scan(text.substring(0, limit), macros, limits)
          ..previous = _before;
        read.line = (at) => found[at] = (
          contained: read.blocks.any((block) => !block.running),
          previous: read.previous,
        );
        read.read();
        states = found;
        heads = {
          for (final mark in read.marks)
            if (_bounds.hasMatch(mark.$3)) mark.$1,
        };
        reach = limit;
      }

      var at = 0;
      while (true) {
        final cut = text.indexOf('\n', at);
        if (cut < 0 || cut + 1 >= text.length) {
          break;
        }
        at = cut + 1;
        final place = from + positions[at];
        if (place <= changed.end || !_bounding(document, place)) {
          continue;
        }
        final line = text.indexOf('\n', at);
        if (line < 0 && end < length) {
          break;
        }
        final through = line < 0 ? text.length : line + 1;
        if (through > reach) {
          reading(min(text.length, max(through, reach * 2)));
        }
        final before = states[at];
        if (before != null &&
            heads.contains(at) &&
            !before.contained &&
            !_stepped.hasMatch(text.substring(at, through)) &&
            _same(before.previous, _stood(document, from, place))) {
          return span(from, place - from);
        }
      }
      if (end == length) {
        return span(from, length - from);
      }
    }
  }

  /// What a boundary's token is called: a paragraph, a heading, or a
  /// page's title.
  static final _bounds = RegExp(r'^(p|h[1-6]|head)$');

  /// A heading whose rank is a step from the last, which reaches back
  /// before the window.
  static final _stepped = RegExp(r"^[.']\s*(sh|NH)\s+[+-]", multiLine: true);

  /// What a reading starts with as the face `\fP` brings back: whatever
  /// stood before the stretch read, said so that a stretch that changes no
  /// face comes out saying it too.
  static const _before = ['\u0000'];

  /// The face `\fP` would bring back at the heading at item [at], as the
  /// text before the edit read it from item [from]; or null where the
  /// version before the edit is not to hand.
  List<String>? _stood(Layered<int> document, int from, int at) {
    final previous = document.previous;
    final edits = document.changes;
    final delta =
        previous == null || edits.length != 1 || edits.single.layer != 1
        ? null
        : switch (edits.single.command) {
            Insert(:final items) => items.length,
            Delete(span: final gone) => -gone.length,
            Replace(span: final gone, :final items) =>
              items.length - gone.length,
            _ => null,
          };
    if (delta == null) {
      return null;
    }
    final to = at - delta;
    if (to > previous!.items.length) {
      return null;
    }
    return (_Scan(covered(previous, span(from, to - from)), macros, limits)
          ..previous = _before
          ..read())
        .previous;
  }

  static bool _same(List<String> one, List<String>? other) =>
      other != null && one.join('\n') == other.join('\n');

  /// Where the last boundary starts at or before [before], or the start of
  /// the text.
  int _since(Layered<int> document, int before) {
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
        final at = low + positions[start + 1];
        if (_bounding(document, at)) {
          return at;
        }
        end = start;
      }
      if (low == 0 && end < 0) {
        return 0;
      }
    }
  }

  /// Whether a boundary starts at item [at]: a paragraph's or a heading's
  /// token that no element spans.
  bool _bounding(Layered<int> document, int at) {
    final index = earliest(document, (token) => token.end > at);
    final token = nth(document, index);
    return token != null &&
        token.start == at &&
        _bounds.hasMatch('${token.get('')}') &&
        document.crossing(3, index).isEmpty;
  }

  @override
  Result<Derivation<int>> edit(Layered<int> document, Edit<int> change) =>
      restructure(_Roff(syntax, notations), document, change);

  /// What [change] makes of [document] where it leaves the markup as it
  /// stands.
  @override
  Result<Change<int>> valid(Layered<int> document, Edit<int> change) =>
      checked(document, change, syntax, tags: false);

  /// [text] as words alone, escaped where this syntax would read markup.
  @override
  List<int> escaped(List<int> text, {bool raw = false}) => escaping(
    text,
    (_Writer(syntax, notations, '').._tail = ' ')._escaped,
    raw: raw,
  );

  @override
  Crossing crossing(Layered<int> document, int layer, ARange range) =>
      crossed(document, layer, range);
}

/// [form] read as the roff package [syntax], whose requests are [macros]
/// and which represents its elements as [notations] say.
Result<Layered<int>> _decoded(
  String syntax,
  Map<String, _Macro> macros,
  Map<String, (String, String)> notations,
  Limits limits,
  Sequence<int> form,
) => decoded(syntax, _Grammar(syntax, macros, notations, limits), limits, form);

/// [value]'s text, where it was read as the roff package [syntax], and
/// otherwise its content and elements as the package represents them, which
/// [notations] says.
Result<Sequence<int>> _encoded(
  String syntax,
  Map<String, (String, String)> notations,
  Layered<int> value,
) => switch (value.grammar) {
  _Grammar(syntax: final read) when read == syntax => Success(value.items),
  _ => _written(syntax, notations, value),
};
