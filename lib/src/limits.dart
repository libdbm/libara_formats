import 'package:libara/libara.dart';

/// What a syntax reads unless it is told otherwise: room for a book many
/// times over, and a bound on what a hostile file can make it build.
const standard = Limits(
  items: 16 * 1024 * 1024,
  markers: 1000000,
  depth: 4096,
  attributes: 1024,
);

/// The diagnostic saying [message] over [range], which a cap reached: the
/// work stopped there, and [bounded] refuses what is read with one.
ARange limited(Range range, String message) => ARange.from(range, {
  'message': Str(Text.of(message)),
  'limit': const Bool(true),
});

/// [document], or a failure where reading it reached a cap.
Result<Layered<int>> bounded(String syntax, Layered<int> document) {
  for (var layer = 2; layer <= document.depth; layer++) {
    for (final problem in document.diagnostics(layer).items) {
      final range = problem as ARange;
      if (range.get('limit') == const Bool(true)) {
        return Failure(Kind.invalid, '$syntax: ${range.get('message')}');
      }
    }
  }
  return Success(document);
}

/// [form] read by [grammar] for [syntax], its ranges saying one of
/// [indexed] found by key, or a failure where it holds more items than
/// [limits] allow or reading it reached a cap.
Result<Layered<int>> decoded(
  String syntax,
  Grammar<int> grammar,
  Limits limits,
  Sequence<int> form, {
  Iterable<String> indexed = const [],
}) {
  final most = limits.items;
  if (most != null && form.length > most) {
    return Failure(
      Kind.invalid,
      '$syntax: ${form.length} characters exceed the limit of $most',
    );
  }
  return Layered.of(
    form,
    grammar,
    indexed: indexed,
  ).flatMap((document) => bounded(syntax, document));
}

/// [form], or a [Kind.syntax] failure naming [syntax] and the first item
/// that is not a byte, 0 to 255: what a syntax reading a file's bytes is
/// given, so that text decoded by mistake is refused at once.
Result<Sequence<int>> bytes(String syntax, Sequence<int> form) {
  var position = 0;
  for (final item in form.items) {
    if (item < 0 || item > 255) {
      return Failure(
        Kind.syntax,
        '$syntax: item $item at $position is not a byte',
      );
    }
    position++;
  }
  return Success(form);
}
