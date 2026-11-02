/// What every importer shares: the content it read, in reading order, and
/// the ranges it found over that content, made into the LMNL document an
/// import gives.
library;

import 'package:libara/libara.dart';

import '../limits.dart';
import '../lmnl/lmnl.dart';
import '../rank.dart';

/// A range over an import's content, in code points: from [start] to [end],
/// named [name] and saying [said].
typedef Span = ({int start, int end, String name, Map<String, String> said});

/// The LMNL document holding [content] with each of [spans] a range over
/// it and each of [revisions] an annotation over its text, read within
/// [limits]; or a failure naming [syntax].
///
/// Spans may cross, which LMNL holds as they stand. They are placed by where
/// they start, the longer first, and in the order given where both agree.
///
/// A span named `li` saying `list`, `ul` or `ol`, is an item of that kind of
/// list, at the `level` it says, from 1; see [listed].
///
/// A revision is an annotation over layer 1 saying its name, such as `ins`
/// or `del`, and what it says: over the items that hold its characters in
/// the LMNL text, from its first to its last, tags between them included.
/// No grammar sees an annotation, so writing the document writes none, and
/// each moves with its characters through every edit.
Result<Layered<int>> assemble(
  String syntax,
  String content,
  List<Span> spans, {
  List<Span> revisions = const [],
  Limits limits = standard,
}) {
  final points = content.runes.length;
  final most = limits.items;
  if (most != null && points > most) {
    return Failure(
      Kind.invalid,
      '$syntax: $points characters exceed the limit of $most',
    );
  }
  for (final span in revisions) {
    if (span.start >= span.end) {
      return Failure(
        Kind.invalid,
        '$syntax: the revision ${span.name} at ${span.start} covers no '
        'characters',
      );
    }
  }
  for (final span in [...spans, ...revisions]) {
    if (span.end < span.start || span.start < 0) {
      return Failure(
        Kind.invalid,
        '$syntax: ${span.name} ends at ${span.end}, before it starts at '
        '${span.start}',
      );
    }
    if (span.end > points) {
      return Failure(
        Kind.invalid,
        '$syntax: ${span.name} ends at ${span.end}, past the content\'s '
        '$points characters',
      );
    }
  }
  final grouped = listed(spans);
  // Where each code point starts, in UTF-16 units, and where the last ends.
  final units = <int>[0];
  for (final point in content.runes) {
    units.add(units.last + (point > 0xFFFF ? 2 : 1));
  }
  // The edges: every place a span starts or ends, and the content's ends.
  final edges = {
    0,
    points,
    for (final span in grouped) ...[span.start, span.end],
  }.toList()..sort();
  final edge = {for (final (index, at) in edges.indexed) at: index};
  final ordered = grouped.indexed.toList()
    ..sort((one, other) {
      final (a, b) = (one.$2, other.$2);
      if (a.start != b.start) {
        return a.start - b.start;
      }
      final longer = (b.end - b.start) - (a.end - a.start);
      return longer != 0 ? longer : one.$1 - other.$1;
    });
  final written = sawtooth(
    content,
    [for (final at in edges) units[at]],
    [
      for (final (_, span) in ordered)
        (
          first: edge[span.start]!,
          last: edge[span.end]!,
          depth: 0,
          name: span.name,
          said: span.said,
        ),
    ],
  );
  return switch (written) {
    Failure(:final kind, :final message) => Failure(kind, '$syntax: $message'),
    Success(value: final text) => LMNL(
      limits: limits,
    ).decode(text).flatMap((document) => _revised(document, revisions)),
  };
}

/// [document] with each of [revisions], over its content, an annotation
/// over the items that hold those characters.
Result<Layered<int>> _revised(Layered<int> document, List<Span> revisions) {
  if (revisions.isEmpty) {
    return Success(document);
  }
  // Where each character of the content starts in the text, and where it
  // ends: a run of text holds its characters as they are, and an escape
  // holds the one it shows.
  final starts = <int>[];
  final ends = <int>[];
  for (final token in document.layer(2).items.cast<ARange>()) {
    if ('${token.get('')}' == '#text') {
      for (var at = token.start; at < token.end; at++) {
        starts.add(at);
        ends.add(at + 1);
      }
    } else if (token.get('shows') != null) {
      starts.add(token.start);
      ends.add(token.end);
    }
  }
  var noted = document;
  for (final revision in revisions) {
    final start = starts[revision.start];
    final range = ARange.create(
      start,
      ends[revision.end - 1] - start,
      attributes: {
        '': Str(Text.of(revision.name)),
        for (final MapEntry(:key, :value) in revision.said.entries)
          key: Str(Text.of(value)),
      },
    );
    final marked = range.flatMap(
      (range) => noted.apply(Edit.annotation(1, Mark(range))),
    );
    switch (marked) {
      case Failure(:final kind, :final message):
        return Failure(kind, message);
      case Success(:final value):
        noted = value.document;
    }
  }
  return Success(noted);
}

/// [spans] with their list items grouped into lists, whatever they are
/// spans over: the content's code points, or a document's tokens.
///
/// An item of a kind of list at a level is held, with the items of that
/// kind and level that follow it, by one span of that kind: following it
/// means that between the two there is nothing but items of a deeper level
/// and content no other block holds. Deeper items are a list of their own,
/// held by the item before them, which is stretched to hold it. An item
/// saying `id` runs together only with items saying the same. `list`,
/// `level` and `id` are taken off each item. The lists come first, so that a list
/// of one item holds it rather than the other way about.
List<Span> listed(List<Span> spans) {
  final items = [
    for (final (index, span) in spans.indexed)
      if (span.name == 'li' && span.said['list'] != null) index,
  ]..sort((one, other) => spans[one].start - spans[other].start);
  if (items.isEmpty) {
    return spans;
  }
  final others = [
    for (final (index, span) in spans.indexed)
      if (!items.contains(index) && block(span.name)) span,
  ];
  // Whether a block other than an item starts between [from] and [to].
  bool parted(int from, int to) =>
      others.any((other) => from <= other.start && other.start < to);
  final ends = {for (final index in items) index: spans[index].end};
  final lists = <Span>[];
  // The lists open, innermost last: each its kind, its level, where it
  // starts, its last item, and the item that holds it, if any.
  final open = <(String, int, int, int, int?)>[];
  void close() {
    final (key, _, start, last, holder) = open.removeLast();
    final end = ends[last]!;
    lists.add((
      start: start,
      end: end,
      name: key.split(' ').first,
      said: const {},
    ));
    if (holder != null && ends[holder]! < end) {
      ends[holder] = end;
    }
  }

  int? previous;
  for (final index in items) {
    final span = spans[index];
    // Items run together where they are of one kind and one list: an item
    // saying no `id` is of the one list of its kind.
    final kind = '${span.said['list']} ${span.said['id'] ?? ''}';
    final level = int.tryParse(span.said['level'] ?? '') ?? 1;
    if (previous != null && parted(ends[previous]!, span.start)) {
      while (open.isNotEmpty) {
        close();
      }
    }
    while (open.isNotEmpty && open.last.$2 > level) {
      close();
    }
    if (open.isNotEmpty && open.last.$2 == level && open.last.$1 != kind) {
      close();
    }
    if (open.isNotEmpty && open.last.$2 == level) {
      final (_, _, start, _, holder) = open.removeLast();
      open.add((kind, level, start, index, holder));
    } else {
      final holder = open.isEmpty ? null : open.last.$4;
      open.add((kind, level, span.start, index, holder));
    }
    previous = index;
  }
  while (open.isNotEmpty) {
    close();
  }
  return [
    ...lists,
    for (final (index, span) in spans.indexed)
      if (ends.containsKey(index))
        (
          start: span.start,
          end: ends[index]!,
          name: span.name,
          said: {
            for (final MapEntry(:key, :value) in span.said.entries)
              if (key != 'list' && key != 'level' && key != 'id') key: value,
          },
        )
      else
        span,
  ];
}
