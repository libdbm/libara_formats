/// Structural edits for a syntax that represents its markup in the text and
/// reads a line by what the lines before it say, Markdown and roff among
/// them: each edit is the text it writes or takes away, read again, the
/// rewrite path the T8 spike found.
///
/// At layer 2 an edit writes an element's markup at a place, or takes
/// tokens away, and what it creates and removes is read off the same edit
/// made to a copy, so the tokens it leaves are a fresh read's.
///
/// At layer 3 an edit works out the new markup of the stretch the element
/// stands in and writes it at layer 2 in one request, and what layer 3
/// becomes is read off the copy the same way. Wrapping writes the element's
/// markup around what it holds; unwrapping takes away the tokens that are
/// its own; renaming rewrites them, or takes them away and wraps what is
/// left; deleting takes its tokens away.
library;

import 'dart:math';

import 'package:libara/libara.dart';

import 'aligned.dart';
import 'editing.dart';
import 'kinds.dart';
import 'lexing.dart';

/// How a syntax represents its elements.
abstract interface class Notation {
  /// The syntax's name, which its refusals say.
  String get syntax;

  /// What opens an element of [name] saying [said], or null where the
  /// syntax has no markup for it; a line it breaks carries on under
  /// [prefix].
  String? opening(String name, Map<String, String> said, String prefix);

  /// An element of [name] saying [said] that holds nothing, or null where
  /// the syntax has no markup for one; a line it breaks carries on under
  /// [prefix].
  String? empty(String name, Map<String, String> said, String prefix);

  /// What closes an element of [name] saying [said], or null where nothing
  /// does; a line it breaks carries on under [prefix].
  String? closing(String name, Map<String, String> said, String prefix);

  /// [words] in an element of [name] saying [said], standing where the
  /// lines carry on under [prefix], or null where the syntax has no
  /// markup for it.
  String? wrapped(
    String name,
    Map<String, String> said,
    String words,
    String prefix,
  );

  /// [words], one of an element of [old]'s own tokens, representing an element
  /// of [name] saying [said] instead, or null where they cannot as they
  /// stand.
  String? recast(
    String old,
    String name,
    Map<String, String> said,
    String words,
  );

  /// What a line written at item [at] of [document]'s text carries on
  /// under so as to stand where [at] does.
  String prefix(Layered<int> document, int at);

  /// Why an element of [name] saying [said] cannot be written as asked, or
  /// null where it can.
  String? lacking(String name, Map<String, String> said);

  /// What the tokens an element of [name] owns are called, and what the
  /// elements are called that own such tokens inside it; or null where it
  /// has no markup of its own to take away.
  (String, Set<String>)? owns(String name);

  /// A new list of [name] saying [said] over the elements [range] covers
  /// in [document], as the stretch of text to write and what to write
  /// there; or null where the syntax writes a list as any other element.
  (Range, String)? listed(
    Layered<int> document,
    String name,
    Map<String, String> said,
    ARange range,
  );

  /// [element], a list or an item of one in [document], taken away, as the
  /// stretch of text to write and what to write there; or null where its
  /// own tokens are taken away as any other element's are.
  (Range, String)? unlisted(Layered<int> document, ARange element);
}

/// The derivation of the structural [change] of [document], as [notation]
/// represents it.
Result<Derivation<int>> restructure(
  Notation notation,
  Layered<int> document,
  Edit<int> change,
) {
  Result<Derivation<int>> no(String why) => refuse(notation.syntax, why);
  return switch ((change.layer, change.command)) {
    (2, Mark(:final range)) => _write(notation, document, range),
    (2, Delete(:final span)) => _cut(notation, document, span),
    (2, Unmark() || Update()) => no(
      'elements are unmarked and renamed at layer 3',
    ),
    (3, Mark(:final marker, :final range)) => _wrap(
      notation,
      document,
      marker,
      range,
    ),
    (3, Unmark(:final marker)) => _unwrap(notation, document, marker),
    (3, Update(:final marker, :final attributes)) => _rename(
      notation,
      document,
      marker,
      attributes,
    ),
    (3, Delete(:final span)) => _drop(notation, document, span),
    (final layer, final command) => no(
      '$command at layer $layer is not an edit ${notation.syntax} makes',
    ),
  };
}

/// Writes what [range] asks for: the markup that opens or closes an
/// element, or a stretch written afresh.
Result<Derivation<int>> _write(
  Notation notation,
  Layered<int> document,
  ARange range,
) {
  if (range is _Replacement) {
    return _settled(
      notation,
      document,
      2,
      replaced(document, range, range.text),
      touched: span(range.start, range.text.runes.length),
    );
  }
  final name = '${range.get('')}';
  final said = stated(range.attributes);
  final at = range.start;
  // An opening says nothing yet of what the close will.
  if (range is Close) {
    if (notation.lacking(name, said) case final why?) {
      return refuse(notation.syntax, why);
    }
  }
  final written = switch (range) {
    Open() => notation.opening(name, said, notation.prefix(document, at)),
    Close() => notation.closing(name, said, notation.prefix(document, at)),
    Empty() => notation.empty(name, said, notation.prefix(document, at)),
    _ => null,
  };
  if (written == null) {
    return refuse(
      notation.syntax,
      range is Open || range is Close || range is Empty
          ? '${notation.syntax} has no representation for $name'
          : '$range is not markup ${notation.syntax} writes',
    );
  }
  return _settled(notation, document, 2, [
    Edit(1, Insert(at, Text.of(written))),
  ], touched: span(at, written.runes.length));
}

/// Takes away the tokens in [run].
Result<Derivation<int>> _cut(
  Notation notation,
  Layered<int> document,
  Range run,
) {
  final picked = document.span(2, run);
  if (picked.length != run.length) {
    return refuse(notation.syntax, '$run is not a run of tokens');
  }
  if (picked.isEmpty) {
    return done();
  }
  final from = picked.first.$2.start;
  return _settled(notation, document, 2, [
    Edit(1, Delete(span(from, picked.last.$2.end - from))),
  ], touched: span(from, 0));
}

/// Wraps the tokens [range] covers in a new element under [marker].
Result<Derivation<int>> _wrap(
  Notation notation,
  Layered<int> document,
  Marker marker,
  ARange range,
) {
  final name = '${range.get('')}';
  final said = stated(range.attributes);
  final picked = [for (final (_, token) in document.span(2, range)) token];
  if (picked.isEmpty || picked.length != range.length) {
    return refuse(notation.syntax, '$range is not a run of tokens to wrap');
  }
  if (notation.lacking(name, said) case final why?) {
    return refuse(notation.syntax, why);
  }
  if (notation.listed(document, name, said, range) case (
    final stretch,
    final written,
  )) {
    return _rewritten(
      notation,
      document,
      stretch,
      written,
      made: (marker, name),
    );
  }
  final from = picked.first.start;
  final stretch = span(from, picked.last.end - from);
  final written = notation.wrapped(
    name,
    said,
    covered(document, stretch),
    notation.prefix(document, from),
  );
  if (written == null) {
    return refuse(
      notation.syntax,
      '${notation.syntax} has no representation for $name',
    );
  }
  return _rewritten(notation, document, stretch, written, made: (marker, name));
}

/// Takes away the tokens that are the element under [marker]'s own.
Result<Derivation<int>> _unwrap(
  Notation notation,
  Layered<int> document,
  Marker marker,
) {
  final found = _owned(notation, document, marker);
  if (found == null) {
    return refuse(notation.syntax, '$marker is not an element');
  }
  final (element, own) = found;
  if (notation.unlisted(document, element) case (
    final stretch,
    final written,
  )) {
    return _rewritten(notation, document, stretch, written);
  }
  if (own.isEmpty) {
    return refuse(
      notation.syntax,
      '${element.get('')} has no representation of its own to take away; delete '
      'it instead',
    );
  }
  final (stretch, tokens) = _stretch(document, element);
  return _rewritten(
    notation,
    document,
    stretch,
    [
      for (final (index, token) in tokens.indexed)
        if (!own.contains(element.start + index)) covered(document, token),
    ].join(),
  );
}

/// Rewrites the element under [marker] as [attributes] name it, where its
/// own tokens can say the new name as they stand, and otherwise takes them
/// away and wraps what is left.
Result<Derivation<int>> _rename(
  Notation notation,
  Layered<int> document,
  Marker marker,
  Map<String, Value> attributes,
) {
  final found = _owned(notation, document, marker);
  if (found == null) {
    return refuse(notation.syntax, '$marker is not an element');
  }
  final (element, own) = found;
  final old = '${element.get('')}';
  final name = '${attributes['']}';
  final said = stated(attributes);
  if (notation.lacking(name, said) case final why?) {
    return refuse(notation.syntax, why);
  }
  final (stretch, tokens) = _stretch(document, element);
  final pieces = [
    for (final (index, token) in tokens.indexed)
      (own.contains(element.start + index), covered(document, token)),
  ];
  final recast = [
    for (final (mine, words) in pieces)
      mine ? notation.recast(old, name, said, words) : words,
  ];
  final String written;
  if (own.isNotEmpty && !recast.contains(null)) {
    written = recast.join();
  } else {
    final wrapped = notation.wrapped(
      name,
      said,
      [
        for (final (mine, words) in pieces)
          if (!mine) words,
      ].join(),
      notation.prefix(document, stretch.start),
    );
    if (wrapped == null) {
      return refuse(
        notation.syntax,
        '${notation.syntax} has no representation for $name',
      );
    }
    written = wrapped;
  }
  return _rewritten(
    notation,
    document,
    stretch,
    written,
    renamed: (marker, name),
  );
}

/// Deletes the elements in [indices] with what they hold.
Result<Derivation<int>> _drop(
  Notation notation,
  Layered<int> document,
  Range indices,
) {
  final elements = document.markers(3);
  if (indices.end > elements.length) {
    return refuse(notation.syntax, '$indices is not a run of elements');
  }
  if (indices.length == 0) {
    return done();
  }
  final picked = elements.sublist(indices.start, indices.end);
  final start = picked.map((element) => element.$2.start).reduce(min);
  final end = picked.map((element) => element.$2.end).reduce(max);
  if (end == start) {
    return refuse(notation.syntax, '$indices holds no tokens to delete');
  }
  return _settled(notation, document, 3, [
    Edit(2, Delete(span(start, end - start))),
  ]);
}

/// The derivation of an edit at [layer] that writes [written] in place of
/// [stretch] of [document]'s text, as [notation] represents it.
Result<Derivation<int>> rewritten(
  Notation notation,
  Layered<int> document,
  int layer,
  Range stretch,
  String written,
) => layer == 2
    ? _settled(
        notation,
        document,
        2,
        replaced(document, stretch, written),
        touched: span(stretch.start, written.runes.length),
      )
    : _rewritten(notation, document, stretch, written);

/// [stretch] of the text written as [written] instead, at layer 2, for a
/// layer-3 edit that [made] an element under a marker or [renamed] one.
Result<Derivation<int>> _rewritten(
  Notation notation,
  Layered<int> document,
  Range stretch,
  String written, {
  (Marker, String)? made,
  (Marker, String)? renamed,
}) {
  // Only what changes is written, so that the tokens either side of it
  // stand as they are.
  final old = covered(document, stretch);
  var head = 0;
  while (head < old.length &&
      head < written.length &&
      old.codeUnitAt(head) == written.codeUnitAt(head)) {
    head++;
  }
  var tail = 0;
  while (tail < old.length - head &&
      tail < written.length - head &&
      old.codeUnitAt(old.length - 1 - tail) ==
          written.codeUnitAt(written.length - 1 - tail)) {
    tail++;
  }
  final from = stretch.start + old.substring(0, head).runes.length;
  final to = stretch.end - old.substring(old.length - tail).runes.length;
  return _settled(
    notation,
    document,
    3,
    [
      Edit(
        2,
        Mark(
          _Replacement(
            span(from, to - from),
            written.substring(head, written.length - tail),
          ),
        ),
      ),
    ],
    made: made,
    renamed: renamed,
  );
}

/// The derivation of an edit at [layer] carried out by [below], whose text
/// it [touched]: the edit made to a copy, and its [layer] read off it, what
/// it lacks removed and what it gained created. Where it [made] an element
/// of a name, that one takes its marker; where it [renamed] one, the
/// element that came of it does, placed again under the marker it is
/// removed from.
Result<Derivation<int>> _settled(
  Notation notation,
  Layered<int> document,
  int layer,
  List<Edit<int>> below, {
  (Marker, String)? made,
  (Marker, String)? renamed,
  Range? touched,
}) {
  var after = document;
  for (final edit in below) {
    switch (after.apply(edit)) {
      case Failure(:final kind, :final message):
        return Failure(kind, message);
      case Success(:final value):
        after = value.document;
    }
  }
  final before = {for (final (marker, _) in document.markers(layer)) marker};
  final now = after.markers(layer);
  final kept = {for (final (marker, _) in now) marker};
  bool fresh((Marker, ARange) one) => !before.contains(one.$1);
  // An element kept over the same tokens as one made is placed again with
  // it, under its own marker, in the order a fresh read has them, so that
  // which holds which is read as it would be: a list made over one item
  // holds it.
  final spans = {
    for (final one in now)
      if (fresh(one)) (one.$2.start, one.$2.length),
  };
  final tied = {
    for (final (marker, range) in now)
      if (before.contains(marker) &&
          spans.contains((range.start, range.length)))
        marker,
  };
  final created = [
    for (final one in now)
      if (fresh(one) || tied.contains(one.$1)) one,
  ];
  final removed = [
    for (final marker in before)
      if (!kept.contains(marker) || tied.contains(marker)) marker,
  ];
  // The element made, or the one a rename came to, takes the marker the
  // edit names: a renamed one is placed again under its own. Others of its
  // name read afresh inside it, as a list inside an item made a list of, are
  // what it holds.
  if (made ?? renamed case (final marker, final name)
      when !kept.contains(marker)) {
    final named = [
      for (final (index, one) in created.indexed)
        if (fresh(one) && '${one.$2.get('')}' == name) index,
    ];
    final holding = [
      for (final index in named)
        if (named.every(
          (other) =>
              created[index].$2.start <= created[other].$2.start &&
              created[other].$2.end <= created[index].$2.end,
        ))
          index,
    ];
    if (holding.length != 1) {
      return refuse(
        notation.syntax,
        named.isEmpty
            ? 'the edit would make no $name'
            : 'the edit would make more than one $name',
      );
    }
    created[holding.first] = (marker, created[holding.first].$2);
  }
  return done(
    below: below,
    created: created,
    removed: removed,
    // A token kept whose text the edit changed, such as a fence that now
    // names another language, is said to be updated, so that the layer
    // above reads it again.
    updated: {
      if (touched != null)
        for (final (marker, range) in now)
          if (before.contains(marker) &&
              range.start <= touched.end &&
              touched.start <= range.end)
            marker: range.attributes,
    },
  );
}

/// A request, made at layer 3 and carried out at layer 2, that the text in
/// a range be written as [text] instead.
final class _Replacement extends ARange {
  _Replacement(Range range, this.text) : super.from(range, const {});

  final String text;
}

/// Where the line holding item [at] of [document]'s text starts.
int line(Layered<int> document, int at) {
  for (var size = glimpse; ; size *= 2) {
    final low = max(0, at - size);
    final text = covered(document, span(low, at - low));
    final cut = text.lastIndexOf('\n');
    if (cut >= 0) {
      return low + text.substring(0, cut + 1).runes.length;
    }
    if (low == 0) {
      return 0;
    }
  }
}

/// The element under [marker] and the indices of the tokens that are its
/// own, as [notation] names them: those in it of the name it owns that no
/// element of its kind inside it holds. Null where there is no element
/// under [marker]; no tokens where it has no markup of its own.
(ARange, Set<int>)? _owned(
  Notation notation,
  Layered<int> document,
  Marker marker,
) {
  final element = marked(document, 3, marker);
  if (element == null) {
    return null;
  }
  final owns = notation.owns('${element.get('')}');
  if (owns == null) {
    return (element, const {});
  }
  final (token, kind) = owns;
  final inner = [
    for (final (other, range) in document.within(3, element))
      if (other != marker && kind.contains('${range.get('')}')) range,
  ];
  return (
    element,
    {
      for (final (index, (_, range)) in document.span(2, element).indexed)
        if ('${range.get('')}' == token &&
            !inner.any(
              (other) =>
                  other.start <= element.start + index &&
                  element.start + index < other.end,
            ))
          element.start + index,
    },
  );
}

/// The text [element] covers, and its tokens; an element of no tokens
/// covers no text where it stands.
(Range, List<ARange>) _stretch(Layered<int> document, ARange element) {
  final tokens = [for (final (_, token) in document.span(2, element)) token];
  if (tokens.isEmpty) {
    final at =
        document.span(2, span(element.start, 1)).firstOrNull?.$2.start ??
        document.items.length;
    return (span(at, 0), tokens);
  }
  final from = tokens.first.start;
  return (span(from, tokens.last.end - from), tokens);
}
