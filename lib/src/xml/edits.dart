part of 'xml.dart';

/// XML's structural edits, each carried out as edits one layer down.
///
/// At layer 2 an edit rewrites a stretch of the text and reads that stretch
/// again with the scanner, so the tokens it leaves are the ones a fresh read
/// gives: the stretch reaches out over the runs of text either side, which
/// join where nothing stands between them any more. A token holding markup
/// in error is never part of a stretch, since its diagnostic is not the
/// edit's to move.
///
/// At layer 3 an edit is made of layer-2 edits to the element's tags, and
/// is refused where what it touches would pair differently afterwards.
extension on _Grammar {
  Result<Derivation<int>> _edit(Layered<int> document, Edit<int> change) =>
      routed(document, change, 'xml', _next, (
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
    if (!named(name)) {
      return _refuse('"$name" is not a name XML can represent');
    }
    for (final key in attributes.keys) {
      if (!named(key)) {
        return _refuse('"$key" is not an attribute name XML can represent');
      }
    }
    final markup = switch (range) {
      Open() => opener(name, attributes),
      Close() => '</$name>',
      Empty() => opener(name, attributes, closed: true),
      _ => null,
    };
    if (markup == null) {
      return _refuse('$range does not say what markup to write');
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
    final content = covered(document, range);
    if (content.contains('--') || content.endsWith('-')) {
      return _refuse('a comment cannot hold "--" or end with "-"');
    }
    return _rewrite(document, range, '<!--$content-->', widen: false);
  }

  /// Takes the delimiters off the comment under [marker], keeping what it
  /// says as text and markup.
  Result<Derivation<int>> _uncomment(Layered<int> document, Marker marker) {
    final token = marked(document, 2, marker);
    if (token == null || '${token.get('')}' != '#comment') {
      return _refuse('only a comment is unmarked at layer 2; delete a tag');
    }
    final content = covered(document, span(token.start + 4, token.length - 7));
    return _rewrite(document, token, content);
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
    if (attributes[''] is! Str || !named(name)) {
      return _refuse('"$name" is not a name XML can represent');
    }
    if (attributes.values.any((value) => value is! Str)) {
      return _refuse('an attribute value in XML is text');
    }
    final role = _Grammar._role(document, token);
    final said = stated(attributes);
    if (role == _Role.end && said.isNotEmpty) {
      return _refuse('an end tag says nothing but its name');
    }
    for (final key in said.keys) {
      if (!named(key)) {
        return _refuse('"$key" is not an attribute name XML can represent');
      }
    }
    final unchanged = same(
      {...token.attributes}..remove(''),
      {...attributes}..remove(''),
    );
    final Range swapped;
    final String inner;
    if (unchanged || role == _Role.end) {
      final from = token.start + (role == _Role.end ? 2 : 1);
      swapped = span(from, old.runes.length);
      inner = name;
    } else {
      final close = role == _Role.empty ? 2 : 1;
      swapped = span(token.start + 1, token.length - 1 - close);
      final written = opener(name, said, closed: role == _Role.empty);
      inner = written.substring(1, written.length - close);
    }
    final rewritten = retagged(document, token, swapped, inner);
    final (end, _, read, problem) = _next(rewritten, 0);
    if (problem != null || end != rewritten.length) {
      return _refuse('$rewritten is not a tag XML reads back whole');
    }
    return done(
      below: [Edit(1, Replace(swapped, Text.of(inner)))],
      updated: {
        marker: {'': literal(name), ...read},
      },
    );
  }

  /// Wraps the tokens [range] covers, which must hold whole elements, in a
  /// new element under [marker].
  Result<Derivation<int>> _wrap(
    Layered<int> document,
    Marker marker,
    ARange range,
  ) {
    final name = '${range.get('')}';
    final said = stated(range.attributes);
    final tokens = document.span(2, range);
    if (tokens.length != range.length || range.get('') is! Str) {
      return _refuse('$range is not a new element over tokens');
    }
    if (_pair(document, range, seeded: false).$2.isNotEmpty) {
      return _refuse('$range does not hold whole elements');
    }
    final at = tokens.isEmpty
        ? (document.span(2, span(range.start, 1)).firstOrNull?.$2.start ??
              document.items.length)
        : tokens.first.$2.start;
    final end = tokens.isEmpty ? at : tokens.last.$2.end;
    final open = Open(at, name, said);
    return done(
      below: [Edit(2, Mark(Close(end, name))), Edit(2, Mark(open))],
      created: [
        (
          marker,
          ARange.from(span(range.start, range.length + 2), open.attributes),
        ),
      ],
    );
  }

  /// Takes the tags off the element under [marker], keeping what it holds.
  Result<Derivation<int>> _unwrap(Layered<int> document, Marker marker) {
    final element = marked(document, 3, marker);
    if (element == null) {
      return _refuse('$marker is not an element');
    }
    if (element.length < 2) {
      return _refuse('$element holds nothing to keep; delete it instead');
    }
    if (_pair(document, element, seeded: false).$2.isNotEmpty) {
      return _refuse('$element holds tags that would pair differently');
    }
    return done(
      below: [
        Edit(2, Delete(span(element.end - 1, 1))),
        Edit(2, Delete(span(element.start, 1))),
      ],
      removed: [marker],
    );
  }

  /// Renames the element under [marker] at both its tags, and gives its
  /// start tag the attributes in [attributes].
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
    if (_pair(document, element, seeded: false).$2.isNotEmpty) {
      return _refuse('$element holds tags that would pair differently');
    }
    final tags = document.markers(2);
    return done(
      below: [
        if (element.length > 1)
          Edit(2, Update(tags[element.end - 1].$1, {'': attributes['']!})),
        Edit(2, Update(tags[element.start].$1, attributes)),
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
    var (start, end) = (elements[indices.start].$2.start, 0);
    for (final (_, range) in elements.sublist(indices.start, indices.end)) {
      start = min(start, range.start);
      end = max(end, range.end);
    }
    final run = span(start, end - start);
    if (_pair(document, run, seeded: false).$2.isNotEmpty) {
      return _refuse('$indices cuts through an element');
    }
    return done(
      below: [Edit(2, Delete(run))],
      removed: [
        for (final (element, range) in elements)
          if (run.start <= range.start && range.end <= run.end) element,
      ],
    );
  }

  /// [run] of the text replaced with [text], read again by XML's scanner.
  Result<Derivation<int>> _rewrite(
    Layered<int> document,
    Range run,
    String text, {
    bool widen = true,
  }) => rewrite(document, run, text, _next, 'xml', widen: widen);
}

Result<Derivation<int>> _refuse(String why) => refuse('xml', why);
