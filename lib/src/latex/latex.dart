/// LaTeX: commands, environments, braces and dollars read as tokens over
/// the text, and the elements they represent, under HTML's names where HTML has
/// one.
///
/// Ported from markwrite's `latex.dart`. Nothing here runs TeX: no macro is
/// expanded, no counter kept and no package loaded. A command the tables do
/// not know is an element of its own name over its braced arguments, or an
/// escape showing nothing where it has none, so a paper round-trips byte for
/// byte. The preamble shows nothing but its title and author, and what
/// follows `\end{document}` shows nothing at all.
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
part 'scan.dart';
part 'write.dart';

/// LaTeX.
///
/// Layer 2 tiles the text: each command, brace and dollar that represents an
/// element is a token named for it, an escape or a command showing what it
/// shows, or nothing, an `#escape` saying so, a comment a `#comment`, and
/// the rest runs of `#text`. Layer 3 holds the elements, from the first
/// token of each to its last; a paragraph is a `p` saying `implied`,
/// with no tokens of its own.
final class LaTeX implements Format<Layered<int>, Sequence<int>> {
  /// LaTeX, reading within [limits].
  const LaTeX({this.limits = standard});

  /// What reading may build.
  final Limits limits;

  @override
  Result<Layered<int>> decode(Sequence<int> form) =>
      decoded('latex', _Grammar(limits), limits, form);

  /// [value]'s text, where it was read as LaTeX, and otherwise its
  /// content and elements as a LaTeX article.
  @override
  Result<Sequence<int>> encode(Layered<int> value) =>
      value.grammar is _Grammar ? Success(value.items) : _written(value);
}

/// What a stretch of text reads as, in UTF-16 units of it: its tokens and
/// elements, and where the reading stopped at a cap, with why.
typedef _Read = ({
  List<Found> tokens,
  List<Found> elements,
  (int, String)? stop,
});

final class _Grammar implements Grammar<int> {
  _Grammar(this.limits);

  final Limits limits;

  /// Whether a command has been defined as words in any version of the
  /// document, after which [_commands] looks for the definitions before a
  /// stretch. Only ever set, so it errs towards looking.
  bool _defined = false;

  /// The commands [document] defines as words before item [before], each
  /// as it last stands there.
  Map<String, String> _commands(Layered<int> document, int before) {
    if (!_defined || before == 0) {
      return const {};
    }
    return {
      for (final (_, token) in document.within(2, span(0, before)))
        if (token.get('command') case final Str name)
          '$name': '${token.get('value')}',
    };
  }

  /// What a definition of a command is written with.
  static final _commanding = RegExp(r'\\(?:re)?newcommand|\\providecommand');

  /// The text layer 2 last read, the container it stood in, and what it
  /// read as, which layer 3 reads next when the same stretch is asked of
  /// it. Taken once.
  (String, String?, _Read)? _last;

  @override
  int get depth => 3;

  @override
  Derived derive(Layered<int> document, int layer, Range region) =>
      layer == 2 ? _tokens(document, region) : _elements(document, region);

  /// Layer 2's tokens over [region].
  Derived _tokens(Layered<int> document, Range region) {
    final text = covered(document, region);
    final positions = Positions(text);
    final within = _within(document, region.start);
    final read = _read(text, within, _commands(document, region.start));
    _last = (text, within, read);
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

    final within = _within(document, from);
    final last = _last;
    _last = null;
    final read = last != null && last.$1 == text && last.$2 == within
        ? last.$3
        : _read(text, within, _commands(document, from));
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

  /// What [text] reads as, standing in the container [within].
  _Read _read(
    String text,
    String? within, [
    Map<String, String> commands = const {},
  ]) {
    final scan = _Scan(text, limits, within)
      ..commands = {...commands}
      ..read();
    if (scan.defined) {
      _defined = true;
    }
    final reach = scan.stop?.$1 ?? text.length;
    // The elements: each opening paired with the closing that ends it,
    // which the reading marks innermost first; a break is one token.
    final elements = <Found>[...scan.implied];
    final open = <_Event>[];
    for (final event in scan.tokens) {
      switch (event.kind) {
        case _Is.open when event.name == 'br' || event.name == 'img':
          elements.add((
            event.start,
            event.start + event.length,
            event.name,
            event.said,
          ));
        case _Is.open:
          open.add(event);
        case _Is.close:
          while (open.isNotEmpty) {
            final opened = open.removeLast();
            if (opened.name == event.name) {
              elements.add((
                opened.start,
                event.start + event.length,
                opened.name,
                opened.said,
              ));
              break;
            }
          }
        case _Is.shown || _Is.comment:
      }
    }
    final marks = [
      for (final event in scan.tokens)
        if (event.length > 0)
          (
            event.start,
            event.start + event.length,
            event.name,
            switch (event.kind) {
              _Is.open => event.said,
              _Is.shown => event.said,
              _ => const <String, String>{},
            },
          ),
    ];
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
    for (final (start, end, _, _) in elements) {
      cuts[min(start, reach)] = 1;
      cuts[min(end, reach)] = 1;
    }
    // A line a blank line stands before starts a token, unless markup
    // runs on over it, as the window finds it, so a stretch read alone
    // tiles as the whole does.
    var held = 0;
    for (var end = -1; end < reach;) {
      final next = text.indexOf('\n', end + 1);
      if (next >= 0 && next < reach && _vacant(text, end + 1, next)) {
        while (held < marks.length && marks[held].$2 <= next + 1) {
          held++;
        }
        if (held == marks.length || marks[held].$1 >= next + 1) {
          cuts[next + 1] = 1;
        }
      }
      if (next < 0) {
        break;
      }
      end = next;
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
    if (scan.stop case (final at, _) when at < text.length) {
      tokens.add((at, text.length, prose, const {}));
    }
    // Outermost first, as the structure reads two over the same tokens: a
    // block the reading implied holds what was written inside it, and of
    // two paired, the one that closed later opened first.
    final implied = scan.implied.length;
    final ordered = [...elements.indexed]
      ..sort(
        (one, other) => one.$2.$1 != other.$2.$1
            ? one.$2.$1.compareTo(other.$2.$1)
            : one.$2.$2 != other.$2.$2
            ? other.$2.$2.compareTo(one.$2.$2)
            : (one.$1 < implied) != (other.$1 < implied)
            ? (one.$1 < implied ? -1 : 1)
            : other.$1.compareTo(one.$1),
      );
    return (
      tokens: tokens,
      elements: [for (final (_, element) in ordered) element],
      stop: scan.stop,
    );
  }

  /// At layer 2, the [_window] of [changed]; at layer 3, the tokens of the
  /// window.
  @override
  Range affected(Layered<int> document, int layer, Range changed) {
    final whole = span(0, document.items.length);
    if (layer == 2) {
      final window = _window(document, changed);
      // A command defined, or its definition taken away, changes what
      // every use after it shows.
      if (window == null ||
          _commanding.hasMatch(covered(document, window)) ||
          document
              .within(2, window)
              .any((pair) => pair.$2.get('command') != null)) {
        return whole;
      }
      return window;
    }
    final from = nth(document, changed.start)?.start ?? document.items.length;
    final to = changed.length > 0 ? nth(document, changed.end - 1)!.end : from;
    final window = _window(document, span(from, to - from)) ?? whole;
    final first = earliest(document, (token) => token.end > window.start);
    final last = earliest(document, (token) => token.start >= window.end);
    return span(first, last - first);
  }

  /// The text to read again when [changed] items of it changed: from the
  /// last boundary before the change to the first past it where the new
  /// reading has nothing open but the container it stands in, each where a
  /// token starts; or null where the window would begin or end the document,
  /// which sets what every line after it reads.
  ///
  /// A boundary is a line a blank line stands before, where nothing spans
  /// but the document or its preamble: a blank line closes every paragraph
  /// and every group, so from there the text reads as the whole reads it,
  /// given the container it stands in, and [_read] starts a token there.
  Range? _window(Layered<int> document, Range changed) {
    final length = document.items.length;
    final from = _since(document, changed.start);
    final within = from == 0 ? null : _within(document, from);
    // What a preamble's words are is said by the document that ends it,
    // so where a window starts at the document's beginning, which nothing
    // spans, or in a preamble no document ends, the whole is read.
    final first = from == 0 ? null : document.span(3, span(0, 1)).firstOrNull;
    if (first != null &&
        '${first.$2.get('')}' == 'preamble' &&
        (within == null ||
            (within == 'preamble' &&
                '${nth(document, first.$2.end)?.get('')}' != 'document'))) {
      return null;
    }
    for (var size = changed.end - from + seed; ; size *= 2) {
      // The text is seen a little past the stretch, so a beginning of the
      // document that the stretch's end would cut short is seen whole.
      final end = min(from + size, length);
      final seen = min(end + r'\begin{document}'.length - 1, length);
      final text = covered(document, span(from, seen - from));
      if (text.contains(r'\begin{document}')) {
        return null;
      }
      // The document ending past a boundary leaves the window before it
      // reading as it does, so only an end the window would hold counts.
      final stop = text.indexOf(r'\end{document}');
      final positions = Positions(text);
      var at = 0;
      while (true) {
        final cut = text.indexOf('\n', at);
        if (cut < 0 || cut + 1 >= text.length) {
          break;
        }
        at = cut + 1;
        if (stop >= 0 && at > stop) {
          return null;
        }
        final place = from + positions[at];
        if (place >= end) {
          break;
        }
        if (place <= changed.end ||
            !_vacant(
              text,
              cut == 0 ? 0 : text.lastIndexOf('\n', cut - 1) + 1,
              cut,
            ) ||
            !_bounding(document, place) ||
            _within(document, place) != within) {
          continue;
        }
        final read = _Scan(text.substring(0, at), limits, within)..read();
        if (read.clean) {
          return span(from, place - from);
        }
      }
      if (stop >= 0) {
        return null;
      }
      if (end == length) {
        return within == null ? span(from, length - from) : null;
      }
    }
  }

  /// What a container's name is said to be where more than the document or
  /// its preamble spans a place.
  static const _outside = '#outside';

  /// The container that alone spans item [at] of the text: the document,
  /// its preamble, or nothing; or [_outside] where anything else spans it.
  String? _within(Layered<int> document, int at) {
    if (at == 0) {
      return null;
    }
    final index = earliest(document, (token) => token.end > at);
    final spanning = [
      for (final (_, element) in document.crossing(3, index))
        '${element.get('')}',
    ];
    if (spanning.isEmpty) {
      return null;
    }
    return spanning.length == 1 &&
            (spanning.single == 'document' || spanning.single == 'preamble')
        ? spanning.single
        : _outside;
  }

  /// Where the last boundary starts before [before], or the start of the
  /// text: strictly before, since a change at a boundary may take away what
  /// closed an element before it.
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
        final at = low + positions[end + 1];
        if (at < before &&
            _bounding(document, at) &&
            _vacant(text, start + 1, end) &&
            _within(document, at) != _outside) {
          return at;
        }
        end = start;
      }
      if (low == 0 && end < 0) {
        return 0;
      }
    }
  }

  /// Whether [text] from [at] to [end] holds nothing but spaces.
  static bool _vacant(String text, int at, int end) {
    for (var here = at; here < end; here++) {
      final unit = text.codeUnitAt(here);
      if (unit != 0x20 && unit != 0x09 && unit != 0x0D) {
        return false;
      }
    }
    return true;
  }

  /// Whether a token starts at item [at].
  bool _bounding(Layered<int> document, int at) {
    final token = nth(document, earliest(document, (token) => token.end > at));
    return token != null && token.start == at;
  }

  @override
  Result<Derivation<int>> edit(Layered<int> document, Edit<int> change) =>
      restructure(const _LaTeX(), document, change);

  /// What [change] makes of [document] where it leaves the markup as it
  /// stands.
  @override
  Result<Change<int>> valid(Layered<int> document, Edit<int> change) =>
      checked(document, change, 'latex', tags: false);

  /// [text] as words alone, escaped where this syntax would read markup.
  @override
  List<int> escaped(List<int> text, {bool raw = false}) =>
      escaping(text, _Writer._escaped, raw: raw);

  @override
  Crossing crossing(Layered<int> document, int layer, ARange range) =>
      crossed(document, layer, range);
}
