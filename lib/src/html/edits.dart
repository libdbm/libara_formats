part of 'html.dart';

/// HTML's structural edits, each carried out as edits one layer down.
///
/// At layer 2 an edit rewrites a stretch of the text and reads that stretch
/// again with the tokenizer, as XML's do. A tag is written only where HTML
/// reads it back as itself, and never one whose element reads what follows
/// as text, which would take in markup past the stretch.
///
/// At layer 3 an edit is made of layer-2 edits to the element's tags, and
/// is refused unless the tree a fresh read builds afterwards is the one
/// before, carried across the edit, with only the edited element changed:
/// see [_settled].
extension on _Grammar {
  Result<Derivation<int>> _edit(Layered<int> document, Edit<int> change) =>
      routed(document, change, 'html', _next, (
        mark: _mark,
        uncomment: _uncomment,
        retag: _retag,
        wrap: _wrap,
        unwrap: _unwrap,
        rename: _rename,
        drop: _drop,
      ));

  /// Writes the tag or comment [range] asks for.
  Result<Derivation<int>> _mark(Layered<int> document, ARange range) {
    if (range is Comment) {
      return _comment(document, range);
    }
    final name = '${range.get('')}';
    final attributes = stated(range.attributes);
    final markup = switch (range) {
      Open() => opener(name, attributes),
      Close() => '</$name>',
      Empty() when _voids.contains(name) => opener(name, attributes),
      Empty() => null,
      _ => null,
    };
    if (markup == null) {
      return _refuse(
        range is Empty
            ? 'only a void element is written empty, not "$name"'
            : '$range does not say what markup to write',
      );
    }
    if (_read(markup, range is Close ? {'': literal(name)} : range.attributes)
        case final why?) {
      return _refuse(why);
    }
    final at = range.start;
    if (inside(document, at) case final token?) {
      return _refuse('$at is inside $token');
    }
    return _rewrite(document, span(at, 0), markup, widen: false);
  }

  /// Makes the text [range] covers a comment.
  Result<Derivation<int>> _comment(Layered<int> document, ARange range) {
    for (final at in [range.start, range.end]) {
      if (inside(document, at) case final token?) {
        return _refuse('$at is inside $token');
      }
    }
    final markup = '<!--${covered(document, range)}-->';
    final (end, name, _, problem) = _next(markup, 0);
    if (end != markup.length || name != '#comment' || problem != null) {
      return _refuse('"$markup" does not read back as one comment');
    }
    return _rewrite(document, range, markup, widen: false);
  }

  /// Takes the delimiters off the comment under [marker], keeping what it
  /// says as text and markup.
  Result<Derivation<int>> _uncomment(Layered<int> document, Marker marker) {
    final token = marked(document, 2, marker);
    final text = token == null ? '' : covered(document, token);
    if (token == null ||
        '${token.get('')}' != '#comment' ||
        !text.startsWith('<!--') ||
        !text.endsWith('-->') ||
        text.length < 7) {
      return _refuse('only a comment is unmarked at layer 2; delete a tag');
    }
    return _rewrite(document, token, text.substring(4, text.length - 3));
  }

  /// Gives the tag under [marker] the name and attributes in [attributes],
  /// keeping its marker: the name is changed in place where nothing else
  /// is, and the tag is written afresh where its attributes change.
  Result<Derivation<int>> _retag(
    Layered<int> document,
    Marker marker,
    Map<String, Value> attributes,
  ) {
    final token = marked(document, 2, marker);
    final old = '${token?.get('')}';
    if (token == null || old.startsWith('#')) {
      return _refuse('$marker is not a tag');
    }
    final name = '${attributes['']}';
    if (attributes[''] is! Str ||
        attributes.values.any((value) => value is! Str)) {
      return _refuse('an attribute value in HTML is text');
    }
    final text = covered(document, token);
    if (_whole(old)) {
      return _refuse('$token holds its element\'s text, read as text');
    }
    final end = text.startsWith('</');
    final said = stated(attributes);
    if (end && said.isNotEmpty) {
      return _refuse('an end tag says nothing but its name');
    }
    final Range swapped;
    final String inner;
    if (end ||
        same({...token.attributes}..remove(''), {...attributes}..remove(''))) {
      swapped = span(token.start + (end ? 2 : 1), old.runes.length);
      inner = name;
    } else {
      final closed = selfClosed(text);
      final close = closed ? 2 : 1;
      swapped = span(token.start + 1, token.length - 1 - close);
      final written = opener(name, said, closed: closed);
      inner = written.substring(1, written.length - close);
    }
    final rewritten = retagged(document, token, swapped, inner);
    if (_read(rewritten, end ? {'': literal(name)} : attributes)
        case final why?) {
      return _refuse(why);
    }
    return done(
      below: [Edit(1, Replace(swapped, Text.of(inner)))],
      updated: {
        marker: {...attributes, '': literal(name)},
      },
    );
  }

  /// Wraps the tokens [range] covers in a new element under [marker].
  Result<Derivation<int>> _wrap(
    Layered<int> document,
    Marker marker,
    ARange range,
  ) {
    final name = '${range.get('')}';
    final tokens = document.span(2, range);
    if (tokens.length != range.length || range.get('') is! Str) {
      return _refuse('$range is not a new element over tokens');
    }
    final at = tokens.isEmpty
        ? (document.span(2, span(range.start, 1)).firstOrNull?.$2.start ??
              document.items.length)
        : tokens.first.$2.start;
    final end = tokens.isEmpty ? at : tokens.last.$2.end;
    return _settled(
      document,
      [
        Edit(2, Mark(Close(end, name))),
        Edit(2, Mark(Open(at, name, stated(range.attributes)))),
      ],
      created: (marker, range.attributes),
    );
  }

  /// Takes the tags off the element under [marker], keeping what it holds.
  Result<Derivation<int>> _unwrap(Layered<int> document, Marker marker) {
    final element = marked(document, 3, marker);
    if (element == null) {
      return _refuse('$marker is not an element');
    }
    final (start, end) = _tags(document, element);
    if (start == null && end == null) {
      return _refuse('$element has no tags of its own');
    }
    return _settled(
      document,
      [
        if (end != null) Edit(2, Delete(span(end, 1))),
        if (start != null) Edit(2, Delete(span(start, 1))),
      ],
      removed: {marker},
    );
  }

  /// Renames the element under [marker] at its tags, and gives its start
  /// tag the attributes in [attributes].
  Result<Derivation<int>> _rename(
    Layered<int> document,
    Marker marker,
    Map<String, Value> attributes,
  ) {
    final element = marked(document, 3, marker);
    if (element == null) {
      return _refuse('$marker is not an element');
    }
    if (attributes[''] is! Str) {
      return _refuse('$attributes names no element');
    }
    final (start, end) = _tags(document, element);
    if (start == null) {
      return _refuse('$element has no start tag of its own');
    }
    final tags = document.markers(2);
    return _settled(
      document,
      [
        if (end != null) Edit(2, Update(tags[end].$1, {'': attributes['']!})),
        Edit(2, Update(tags[start].$1, attributes)),
      ],
      updated: {marker: attributes},
    );
  }

  /// Deletes the elements in [indices] with what they hold.
  Result<Derivation<int>> _drop(Layered<int> document, Range indices) {
    final elements = document.markers(3);
    if (indices.end > elements.length) {
      return _refuse('$indices is not a run of elements');
    }
    if (indices.length == 0) {
      return done();
    }
    final picked = elements.sublist(indices.start, indices.end);
    final start = picked.map((element) => element.$2.start).reduce(min);
    final end = picked.map((element) => element.$2.end).reduce(max);
    return _settled(
      document,
      [if (end > start) Edit(2, Delete(span(start, end - start)))],
      removed: {for (final (marker, _) in picked) marker},
    );
  }

  /// [run] of the text replaced with [text], read again by HTML's
  /// tokenizer.
  Result<Derivation<int>> _rewrite(
    Layered<int> document,
    Range run,
    String text, {
    bool widen = true,
  }) => rewrite(document, run, text, _next, 'html', widen: widen);
}

/// The derivation of a layer-3 edit of [document] carried out by [below],
/// which removes the elements [removed], gives those in [updated] new
/// attributes, and makes the element [created], if any: refused unless
/// what a fresh read builds once [below] is done is every other element
/// and diagnostic as libara carries it across [below], so that the layers
/// the edit leaves are the ones a fresh read gives.
///
/// An element is carried to the tokens it held that [below] keeps, tokens
/// [below] writes between them falling inside it, and one empty element to
/// the first kept token from where it stood; an element [below] keeps
/// none of the tokens of is removed with the rest, and a diagnostic is
/// left empty where they were, since an edit cannot remove one.
Result<Derivation<int>> _settled(
  Layered<int> document,
  List<Edit<int>> below, {
  (Marker, Map<String, Value>)? created,
  Set<Marker> removed = const {},
  Map<Marker, Map<String, Value>> updated = const {},
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
  final places = {
    for (final (index, (marker, _)) in after.markers(2).indexed) marker: index,
  };
  final kept = [for (final (marker, _) in document.markers(2)) places[marker]];
  Range? carried(Range range) {
    if (range.length == 0) {
      for (final place in kept.skip(range.start)) {
        if (place != null) {
          return span(place, 0);
        }
      }
      return span(after.layer(2).length, 0);
    }
    final held = [
      for (final place in kept.sublist(range.start, range.end)) ?place,
    ];
    return held.isEmpty ? null : span(held.first, held.last - held.first + 1);
  }

  String key(Range range, Map<String, Value> attributes) =>
      '${range.start},${range.length},'
      '${(attributes.entries.map((entry) => '${entry.key}=${entry.value}').toList()..sort()).join(',')}';

  // An element with no tags of its own, as HTML implies, may take in the
  // tokens [below] puts in at its edges, as a fresh read does; an empty one
  // may stand before them.
  final placed = {...kept.nonNulls};
  Range widened(Range range) {
    var (start, end) = (range.start, range.end);
    while (start > 0 && !placed.contains(start - 1)) {
      start--;
    }
    while (end < after.layer(2).length && !placed.contains(end)) {
      end++;
    }
    return span(start, end - start);
  }

  final gone = <Marker>[...removed];
  final expected = <(Marker, List<String>)>[];
  for (final (marker, element) in document.markers(3)) {
    if (removed.contains(marker)) {
      continue;
    }
    final range = carried(element);
    if (range == null) {
      gone.add(marker);
      continue;
    }
    final attributes = updated[marker] ?? element.attributes;
    expected.add((
      marker,
      [
        key(range, attributes),
        if (!tagged(document, element))
          key(
            range.length == 0 ? span(widened(range).start, 0) : widened(range),
            attributes,
          ),
      ],
    ));
  }
  final fresh = <String, List<ARange>>{};
  for (final element in after.layer(3).items.cast<ARange>()) {
    (fresh[key(element, element.attributes)] ??= []).add(element);
  }
  // A widened element is placed again under its own marker.
  final placing = <(Marker, ARange)>[];
  for (final (marker, wanted) in expected) {
    final found = [
      for (final one in wanted)
        if (fresh[one] case final found? when found.isNotEmpty) found,
    ].firstOrNull;
    if (found == null) {
      return _refuse('the edit would change other elements');
    }
    final element = found.removeLast();
    if (!identical(found, fresh[wanted.first])) {
      placing.add((marker, element));
    }
  }
  final left = [for (final elements in fresh.values) ...elements];
  if (created == null
      ? left.isNotEmpty
      : left.length != 1 || !same(left.single.attributes, created.$2)) {
    return _refuse('the edit would change other elements');
  }
  final notes = <String>[];
  for (final problem in document.diagnostics(3).items.cast<ARange>()) {
    // A diagnostic stays where every token under it went, collapsed.
    final range = carried(problem) ?? carried(span(problem.start, 0))!;
    notes.add(key(range, problem.attributes));
  }
  final now = [
    for (final problem in after.diagnostics(3).items.cast<ARange>())
      key(problem, problem.attributes),
  ];
  if (!_alike(notes, now)) {
    return _refuse('the edit would change what is in error');
  }
  return done(
    below: below,
    created: [if (created != null) (created.$1, left.single), ...placing],
    removed: [...gone, for (final (marker, _) in placing) marker],
    updated: updated,
  );
}

/// Whether [one] and [other] hold the same items, in any order.
bool _alike(List<String> one, List<String> other) =>
    one.length == other.length &&
    (one.toList()..sort()).join('\n') == (other.toList()..sort()).join('\n');

/// The indices of [element]'s own start and end tags, where it has them:
/// a start tag of its name at its first token, and an end tag of its name
/// at its last.
(int?, int?) _tags(Layered<int> document, ARange element) {
  if (element.length == 0) {
    return (null, null);
  }
  final name = '${element.get('')}';
  bool tag(int index, {required bool end}) {
    final token = document.span(2, span(index, 1)).single.$2;
    return '${token.get('')}' == name &&
        covered(document, token).startsWith('</') == end;
  }

  final start = tag(element.start, end: false) ? element.start : null;
  final end = element.length > 1 && tag(element.end - 1, end: true)
      ? element.end - 1
      : null;
  return (start, end);
}

/// Why [markup] is not written: null where HTML reads it back as one tag
/// saying [attributes], whose element does not read what follows as text.
String? _read(String markup, Map<String, Value> attributes) {
  final (end, name, read, problem) = _next(markup, 0);
  final wanted = '${attributes['']}';
  if (end != markup.length ||
      problem != null ||
      (attributes.containsKey('') && name != wanted) ||
      !same(read, {
        for (final MapEntry(:key, :value) in attributes.entries)
          if (key.isNotEmpty) key: value,
      })) {
    return '"$markup" is not what HTML reads back as the tag asked for';
  }
  if (_whole(name) && !markup.startsWith('</')) {
    return '<$name> reads what follows it as text';
  }
  return null;
}

/// Whether an element of [name] reads its content as text.
bool _whole(String name) => _raw.contains(name) || name == 'plaintext';

Result<Derivation<int>> _refuse(String why) => refuse('html', why);
