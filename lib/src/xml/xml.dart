import 'dart:math';

import 'package:libara/libara.dart';

import '../convert.dart';
import '../editing.dart';
import '../entities.dart';
import '../kinds.dart';
import '../lexing.dart';
import '../limits.dart';
import '../tags.dart';
import '../tags.dart' as tags show escaped;

part 'edits.dart';

/// XML, as a lossless scanner for markwrite's documented subset rather
/// than a validating processor.
///
/// Layer 2 holds one token per tag, comment, processing instruction,
/// declaration, CDATA section and entity reference, and one per run of text
/// between them, so it covers the whole text. A tag's name is under the
/// empty key, and its attributes under their own names, each holding what
/// its value says. The other tokens take the DOM's names: `#text`,
/// `#comment`, `#pi`, `#doctype`, `#declaration`, `#cdata` and `#entity`, the
/// last two with a `shows` attribute saying what they stand for. What does
/// not scan is a `#text` token with a diagnostic over it.
///
/// Layer 3 holds the elements, each over the tokens from its start tag to
/// its end tag, or its one empty tag, carrying the start tag's name and
/// attributes. The document itself is not a range: it is the whole of the
/// layer, and nothing stored could say that better than the layer does. A
/// tag that does not pair is a diagnostic and opens or closes nothing.
///
/// Reading stops where it reaches one of [limits]: a text longer than
/// `items` is refused before it is read, and more tokens and diagnostics
/// than `markers`, more elements, elements nested deeper than `depth`, or a
/// tag saying more than `attributes` refuse it as they are found. An edit
/// past a cap leaves a diagnostic saying so.
final class XML implements Format<Layered<int>, Sequence<int>> {
  /// The XML syntax, reading within [limits].
  const XML({this.limits = standard});

  /// What reading may build.
  final Limits limits;

  @override
  Result<Layered<int>> decode(Sequence<int> form) =>
      decoded('xml', _Grammar(limits), limits, form);

  /// [value]'s text, where it was read as XML, and otherwise its content
  /// in its elements, which must nest.
  @override
  Result<Sequence<int>> encode(Layered<int> value) => value.grammar is _Grammar
      ? Success(value.items)
      : tree(value, 'xml', empty: (_) => '/>');
}

/// How the diagnostic for a start tag that never closes begins.
const _unclosed = 'unclosed ';

enum _Role { start, end, empty }

final class _Grammar implements Grammar<int> {
  const _Grammar(this.limits);

  final Limits limits;

  @override
  int get depth => 3;

  @override
  Derived derive(Layered<int> document, int layer, Range region) => layer == 2
      ? tokens(document, region, limits, _next)
      : _elements(document, region);

  /// At layer 2, from the token holding the item before the change, or the
  /// run of text before that one, which a reference the change breaks
  /// joins, to the first place past the change where an unchanged token
  /// starts: every token is scanned from its own start without looking
  /// back, so from there on the scan reads what it read before.
  ///
  /// The scan looks ahead through a window that doubles until a token ends
  /// short of it, since a token cut off by the window's end, such as a
  /// comment that closes past it, is not yet the token it will be.
  /// At layer 3, the innermost element strictly around the changed tokens
  /// that, paired on its own, is still the element it was: its tags stand
  /// on the stack from its start to its end, so what it holds pairs the
  /// same within it as within the whole. Every token where none is.
  @override
  Range affected(Layered<int> document, int layer, Range changed) => layer == 2
      ? relexed(document, changed, _next)
      : _element(document, changed);

  @override
  Result<Derivation<int>> edit(Layered<int> document, Edit<int> change) =>
      _edit(document, change);

  Range _element(Layered<int> document, Range changed) {
    final around = [
      for (final (_, element) in document.crossing(3, changed.start))
        if (changed.end < element.end) element,
    ]..sort((one, other) => one.length - other.length);
    for (final element in around) {
      final (found, _) = _pair(document, element);
      if (found.any(
        (range) =>
            range.start == element.start && range.length == element.length,
      )) {
        return element;
      }
    }
    return span(0, document.layer(2).length);
  }

  /// The elements over [region] of layer 2's tokens, and the tags that do
  /// not pair.
  Derived _elements(Layered<int> document, Range region) {
    final (elements, problems) = _pair(document, region);
    return (ranges: elements, diagnostics: problems);
  }

  /// The elements [region]'s tokens pair into, and the tags that do not,
  /// paired from what stands open where [region] starts, or, where not
  /// [seeded], from nothing, to ask whether [region] pairs on its own.
  ///
  /// Pairing stops at a tag that would nest deeper than the limit, or where
  /// the tokens, elements and diagnostics would be more marked ranges than
  /// it allows.
  (List<ARange>, List<ARange>) _pair(
    Layered<int> document,
    Range region, {
    bool seeded = true,
  }) {
    final tokens = document.span(2, region);
    final open = seeded ? _standing(document, region.start) : <(int, ARange)>[];
    final elements = <ARange>[];
    final problems = <ARange>[];
    final most = limits.markers;
    final deepest = limits.depth;
    for (var at = 0; at < tokens.length; at++) {
      final (_, token) = tokens[at];
      final name = '${token.get('')}';
      if (name.startsWith('#')) {
        continue;
      }
      final index = region.start + at;
      if (most != null &&
          region.length + elements.length + problems.length >= most) {
        problems.add(
          limited(span(index, 1), 'more than $most tokens and elements'),
        );
        return (elements, problems);
      }
      switch (_role(document, token)) {
        case _Role.empty:
          elements.add(ranged(index, 1, token.attributes));
        case _Role.start when deepest != null && open.length >= deepest:
          problems.add(
            limited(span(index, 1), 'elements nested deeper than $deepest'),
          );
          return (elements, problems);
        case _Role.start:
          open.add((index, token));
        case _Role.end:
          if (open.isNotEmpty && '${open.last.$2.get('')}' == name) {
            final (start, tag) = open.removeLast();
            elements.add(ranged(start, index - start + 1, tag.attributes));
          } else {
            final held = open.isEmpty ? 'nothing' : '${open.last.$2.get('')}';
            problems.add(
              ranged(index, 1, {'message': literal('</$name> closes $held')}),
            );
          }
      }
    }
    for (final (index, tag) in open) {
      if (index >= region.start) {
        problems.add(
          ranged(index, 1, {'message': literal('$_unclosed<${tag.get('')}>')}),
        );
      }
    }
    return (elements, problems);
  }

  /// The tags standing open just before token [index], outermost first:
  /// the elements around it, and the start tags before it that never
  /// close, which stay open to the end. Neither can stand inside the other,
  /// since an element holding a tag that never closes would not have
  /// closed, so their order is their tokens' order.
  static List<(int, ARange)> _standing(Layered<int> document, int index) {
    if (index == 0) {
      return [];
    }
    return [
      for (final (_, element) in document.crossing(3, index))
        (element.start, element),
      for (final problem in document.diagnostics(3).items)
        if (problem.start < index &&
            '${(problem as ARange).get('message')}'.startsWith(_unclosed))
          (problem.start, document.span(2, problem).single.$2),
    ]..sort((one, other) => one.$1 - other.$1);
  }

  /// Whether [tag] opens, closes, or is a whole element, read off the text
  /// it covers rather than stored.
  static _Role _role(Layered<int> document, ARange tag) {
    final items = document.items;
    if (items.item(tag.start + 1) == 0x2F) {
      return _Role.end;
    }
    return items.item(tag.end - 2) == 0x2F ? _Role.empty : _Role.start;
  }

  /// What [change] makes of [document] where it leaves the markup as it
  /// stands.
  @override
  Result<Change<int>> valid(Layered<int> document, Edit<int> change) =>
      checked(document, change, 'xml', tags: true);

  /// [text] as words alone, escaped where this syntax would read markup.
  @override
  List<int> escaped(List<int> text, {bool raw = false}) =>
      escaping(text, tags.escaped, raw: raw);

  @override
  Crossing crossing(Layered<int> document, int layer, ARange range) =>
      crossed(document, layer, range);
}

/// The token starting at [at] in [text].
Token _next(String text, int at) {
  if (text.codeUnitAt(at) == 0x3C) {
    return _markup(text, at);
  }
  for (final (start, end, shows) in references(
    text,
    at,
    min(text.length, at + longest + 2),
  )) {
    if (start == at) {
      return (end, '#entity', {'shows': literal(shows)}, null);
    }
    break;
  }
  final mark = found(text, 0x3C, at, text.length);
  final stop = mark < 0 ? text.length : mark;
  for (final (start, _, _) in references(text, at, stop)) {
    return (start, prose, const {}, null);
  }
  return (stop, prose, const {}, null);
}

/// The tag or construct opening with the `<` at [at] in [text].
Token _markup(String text, int at) {
  if (text.startsWith('<?', at) || text.startsWith('<!', at)) {
    final past = skipped(text, at);
    if (past < 0) {
      return (text.length, prose, const {}, 'unterminated ${_kind(text, at)}');
    }
    final (name, shows) = saying(text, at, past);
    return (
      past,
      name,
      name == '#cdata' ? {'shows': literal(shows)} : const {},
      null,
    );
  }
  final close = closing(text, at);
  if (close < 0) {
    return (text.length, prose, const {}, 'unterminated tag');
  }
  final tag = text.substring(at, close + 1);
  final name = called(tag);
  if (name.isEmpty) {
    return (close + 1, prose, const {}, 'tag with no name');
  }
  if (tag.startsWith('</')) {
    return (close + 1, name, const {}, null);
  }
  String? problem;
  final attributes = <String, Value>{};
  for (final (key, written) in pairs(tag)) {
    if (key.isEmpty) {
      problem = 'attribute with no name';
    } else {
      attributes[key] = literal(resolved(written));
    }
  }
  return (close + 1, name, attributes, problem);
}

/// What the construct opening at [at] is called, for a diagnostic to name.
String _kind(String text, int at) {
  if (text.startsWith('<!--', at)) {
    return 'comment';
  }
  if (text.startsWith('<![CDATA[', at)) {
    return 'character section';
  }
  if (text.startsWith('<?', at)) {
    return 'processing instruction';
  }
  return 'declaration';
}
