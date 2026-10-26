/// What every syntax's layer 2 shares: a scanner reads one token from where
/// it starts, without looking back, and from that follow how a region is
/// read into tokens and how far an edit's region reaches.
library;

import 'dart:math';

import 'package:libara/libara.dart';

import 'limits.dart';
import 'positions.dart';

/// One token as a scanner reads it: where it ends, in UTF-16 units of the
/// text being scanned, what it is called, what it says, and what is wrong
/// with it, if anything.
typedef Token = (
  int end,
  String name,
  Map<String, Value> attributes,
  String? problem,
);

/// Reads the token starting at [at] in [text].
typedef Scanner = Token Function(String text, int at);

/// The name of a run of text.
const prose = '#text';

/// How much text past an edit is first read for where the tokens it
/// touched settle, or for the line it stands on, before the stretch is
/// doubled: more than most tokens and lines run to.
const glimpse = 256;

/// How much text past an edit a grammar read by lines first reads for a
/// boundary, before the stretch is doubled: more than most paragraphs run
/// to.
const seed = 1024;

/// Markup or an element as a scanner finds it: where it starts and
/// ends in the text read, what it is called, and what it says.
typedef Found = (int, int, String, Map<String, String>);

/// [text] as an attribute value.
Str literal(String text) => Str(Text.of(text));

/// [attributes] as text, the name left out.
Map<String, String> stated(Map<String, Value> attributes) => {
  for (final MapEntry(:key, :value) in attributes.entries)
    if (key.isNotEmpty) key: '$value',
};

/// The range from [start] of [length], which a syntax only ever asks for
/// within the text it has.
Range span(int start, int length) => switch (Range.create(start, length)) {
  Success(:final value) => value,
  Failure(:final message) => throw StateError(message),
};

/// Layer 2's token at [index], if there is one.
ARange? nth(Layered<int> document, int index) =>
    document.span(2, span(index, 1)).firstOrNull?.$2;

/// The index of the first token of layer 2 that [test] holds for, where it
/// holds for every token after one it holds for, or the count of tokens.
int earliest(Layered<int> document, bool Function(ARange) test) {
  // No token is empty, so there are no more of them than items.
  var (low, high) = (0, document.items.length);
  while (low < high) {
    final middle = (low + high) ~/ 2;
    final token = nth(document, middle);
    if (token == null || test(token)) {
      high = middle;
    } else {
      low = middle + 1;
    }
  }
  return low;
}

/// Whether [token] is a run of text.
bool texted(ARange token) => token.get('') == literal(prose);

/// The range from [start] of [length] saying [attributes].
ARange ranged(int start, int length, Map<String, Value> attributes) =>
    ARange.from(span(start, length), attributes);

/// The tokens [next] reads over [region] of [document]'s text, and the
/// diagnostics for those that do not scan, within [limits]: past `markers`
/// the rest of the region is one run of text, and a token saying more than
/// `attributes` is one too, each under a diagnostic that refuses the read.
Derived tokens(
  Layered<int> document,
  Range region,
  Limits limits,
  Scanner next,
) {
  final text = String.fromCharCodes(document.slice(region).items);
  final positions = Positions(text);
  final ranges = <ARange>[];
  final diagnostics = <ARange>[];
  final most = limits.markers;
  final widest = limits.attributes;
  // A name is said by every token that has it, so it is made once.
  final names = <String, Str>{};
  Str called(String name) => names[name] ??= literal(name);
  var unit = 0;
  while (unit < text.length) {
    final start = region.start + positions[unit];
    if (most != null && ranges.length + diagnostics.length >= most) {
      final rest = span(start, region.end - start);
      ranges.add(ARange.from(rest, {'': called(prose)}));
      diagnostics.add(limited(rest, 'more than $most tokens'));
      break;
    }
    final (end, name, attributes, problem) = next(text, unit);
    final length = positions[end] - positions[unit];
    if (widest != null && attributes.length > widest) {
      ranges.add(ranged(start, length, {'': called(prose)}));
      diagnostics.add(
        limited(span(start, length), 'more than $widest attributes'),
      );
      unit = end;
      continue;
    }
    ranges.add(ranged(start, length, {'': called(name), ...attributes}));
    if (problem != null) {
      diagnostics.add(ranged(start, length, {'message': literal(problem)}));
    }
    unit = end;
  }
  return (ranges: ranges, diagnostics: diagnostics);
}

/// The region of layer 2 to read again when [changed] items of the text
/// changed: from the token holding the item before the change, or the run
/// of text before that one, which the change may join, to the first place
/// past the change where an unchanged token starts. Every token is read
/// from its own start without looking back, so from there on [next] reads
/// what it read before.
///
/// The scan looks ahead through a window that doubles until a token ends
/// short of it, since a token cut off by the window's end, such as a
/// comment that closes past it, is not yet the token it will be.
Range relexed(Layered<int> document, Range changed, Scanner next) {
  var start = changed.start;
  if (start > 0) {
    start = _from(document, start - 1);
    if (start > 0) {
      final previous = _from(document, start - 1);
      for (final (_, range) in document.within(
        2,
        span(previous, start - previous),
      )) {
        if (range.start == previous && range.end == start && texted(range)) {
          start = previous;
        }
      }
    }
  }
  final length = document.items.length;
  for (var size = changed.end - start + glimpse; ; size *= 2) {
    final end = min(start + size, length);
    final text = String.fromCharCodes(
      document.slice(span(start, end - start)).items,
    );
    final positions = Positions(text);
    var unit = 0;
    var position = start;
    while (position < end &&
        (position <= changed.end ||
            document.crossing(2, position).isNotEmpty)) {
      unit = next(text, unit).$1;
      position = start + positions[unit];
    }
    if (position < end || end == length) {
      return span(start, max(position, changed.end) - start);
    }
  }
}

/// The start of the layer-2 token holding item [position].
int _from(Layered<int> document, int position) {
  final around = document.crossing(2, position);
  return around.isEmpty ? position : around.single.$2.start;
}
