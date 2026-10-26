/// What every syntax's structural edits share: rewriting a stretch of the
/// text and reading it again with the syntax's own scanner, so the tokens an
/// edit leaves are the ones a fresh read gives.
library;

import 'package:libara/libara.dart';

import 'aligned.dart';
import 'lexing.dart';
import 'positions.dart';

/// Replaces [run] of [document]'s text with [text], and the tokens in it
/// with what [next] reads there.
///
/// With [widen], the stretch read again takes in the runs of text either
/// side, which the change may join; a stretch always takes in a token that
/// [run] cuts into. A stretch holding markup in error is refused for
/// [syntax], since its diagnostic is not the edit's to move, and so is an
/// edit that would leave some.
Result<Derivation<int>> rewrite(
  Layered<int> document,
  Range run,
  String text,
  Scanner next,
  String syntax, {
  bool widen = true,
}) {
  var (from, to) = (run.start, run.end);
  if (from > 0) {
    final before = holding(document, from - 1)!;
    if (before.end > from || (widen && texted(before))) {
      from = before.start;
    }
  }
  if (to < document.items.length) {
    final after = holding(document, to)!;
    if (after.start < to || (widen && texted(after))) {
      to = after.end;
    }
  }
  final stretch = span(from, to - from);
  for (final problem in document.diagnostics(2).items) {
    if (problem.start < stretch.end && stretch.start < problem.end) {
      return refuse(syntax, '$stretch holds markup in error');
    }
  }
  final written =
      covered(document, span(from, run.start - from)) +
      text +
      covered(document, span(run.end, to - run.end));
  final positions = Positions(written);
  final created = <(Marker, ARange)>[];
  var unit = 0;
  var last = 0;
  while (unit < written.length) {
    last = unit;
    final (end, name, attributes, problem) = next(written, unit);
    if (problem != null) {
      return refuse(
        syntax,
        'the edit would leave "$written" in error: $problem',
      );
    }
    created.add((
      Marker(),
      ranged(from + positions[unit], positions[end] - positions[unit], {
        '': literal(name),
        ...attributes,
      }),
    ));
    unit = end;
  }
  // A token at the end of the stretch that would read on into what follows
  // it, such as an element read as text to its end tag, is not the token a
  // fresh read gives.
  if (to < document.items.length &&
      created.isNotEmpty &&
      !texted(created.last.$2) &&
      next(written + covered(document, span(to, 1)), last).$1 >
          written.length) {
    return refuse(syntax, '"$written" would read on into what follows it');
  }
  return done(
    below: replaced(document, run, text),
    created: created,
    removed: [for (final (marker, _) in document.within(2, stretch)) marker],
  );
}

/// A tag syntax's own structural edits at layers 2 and 3, one for each
/// command; deleting tokens is [cut], the same for every syntax.
typedef Structural = ({
  Result<Derivation<int>> Function(Layered<int>, ARange) mark,
  Result<Derivation<int>> Function(Layered<int>, Marker) uncomment,
  Result<Derivation<int>> Function(Layered<int>, Marker, Map<String, Value>)
  retag,
  Result<Derivation<int>> Function(Layered<int>, Marker, ARange) wrap,
  Result<Derivation<int>> Function(Layered<int>, Marker) unwrap,
  Result<Derivation<int>> Function(Layered<int>, Marker, Map<String, Value>)
  rename,
  Result<Derivation<int>> Function(Layered<int>, Range) drop,
});

/// [change] to [document] carried out by the one of [edits] for its layer
/// and command, or by [cut] with [next], and otherwise refused for
/// [syntax].
Result<Derivation<int>> routed(
  Layered<int> document,
  Edit<int> change,
  String syntax,
  Scanner next,
  Structural edits,
) => switch ((change.layer, change.command)) {
  (2, Mark(:final range)) => edits.mark(document, range),
  (2, Unmark(:final marker)) => edits.uncomment(document, marker),
  (2, Update(:final marker, :final attributes)) => edits.retag(
    document,
    marker,
    attributes,
  ),
  (2, Delete(:final span)) => cut(document, span, next, syntax),
  (3, Mark(:final marker, :final range)) => edits.wrap(document, marker, range),
  (3, Unmark(:final marker)) => edits.unwrap(document, marker),
  (3, Update(:final marker, :final attributes)) => edits.rename(
    document,
    marker,
    attributes,
  ),
  (3, Delete(:final span)) => edits.drop(document, span),
  (final layer, final command) => refuse(
    syntax,
    '$command at layer $layer is not an ${syntax.toUpperCase()} edit',
  ),
};

/// Deletes the tokens in [run], joining the runs of text either side, which
/// [next] reads again for [syntax].
Result<Derivation<int>> cut(
  Layered<int> document,
  Range run,
  Scanner next,
  String syntax,
) {
  final picked = document.span(2, run);
  if (picked.length != run.length) {
    return refuse(syntax, '$run is not a run of tokens');
  }
  if (picked.isEmpty) {
    return done();
  }
  final first = picked.first.$2;
  return rewrite(
    document,
    span(first.start, picked.last.$2.end - first.start),
    '',
    next,
    syntax,
  );
}

/// The text of [token] with [inner] written over [swapped], the part of it
/// a tag's new name and attributes take.
String retagged(
  Layered<int> document,
  ARange token,
  Range swapped,
  String inner,
) => covered(document, token).replaceRange(
  units(document, token.start, swapped.start),
  units(document, token.start, swapped.end),
  inner,
);

/// The token other than a run of text that [at] falls strictly inside, if
/// any: no tag is written into the middle of another.
ARange? inside(Layered<int> document, int at) {
  final around = document.crossing(2, at);
  return around.isEmpty || texted(around.single.$2) ? null : around.single.$2;
}

/// The layer-2 token holding item [position].
ARange? holding(Layered<int> document, int position) {
  final around = document.crossing(2, position);
  if (around.isNotEmpty) {
    return around.single.$2;
  }
  for (final (_, token) in [
    ...document.crossing(2, position + 1),
    ...document.within(2, span(position, 1)),
  ]) {
    if (token.start == position) {
      return token;
    }
  }
  return null;
}

/// Whether [one] and [other] say the same things.
bool same(Map<String, Value> one, Map<String, Value> other) =>
    one.length == other.length &&
    one.entries.every((entry) => other[entry.key] == entry.value);

/// The range under [marker] at [layer], or null.
ARange? marked(Layered<int> document, int layer, Marker marker) {
  for (final (key, range) in document.markers(layer)) {
    if (key == marker) {
      return range;
    }
  }
  return null;
}

/// The text [range] covers, as a Dart string.
String covered(Layered<int> document, Range range) =>
    String.fromCharCodes(document.slice(range).items);

/// The text of each of [tokens], or of a token among them, read off one
/// slice of [document]'s text, taken when first asked for, rather than off
/// a slice for each.
String Function(Range token) texts(
  Layered<int> document,
  List<(Marker, ARange)> tokens,
) {
  List<int>? codes;
  final start = tokens.isEmpty ? 0 : tokens.first.$2.start;
  return (token) {
    codes ??= document
        .slice(span(start, tokens.last.$2.end - start))
        .items
        .toList();
    return String.fromCharCodes(codes!, token.start - start, token.end - start);
  };
}

/// The UTF-16 units of the text from [from] to [to].
int units(Layered<int> document, int from, int to) =>
    covered(document, span(from, to - from)).length;

/// [syntax] refusing an edit, saying [why].
Result<Derivation<int>> refuse(String syntax, String why) =>
    Failure(Kind.invalid, '$syntax: $why');

/// The derivation of an edit.
Result<Derivation<int>> done({
  List<Edit<int>> below = const [],
  List<(Marker, ARange)> created = const [],
  List<Marker> removed = const [],
  Map<Marker, Map<String, Value>> updated = const {},
}) => Success((
  below: below,
  created: created,
  removed: removed,
  updated: updated,
));

/// What a text [change] makes of [document] where it leaves the markup as
/// it stands, or [syntax] saying why it does not:
/// - an edge strictly inside a token other than a run of text fails, since
///   a tag is not text;
/// - an edit leaving every token outside it as it was, called and written
///   the same, and putting in only what shows text, goes through;
/// - one taking whole tags with it goes where they nest, an opener for
///   every closer of the same element, as when the end tag of one block and
///   the start tag of the next are taken, joining them; and where the markup
///   is written in the words, without [tags], any deletion goes, since that
///   is how its markup is taken away.
Result<Change<int>> checked(
  Layered<int> document,
  Edit<int> change,
  String syntax, {
  required bool tags,
}) {
  final (start, end, length) = switch (change.command) {
    Insert(:final position, :final items) => (position, position, items.length),
    Delete(:final span) => (span.start, span.end, 0),
    Replace(:final span, :final items) => (span.start, span.end, items.length),
    _ => (-1, -1, 0),
  };
  if (change.layer != 1 || start < 0) {
    return Failure(Kind.invalid, '$syntax: $change is not a text edit');
  }
  for (final edge in {start, end}) {
    if (inside(document, edge) case final token?) {
      return Failure(
        Kind.invalid,
        '$syntax: text edit intersects the protected ${token.get('')} '
        'markup token',
      );
    }
  }
  return document.apply(change).flatMap((applied) {
    final after = applied.document;
    // Only what the syntax read again can differ: the tokens outside it
    // are the same tokens, moved along. So the comparison is over the
    // stretch it read, and the edit, before and after.
    var from = start;
    var to = start + length;
    for (final region in applied.layers[1].regions) {
      from = region.start < from ? region.start : from;
      to = region.end > to ? region.end : to;
    }
    final shift = length - (end - start);
    final held = <ARange>[];
    var taking = false;
    for (final (_, token) in document.within(
      2,
      span(from, to - shift - from),
    )) {
      if (texted(token)) {
        continue;
      }
      if (token.length > 0 && token.start >= start && token.end <= end) {
        taking = taking || token.get('shows') == null;
      } else {
        held.add(token);
      }
    }
    var alike = true;
    var at = 0;
    for (final (_, token) in after.within(2, span(from, to - from))) {
      if (texted(token)) {
        continue;
      }
      if (token.length > 0 &&
          token.start >= start &&
          token.end <= start + length) {
        alike = alike && token.get('shows') != null;
        continue;
      }
      if (at == held.length) {
        alike = false;
        break;
      }
      final one = held[at];
      at += 1;
      alike =
          alike &&
          one.length == token.length &&
          one.get('') == token.get('') &&
          covered(document, one) == covered(after, token);
    }
    alike = alike && at == held.length;
    if (alike && (!taking || !tags || _nests(document, start, end)) ||
        !tags && length == 0) {
      return Success(applied);
    }
    return Failure(
      Kind.invalid,
      '$syntax: text edit would change the markup structure',
    );
  });
}

/// Whether the tags of [document] from [start] to [end] that show nothing
/// open as many of each element as they close.
bool _nests(Layered<int> document, int start, int end) {
  final tokens = document.layer(2).items.cast<ARange>().toList();
  final taken = <int>{
    for (final (index, token) in tokens.indexed)
      if (!texted(token) &&
          token.length > 0 &&
          token.start >= start &&
          token.end <= end &&
          token.get('shows') == null)
        index,
  };
  final open = <Value?, int>{};
  for (final element in document.layer(3).items.cast<ARange>()) {
    if (element.length < 2) {
      continue;
    }
    final name = element.get('');
    if (taken.contains(element.start) &&
        tokens[element.start].get('') == name) {
      open[name] = (open[name] ?? 0) + 1;
    }
    if (taken.contains(element.end - 1) &&
        tokens[element.end - 1].get('') == name) {
      open[name] = (open[name] ?? 0) - 1;
    }
  }
  return open.values.every((count) => count == 0);
}

/// [text] as [escape] writes it, or as it stands where [raw].
List<int> escaping(
  List<int> text,
  String Function(String text) escape, {
  required bool raw,
}) => raw ? text : escape(String.fromCharCodes(text)).runes.toList();

/// What a move does with [range], a layer-[layer] range of [document]
/// crossing an edge of what it moves: a run of text is cut back, and read
/// again either side, and so is an element with no tag of its own, which
/// HTML implies around what it holds; a tag is not cut, and an element
/// with tags is moved only whole.
Crossing crossed(Layered<int> document, int layer, ARange range) =>
    switch (layer) {
      2 when texted(range) => Crossing.clamp,
      3 when !tagged(document, range) => Crossing.clamp,
      _ => Crossing.refuse,
    };

/// Whether [element], over tokens of [document], opens with a tag of its
/// own, called what it is.
bool tagged(Layered<int> document, ARange element) {
  if (element.length == 0) {
    return false;
  }
  final first = document.layer(2).items.elementAt(element.start) as ARange;
  return !texted(first) && first.get('') == element.get('');
}
