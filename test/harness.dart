/// What every syntax's tests hold it to: that a text comes back as it went
/// in, that an edited document has the layers a fresh read of its text
/// would have, and that its elements nest as a reference parser says.
library;

import 'dart:math';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

/// The value of [result], failing the test on a failure.
T value<T>(Result<T> result) => switch (result) {
  Success(:final value) => value,
  Failure(:final kind, :final message) => fail('$kind: $message'),
};

/// [text] as [syntax] reads it.
Layered<int> decoded(Syntax syntax, String text) =>
    value(syntax.decode(Text.of(text)));

/// [items] as a Dart string.
String string(Sequence<int> items) => String.fromCharCodes(items.items);

/// What [document] derived above layer 1, as text to compare: each layer's
/// ranges and diagnostics, sorted, since two ranges over one extent may come
/// in either order.
List<String> layers(Layered<int> document) => [
  for (var layer = 2; layer <= document.depth; layer++) ...[
    'layer $layer: ${_sorted(document.layer(layer))}',
    'diagnostics $layer: ${_sorted(document.diagnostics(layer))}',
  ],
];

List<String> _sorted(Ranges ranges) =>
    [for (final range in ranges.items) '$range']..sort();

/// That [syntax] writes [text] back exactly as it read it.
void roundtrip(Syntax syntax, String text) {
  expect(string(value(syntax.encode(decoded(syntax, text)))), text);
}

/// That after each of [edits] random insertions and deletions, the layers
/// [syntax] derived again over the region an edit touched are the layers a
/// fresh read of the edited text gives.
///
/// What is inserted is cut from [text] itself, so the edits carry the
/// syntax's own markup, half tags and all, rather than letters that never
/// disturb a token.
void derivable(
  Syntax syntax,
  String text, {
  required int seed,
  int edits = 200,
}) {
  final random = Random(seed);
  final source = text.runes.toList();
  var document = decoded(syntax, text);
  for (var step = 0; step < edits; step++) {
    final length = document.items.length;
    final Command<int> command;
    if (length == 0 || random.nextBool()) {
      final start = source.isEmpty ? 0 : random.nextInt(source.length);
      final end = min(source.length, start + random.nextInt(9));
      command = Insert(
        random.nextInt(length + 1),
        Text.of(String.fromCharCodes(source, start, end)),
      );
    } else {
      final start = random.nextInt(length);
      command = Delete(
        value(Range.create(start, min(length - start, 1 + random.nextInt(8)))),
      );
    }
    document = value(document.apply(Edit(1, command))).document;
    expect(
      layers(document),
      layers(decoded(syntax, string(document.items))),
      reason: 'seed $seed, step $step, after $command',
    );
  }
}

/// [document]'s layer-3 elements in pre-order, each as its depth and its
/// name, under the `#document` that is the whole layer, to set beside a
/// reference parser's tree written the same way.
///
/// Elements are ranges over layer-2 tokens, so one holds another when it
/// covers the other's tokens; the longer of two with one start holds the
/// shorter.
List<String> preorder(Layered<int> document) {
  final elements = document.layer(3).items.cast<ARange>().toList()
    ..sort(
      (one, other) => one.start != other.start
          ? one.start.compareTo(other.start)
          : other.length.compareTo(one.length),
    );
  final open = <Range>[];
  final order = ['0:#document'];
  for (final element in elements) {
    while (open.isNotEmpty && open.last.end <= element.start) {
      open.removeLast();
    }
    order.add('${open.length + 1}:${element.get('')}');
    open.add(element);
  }
  return order;
}

/// That [document]'s elements nest as [reference], a pre-order list of
/// `depth:name` that a reference parser gave for the same text.
void isomorphic(List<String> reference, Layered<int> document) {
  expect(preorder(document), reference);
}

/// [document]'s layer-3 elements in pre-order, each with the text it
/// covers, which is that of the tokens from its first to its last.
List<(ARange, String)> covering(Layered<int> document) {
  final tokens = document.layer(2).items.cast<ARange>().toList();
  final ordered = document.layer(3).items.cast<ARange>().toList()
    ..sort(
      (one, other) => one.start != other.start
          ? one.start.compareTo(other.start)
          : other.length.compareTo(one.length),
    );
  return [
    for (final element in ordered)
      (
        element,
        element.length == 0
            ? ''
            : string(
                document.slice(
                  value(
                    Range.create(
                      tokens[element.start].start,
                      tokens[element.end - 1].end - tokens[element.start].start,
                    ),
                  ),
                ),
              ),
      ),
  ];
}

/// [document]'s layer-2 tokens in order, each as its name and the text it
/// covers.
List<(String, String)> tokens(Layered<int> document) => [
  for (final range in document.layer(2).items)
    ('${(range as ARange).get('')}', string(document.slice(range))),
];

/// [document]'s layer-2 token starting at [start], in code points.
ARange token(Layered<int> document, int start) =>
    document.layer(2).items.firstWhere((range) => range.start == start)
        as ARange;

/// What [range] says under [key], as text, or null where it says nothing.
String? said(ARange range, String key) => range.get(key)?.toString();

/// The messages of [document]'s diagnostics at [layer], in order.
List<String> problems(Layered<int> document, int layer) => [
  for (final range in document.diagnostics(layer).items)
    '${(range as ARange).get('message')}',
];

/// [document] after the structural [edit], having checked that its layers
/// are what a fresh read of its text gives.
Layered<int> edited(Syntax syntax, Layered<int> document, Edit<int> edit) {
  final next = value(document.apply(edit)).document;
  expect(
    layers(next),
    layers(decoded(syntax, string(next.items))),
    reason: 'after $edit',
  );
  return next;
}

/// That [syntax] refuses the structural [edit] of [document], saying a
/// reason that contains [why].
void refused(Layered<int> document, Edit<int> edit, String why) {
  expect(
    document.apply(edit),
    isA<Failure<Object?>>()
        .having((failure) => failure.kind, 'kind', Kind.invalid)
        .having((failure) => failure.message, 'message', contains(why)),
  );
}

/// The marker of [document]'s element called [name], the [nth] of them in
/// start order, the longer first where two start together.
Marker element(Layered<int> document, String name, [int nth = 0]) {
  final named =
      [
        for (final pair in document.markers(3))
          if (said(pair.$2, '') == name) pair,
      ]..sort(
        (one, other) => one.$2.start != other.$2.start
            ? one.$2.start.compareTo(other.$2.start)
            : other.$2.length.compareTo(one.$2.length),
      );
  return named[nth].$1;
}

/// [document]'s element under [marker].
ARange marked(Layered<int> document, Marker marker) =>
    document.markers(3).firstWhere((pair) => pair.$1 == marker).$2;

/// A new range saying [attributes] over [length] items from [start].
ARange over(int start, int length, Map<String, String> attributes) => value(
  ARange.create(
    start,
    length,
    attributes: {
      for (final MapEntry(:key, :value) in attributes.entries)
        key: Str(Text.of(value)),
    },
  ),
);

/// The index of [document]'s token covering exactly [words].
int at(Layered<int> document, String words) =>
    tokens(document).indexWhere((token) => token.$2 == words);

/// The marker of [document]'s range at [layer] that [test] picks.
Marker marker(Layered<int> document, int layer, bool Function(ARange) test) =>
    document.markers(layer).firstWhere((pair) => test(pair.$2)).$1;

/// That after each of [edits] random structural edits that [made] proposes
/// for the current document, the document is either unchanged, where the
/// syntax refused it with [Kind.invalid], or has the layers a fresh read of
/// its text gives.
void structural(
  Syntax syntax,
  String text,
  Edit<int>? Function(Layered<int> document, Random random) made, {
  required int seed,
  int edits = 200,
}) {
  final random = Random(seed);
  var document = decoded(syntax, text);
  for (var step = 0; step < edits; step++) {
    final edit = made(document, random);
    if (edit == null) {
      continue;
    }
    switch (document.apply(edit)) {
      case Failure(:final kind, :final message):
        expect(kind, Kind.invalid, reason: 'seed $seed, step $step: $message');
      case Success(:final value):
        document = value.document;
        expect(
          layers(document),
          layers(decoded(syntax, string(document.items))),
          reason: 'seed $seed, step $step, after $edit',
        );
    }
  }
}
