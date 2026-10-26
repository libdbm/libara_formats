part of 'lmnl.dart';

/// LMNL's structural edits, each carried out as edits one layer down.
///
/// At layer 2 an edit rewrites a stretch of the text and reads it again, as
/// every syntax's do. At layer 3 an edit is made of layer-2 edits to an
/// element's tags. Nothing is refused for overlap. What is refused is an
/// edit after which a tag would pair differently: pairing goes by name, so
/// a tag of an element's name standing inside it is what stands in the
/// way.
extension on _Grammar {
  Result<Derivation<int>> _edit(Layered<int> document, Edit<int> change) =>
      routed(document, change, 'lmnl', _Grammar._next, (
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
    if (range is Empty) {
      return _refuse('LMNL writes no empty element');
    }
    final name = '${range.get('')}';
    final said = stated(range.attributes);
    if (_unrepresentable(name, said) case final why?) {
      return _refuse(why);
    }
    final markup = switch (range) {
      Open() => _start(name, said),
      Close() => '{$name]',
      _ => null,
    };
    if (markup == null) {
      return _refuse('$range does not say what markup to write');
    }
    if (inside(document, range.start) case final token?) {
      return _refuse('${range.start} is inside $token');
    }
    return _rewrite(document, span(range.start, 0), markup, widen: false);
  }

  /// Makes the text [range] covers a comment.
  Result<Derivation<int>> _comment(Layered<int> document, ARange range) {
    for (final at in [range.start, range.end]) {
      if (inside(document, at) case final token?) {
        return _refuse('$at is inside $token');
      }
    }
    final content = covered(document, range);
    if (content.contains('--]')) {
      return _refuse('a comment cannot hold "--]"');
    }
    return _rewrite(document, range, '[!--$content--]', widen: false);
  }

  /// Takes the delimiters off the comment under [marker].
  Result<Derivation<int>> _uncomment(Layered<int> document, Marker marker) {
    final token = marked(document, 2, marker);
    if (token == null || '${token.get('')}' != '#comment') {
      return _refuse('only a comment is unmarked at layer 2; delete a tag');
    }
    return _rewrite(
      document,
      token,
      covered(document, span(token.start + 4, token.length - 7)),
    );
  }

  /// Gives the tag under [marker] the name and annotations in [attributes],
  /// keeping its marker: the name is changed in place where nothing else
  /// is, and the tag is written afresh where its annotations change.
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
    if (attributes.values.any((value) => value is! Str)) {
      return _refuse('an annotation in LMNL is text');
    }
    final name = '${attributes['']}';
    final said = stated(attributes);
    if (_unrepresentable(name, said) case final why?) {
      return _refuse(why);
    }
    final closing = document.items.item(token.start) == _brace;
    if (closing && said.isNotEmpty) {
      return _refuse('an end tag says nothing but its name');
    }
    final Range swapped;
    final String inner;
    if (closing ||
        same({...token.attributes}..remove(''), {...attributes}..remove(''))) {
      swapped = span(token.start + 1, old.runes.length);
      inner = name;
    } else {
      swapped = span(token.start + 1, token.length - 2);
      final written = _start(name, said);
      inner = written.substring(1, written.length - 1);
    }
    final rewritten = retagged(document, token, swapped, inner);
    final (end, _, read, problem) = _Grammar._next(rewritten, 0);
    if (problem != null || end != rewritten.length) {
      return _refuse('$rewritten is not a tag LMNL reads back whole');
    }
    return done(
      below: [Edit(1, Replace(swapped, Text.of(inner)))],
      updated: {
        marker: {'': literal(name), ...read},
      },
    );
  }

  /// Wraps the tokens [range] covers in a new element under [marker],
  /// whatever it crosses, unless a tag of its name stands among them.
  Result<Derivation<int>> _wrap(
    Layered<int> document,
    Marker marker,
    ARange range,
  ) {
    final tokens = document.span(2, range);
    if (tokens.length != range.length || range.get('') is! Str) {
      return _refuse('$range is not a new element over tokens');
    }
    final name = '${range.get('')}';
    final said = stated(range.attributes);
    if (_unrepresentable(name, said) case final why?) {
      return _refuse(why);
    }
    for (final (_, token) in tokens) {
      if ('${token.get('')}' == name) {
        return _refuse('a tag of $name inside $range would pair with it');
      }
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
  /// Always possible: a tag of its name between its own pairs within it.
  Result<Derivation<int>> _unwrap(Layered<int> document, Marker marker) {
    final element = marked(document, 3, marker);
    if (element == null) {
      return _refuse('$marker is not an element');
    }
    return done(
      below: [
        Edit(2, Delete(span(element.end - 1, 1))),
        Edit(2, Delete(span(element.start, 1))),
      ],
      removed: [marker],
    );
  }

  /// Renames the element under [marker] at both its tags, unless a tag of
  /// the new name stands inside it, and gives its start tag [attributes].
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
    final name = attributes['']!;
    for (final (_, token) in document.span(
      2,
      span(element.start + 1, element.length - 2),
    )) {
      if (token.get('') == name) {
        return _refuse('a tag of $name inside $element would pair with it');
      }
    }
    final tags = document.markers(2);
    return done(
      below: [
        Edit(2, Update(tags[element.end - 1].$1, {'': name})),
        Edit(2, Update(tags[element.start].$1, attributes)),
      ],
      updated: {marker: attributes},
    );
  }

  /// Deletes the elements at [indices] with what they hold, unless that
  /// would cut a tag away from the tag it pairs with.
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
    for (final (_, element) in elements) {
      final first = run.start <= element.start && element.start < run.end;
      final last = run.start < element.end && element.end <= run.end;
      if (first != last) {
        return _refuse('$indices cuts $element from one of its tags');
      }
    }
    // A tag that pairs with nothing is a diagnostic, which is not the
    // edit's to take away.
    for (final problem in document.diagnostics(3).items) {
      if (run.start <= problem.start && problem.start < run.end) {
        return _refuse('$indices holds a tag that pairs with nothing');
      }
    }
    return done(
      below: [Edit(2, Delete(run))],
      removed: [
        for (final (element, range) in elements)
          if (run.start <= range.start && range.end <= run.end) element,
      ],
    );
  }

  /// [run] of the text replaced with [text], read again by LMNL's scanner.
  Result<Derivation<int>> _rewrite(
    Layered<int> document,
    Range run,
    String text, {
    bool widen = true,
  }) => rewrite(document, run, text, _Grammar._next, 'lmnl', widen: widen);
}

/// Why [name] or one of [said]'s names cannot be represented in a tag, or null.
String? _unrepresentable(String name, Map<String, String> said) {
  if (!named(name)) {
    return '"$name" is not a name LMNL can represent';
  }
  for (final key in said.keys) {
    if (!named(key)) {
      return '"$key" is not an annotation name LMNL can represent';
    }
  }
  return null;
}

/// A start tag of [name] with [said] as its annotations.
String _start(String name, Map<String, String> said) {
  final written = StringBuffer('[$name');
  for (final MapEntry(:key, :value) in said.entries) {
    written.write(' [$key}$value{$key]');
  }
  written.write('}');
  return written.toString();
}

Result<Derivation<int>> _refuse(String why) => refuse('lmnl', why);
