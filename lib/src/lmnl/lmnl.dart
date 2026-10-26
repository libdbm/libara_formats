import 'dart:math';

import 'package:libara/libara.dart';

import '../convert.dart';
import '../editing.dart';
import '../kinds.dart';
import '../lexing.dart';
import '../limits.dart';
import '../tags.dart';

part 'edits.dart';

/// LMNL, in sawtooth syntax: `[name}` opens a range and `{name]` closes it,
/// `[}` and `{]` do the same with no name, `[name]` is an empty range and
/// `{{name}}` an atom, and annotations stand inside a tag as
/// `[l [n}144{n]}`. A suffix, `[a=1}` and `{a=1]`, tells apart ranges of
/// one name that overlap.
///
/// Layer 2 holds one token per tag, atom, comment `[!-- --]` and escape
/// `\x`, and
/// one per run of text between them. A tag's name is under the empty key,
/// and each annotation is an attribute holding the text it was written as,
/// whatever ranges that text represents. An escape covers the backslash and the
/// character it escapes, with a `shows` attribute saying the character, so
/// that every token can be read from its own start. What does not scan is
/// a `#text` token with a diagnostic over it.
///
/// Layer 3 holds the elements. An end tag closes the latest open start tag
/// of its name and suffix, so ranges may overlap, which is what LMNL is
/// for. A tag that pairs with nothing is a diagnostic. Each element carries its
/// start tag's name and annotations, and those of its end tag the start tag
/// does not say. An empty range and an atom are each an element over its
/// one tag.
final class LMNL implements Format<Layered<int>, Sequence<int>> {
  /// The LMNL syntax, reading within [limits].
  const LMNL({this.limits = standard});

  /// What reading may build.
  final Limits limits;

  @override
  Result<Layered<int>> decode(Sequence<int> form) =>
      decoded('lmnl', _Grammar(limits), limits, form);

  /// [value]'s text, where it was read as LMNL, and otherwise its content
  /// with each element a range over it, which may overlap another; or a
  /// refusal where an element's name or an attribute's is one a tag cannot
  /// hold.
  @override
  Result<Sequence<int>> encode(Layered<int> value) =>
      value.grammar is _Grammar ? Success(value.items) : _written(value);
}

/// [document], read in another syntax, written as LMNL: at each token's
/// edge, the ranges ending there close, the last opened first, and then
/// those starting there open, the outermost first.
Result<Sequence<int>> _written(Layered<int> document) {
  final (:content, :offsets, :elements) = projected(document);
  final starting = <int, List<Placed>>{};
  for (final element in elements) {
    if (_unrepresentable(element.name, element.said) case final String why) {
      return Failure(Kind.invalid, 'lmnl: $why');
    }
    (starting[element.first] ??= []).add(element);
  }
  final written = StringBuffer();
  final open = <Placed>[];
  for (var edge = 0; edge < offsets.length; edge++) {
    if (edge > 0) {
      written.write(
        _escaped(content.substring(offsets[edge - 1], offsets[edge])),
      );
    }
    for (final element in open.reversed.toList()) {
      if (element.last == edge) {
        written.write('{${element.name}]');
        open.remove(element);
      }
    }
    for (final element in starting[edge] ?? const <Placed>[]) {
      written.write('[${element.name}');
      for (final MapEntry(:key, :value) in element.said.entries) {
        written.write(' [$key}${_escaped(value)}{$key]');
      }
      // An element holding no content is an empty range, one tag of its
      // own.
      if (offsets[element.last] == offsets[element.first]) {
        written.write(']');
      } else {
        written.write('}');
        open.add(element);
      }
    }
  }
  return Success(Text.of(written.toString()));
}

/// [words] with what LMNL reads as markup escaped.
String _escaped(String words) =>
    words.replaceAllMapped(RegExp(r'[\\\[\]{}]'), (match) => '\\${match[0]}');

final class _Grammar implements Grammar<int> {
  const _Grammar(this.limits);

  final Limits limits;

  @override
  int get depth => 3;

  @override
  Derived derive(Layered<int> document, int layer, Range region) {
    if (layer == 2) {
      return tokens(document, region, limits, _next);
    }
    final (elements, problems) = _pair(document, region);
    return (ranges: elements, diagnostics: problems);
  }

  /// At layer 2, as every syntax's tokens are read again. At layer 3, the
  /// change alone where it holds no tag and every element at its edges still
  /// opens and closes with tags of its own name that no other element of
  /// that name shares: pairing is by name, so an edit that touches no paired
  /// tag pairs nothing differently. Every token otherwise.
  @override
  Range affected(Layered<int> document, int layer, Range changed) {
    if (layer == 2) {
      return relexed(document, changed, _next);
    }
    Range whole() => span(0, document.layer(2).length);
    for (final (_, token) in document.span(2, changed)) {
      if (!'${token.get('')}'.startsWith('#')) {
        return whole();
      }
    }
    // A tag that paired with nothing and was taken away leaves its
    // diagnostic where it stood.
    for (final problem in document.diagnostics(3).items) {
      if (problem.start <= changed.end && changed.start <= problem.end) {
        return whole();
      }
    }
    final before = max(0, changed.start - 1);
    final after = changed.end + 1;
    final edges = {
      for (final (marker, element) in [
        ...document.crossing(3, before),
        ...document.crossing(3, after),
        ...document.within(3, span(before, after - before)),
      ])
        marker: element,
    }.values.toList();
    // An element whose own tag went collapses onto the nearest tag, which
    // may be one of its name; that one is another element's, since a tag
    // of its name inside it pairs within it, so two elements share it.
    final starts = <(Value?, int)>{};
    final ends = <(Value?, int)>{};
    for (final element in edges) {
      if (!_whole(document, element) ||
          !starts.add((element.get(''), element.start)) ||
          !ends.add((element.get(''), element.end))) {
        return whole();
      }
    }
    return changed;
  }

  @override
  Result<Derivation<int>> edit(Layered<int> document, Edit<int> change) =>
      _edit(document, change);

  /// Whether [element] still runs from a start tag of its name to an end
  /// tag of its name.
  static bool _whole(Layered<int> document, ARange element) {
    if (element.length < 2) {
      return false;
    }
    final first = document.span(2, span(element.start, 1));
    final last = document.span(2, span(element.end - 1, 1));
    if (first.isEmpty || last.isEmpty) {
      return false;
    }
    final name = element.get('');
    return first.single.$2.get('') == name &&
        last.single.$2.get('') == name &&
        document.items.item(first.single.$2.start) == _open &&
        document.items.item(last.single.$2.start) == _brace;
  }

  /// The elements [region]'s tokens pair into, each end tag closing the
  /// latest open start tag of its name, and a diagnostic for each tag that
  /// pairs with nothing, or where a limit is reached. A region holds every element any of its tokens belongs to,
  /// since libara widens it over the ranges that cross its ends.
  (List<ARange>, List<ARange>) _pair(Layered<int> document, Range region) {
    final tokens = document.span(2, region);
    final open = <String, List<(int, ARange)>>{};
    final elements = <ARange>[];
    final problems = <ARange>[];
    final most = limits.markers;
    final deepest = limits.depth;
    var standing = 0;
    for (var at = 0; at < tokens.length; at++) {
      final (_, token) = tokens[at];
      final name = '${token.get('')}';
      if (name.startsWith('#')) {
        continue;
      }
      final index = region.start + at;
      if (most != null && region.length + elements.length >= most) {
        return (
          elements,
          [limited(span(index, 1), 'more than $most tokens and elements')],
        );
      }
      final key = _key(document, token, name);
      final first = document.items.item(token.start);
      if (document.items.item(token.end - 1) == _square && first == _open ||
          first == _brace && document.items.item(token.start + 1) == _brace) {
        // An empty range or an atom: an element over its one tag.
        elements.add(ranged(index, 1, token.attributes));
      } else if (first == _open) {
        if (deepest != null && standing >= deepest) {
          return (
            elements,
            [limited(span(index, 1), 'ranges open deeper than $deepest')],
          );
        }
        (open[key] ??= []).add((index, token));
        standing++;
      } else if (open[key] case final held? when held.isNotEmpty) {
        final (start, tag) = held.removeLast();
        standing--;
        // What the end tag says is the element's too, where the start tag
        // does not say it first.
        elements.add(
          ranged(start, index - start + 1, {
            ...token.attributes,
            ...tag.attributes,
          }),
        );
      } else {
        problems.add(
          ranged(index, 1, {
            'message': literal('end tag {$key] closes nothing'),
          }),
        );
      }
    }
    for (final held in open.values) {
      for (final (index, tag) in held) {
        problems.add(
          ranged(index, 1, {
            'message': literal(
              'unclosed [${_key(document, tag, '${tag.get('')}')}}',
            ),
          }),
        );
      }
    }
    return (elements, problems);
  }

  /// What pairs [token], called [name]: its name, and the suffix after an
  /// `=` that tells apart overlapping ranges of one name, where it has one.
  static String _key(Layered<int> document, ARange token, String name) {
    var at = token.start + 1 + name.runes.length;
    if (at >= token.end || document.items.item(at) != _equals) {
      return name;
    }
    final suffix = StringBuffer();
    for (at += 1; at < token.end; at++) {
      final unit = document.items.item(at)!;
      if (_breaks(unit)) {
        break;
      }
      suffix.writeCharCode(unit);
    }
    return '$name=$suffix';
  }

  /// The token starting at [at] in [text].
  static Token _next(String text, int at) {
    final unit = text.codeUnitAt(at);
    if (unit == _backslash) {
      if (at + 1 >= text.length) {
        return (at + 1, prose, const {}, null);
      }
      final width = _surrogates(text, at + 1) ? 2 : 1;
      final end = at + 1 + width;
      return (
        end,
        '#escape',
        {'shows': literal(text.substring(at + 1, end))},
        null,
      );
    }
    if (text.startsWith('[!--', at)) {
      final close = text.indexOf('--]', at + 4);
      return close < 0
          ? (text.length, prose, const {}, 'unterminated comment')
          : (close + 3, '#comment', const {}, null);
    }
    if (text.startsWith('{{', at)) {
      return _atom(text, at);
    }
    if (unit == _open || unit == _brace) {
      return _tag(text, at);
    }
    // By hand, since an `indexOf` for a character the text does not hold
    // reads to its end, and doing that for every run makes a read
    // quadratic.
    var stop = at + 1;
    while (stop < text.length) {
      final next = text.codeUnitAt(stop);
      if (next == _open || next == _brace || next == _backslash) {
        break;
      }
      stop++;
    }
    return (stop, prose, const {}, null);
  }

  /// The tag opening at [at] in [text], read to the bracket that closes it.
  static Token _tag(String text, int at) {
    final (end, wrong) = _closing(text, at);
    if (wrong) {
      return (end + 1, prose, const {}, 'brackets facing the wrong way');
    }
    if (end < 0) {
      return (text.length, prose, const {}, 'unterminated tag');
    }
    final tag = text.substring(at, end + 1);
    final name = _name(tag);
    if (name.startsWith('#')) {
      return (end + 1, prose, const {}, 'a name cannot begin with #');
    }
    final (annotations, problem) = _annotations(tag);
    return (end + 1, name, annotations, problem);
  }

  /// The atom opening at [at] in [text], `{{name}}` with annotations as a
  /// start tag has them, read to the doubled brace that closes it.
  static Token _atom(String text, int at) {
    final opened = <int>[];
    for (var index = at + 2; index < text.length; index++) {
      final unit = text.codeUnitAt(index);
      if (unit == _backslash) {
        index++;
      } else if (unit == _open || unit == _brace) {
        opened.add(unit);
      } else if (unit == _shut && opened.isEmpty) {
        if (index + 1 >= text.length || text.codeUnitAt(index + 1) != _shut) {
          return (index + 1, prose, const {}, 'brackets facing the wrong way');
        }
        // Read as a tag from its inner brace, which is where a name and
        // annotations start.
        final tag = text.substring(at + 1, index + 1);
        final name = _name(tag);
        if (name.startsWith('#')) {
          return (index + 2, prose, const {}, 'a name cannot begin with #');
        }
        final (annotations, problem) = _annotations(tag);
        return (index + 2, name, annotations, problem);
      } else if (unit == _shut || unit == _square) {
        final wanted = unit == _shut ? _open : _brace;
        if (opened.isEmpty || opened.removeLast() != wanted) {
          return (index + 1, prose, const {}, 'brackets facing the wrong way');
        }
      }
    }
    return (text.length, prose, const {}, 'unterminated atom');
  }

  /// Where the tag opening at [from] closes, by matching the sawtooth
  /// brackets, `[` with `}` and `{` with `]`, so that annotations nest; and
  /// whether it stopped instead at a bracket closing the wrong kind. -1
  /// where nothing closes it.
  static (int, bool) _closing(String text, int from) {
    final opened = <int>[];
    for (var index = from; index < text.length; index++) {
      final unit = text.codeUnitAt(index);
      if (unit == _backslash) {
        index++;
      } else if (unit == _open || unit == _brace) {
        opened.add(unit);
      } else if (unit == _square &&
          opened.length == 1 &&
          opened.single == _open) {
        // A start bracket closed by an end one: an empty range.
        return (index, false);
      } else if (unit == _shut || unit == _square) {
        final wanted = unit == _shut ? _open : _brace;
        if (opened.isEmpty || opened.removeLast() != wanted) {
          return (index, true);
        }
        if (opened.isEmpty) {
          return (index, false);
        }
      }
    }
    return (-1, false);
  }

  /// The name of a tag: the run after its `[` or `{` up to a space, a
  /// bracket, or a delimiter another syntax's tag would read.
  static String _name(String tag) {
    var to = 1;
    while (to < tag.length && !_breaks(tag.codeUnitAt(to))) {
      to++;
    }
    return tag.substring(1, to);
  }

  /// The annotations of a start tag, each `[name}value{name]`, as
  /// attributes holding their values as written; and a problem where one
  /// has no name, which the empty key, the tag's own name, cannot hold.
  static (Map<String, Value>, String?) _annotations(String tag) {
    final found = <String, Value>{};
    String? problem;
    var at = 1;
    while (true) {
      final open = tag.indexOf('[', at);
      if (open < 0 || open >= tag.length - 1) {
        break;
      }
      var stop = open + 1;
      while (stop < tag.length && !_breaks(tag.codeUnitAt(stop))) {
        stop++;
      }
      final name = tag.substring(open + 1, stop);
      final brace = tag.indexOf('}', stop);
      if (brace < 0) {
        break;
      }
      final close = _ending(tag, '{$name]', brace + 1);
      if (close < 0) {
        at = brace + 1;
        continue;
      }
      if (name.isEmpty) {
        problem = 'an annotation with no name';
      } else {
        found[name] = literal(tag.substring(brace + 1, close));
      }
      at = close + name.length + 2;
    }
    return (found, problem);
  }

  /// Where [end] first stands in [tag] from [from], passing over what a
  /// backslash escapes, or -1.
  static int _ending(String tag, String end, int from) {
    for (var index = from; index < tag.length; index++) {
      if (tag.codeUnitAt(index) == _backslash) {
        index++;
      } else if (tag.startsWith(end, index)) {
        return index;
      }
    }
    return -1;
  }

  static bool _breaks(int unit) => const {
    0x20, 0x09, 0x0A, 0x0D, // whitespace
    _open, _brace, _shut, _square,
    0x3C, 0x3E, 0x22, 0x27, 0x2F, 0x3D, // < > " ' / =
  }.contains(unit);

  static bool _surrogates(String text, int at) =>
      at + 1 < text.length &&
      (text.codeUnitAt(at) & 0xFC00) == 0xD800 &&
      (text.codeUnitAt(at + 1) & 0xFC00) == 0xDC00;

  /// What [change] makes of [document] where it leaves the markup as it
  /// stands.
  @override
  Result<Change<int>> valid(Layered<int> document, Edit<int> change) =>
      checked(document, change, 'lmnl', tags: true);

  /// [text] as words alone, escaped where this syntax would read markup.
  @override
  List<int> escaped(List<int> text, {bool raw = false}) =>
      escaping(text, _escaped, raw: raw);

  @override
  Crossing crossing(Layered<int> document, int layer, ARange range) =>
      crossed(document, layer, range);
}

const _open = 0x5B; // [
const _brace = 0x7B; // {
const _shut = 0x7D; // }
const _square = 0x5D; // ]
const _backslash = 0x5C;
const _equals = 0x3D;
