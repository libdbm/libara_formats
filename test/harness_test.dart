import 'package:libara/libara.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// A toy syntax for holding the harness to: parentheses group, and
/// everything between them is text. Each switch breaks it in one way the
/// harness is meant to catch.
final class Groups implements Syntax {
  const Groups({this.narrow = false, this.lossy = false});

  /// Re-derives tokens only over the changed items, so text typed beside a
  /// run is not joined to it.
  final bool narrow;

  /// Writes the text back short of its last character.
  final bool lossy;

  @override
  Result<Layered<int>> decode(Sequence<int> form) =>
      Layered.of(form, _Grammar(narrow));

  @override
  Result<Sequence<int>> encode(Layered<int> value) {
    final items = value.items;
    return Success(
      lossy && items.length > 0 ? items.slice(0, items.length - 1) : items,
    );
  }
}

final class _Grammar implements Grammar<int> {
  const _Grammar(this.narrow);

  final bool narrow;

  @override
  int get depth => 3;

  @override
  Derived derive(Layered<int> document, int layer, Range region) =>
      layer == 2 ? _tokens(document, region) : _groups(document);

  @override
  Range affected(Layered<int> document, int layer, Range changed) =>
      narrow && layer == 2
      ? changed
      : value(
          Range.create(
            0,
            layer == 2 ? document.items.length : document.layer(2).length,
          ),
        );

  @override
  Result<Derivation<int>> edit(Layered<int> document, Edit<int> change) =>
      const Failure(Kind.invalid, 'groups: no structural edits');

  static const _open = 0x28;
  static const _close = 0x29;

  Derived _tokens(Layered<int> document, Range region) {
    final ranges = <ARange>[];
    var run = region.start;
    for (var at = region.start; at < region.end; at++) {
      final point = document.items.item(at);
      if (point == _open || point == _close) {
        if (run < at) {
          ranges.add(_named(run, at - run, '#text'));
        }
        ranges.add(_named(at, 1, 'group'));
        run = at + 1;
      }
    }
    if (run < region.end) {
      ranges.add(_named(run, region.end - run, '#text'));
    }
    return (ranges: ranges, diagnostics: const []);
  }

  Derived _groups(Layered<int> document) {
    final tokens = document.layer(2).items.toList();
    final ranges = <ARange>[];
    final diagnostics = <ARange>[];
    final open = <int>[];
    for (var index = 0; index < tokens.length; index++) {
      final point = document.items.item(tokens[index].start);
      if (point == _open) {
        open.add(index);
      } else if (point == _close) {
        if (open.isEmpty) {
          diagnostics.add(_message(index, 'nothing to close'));
        } else {
          final start = open.removeLast();
          ranges.add(_named(start, index - start + 1, 'group'));
        }
      }
    }
    for (final index in open) {
      diagnostics.add(_message(index, 'never closed'));
    }
    return (ranges: ranges, diagnostics: diagnostics);
  }

  static ARange _named(int start, int length, String name) =>
      ARange.from(value(Range.create(start, length)), {'': Str(Text.of(name))});

  static ARange _message(int index, String message) => ARange.from(
    value(Range.create(index, 1)),
    {'message': Str(Text.of(message))},
  );

  @override
  Result<Change<int>> valid(Layered<int> document, Edit<int> change) =>
      document.apply(change);

  @override
  List<int> escaped(List<int> text, {bool raw = false}) => text;

  @override
  Crossing crossing(Layered<int> document, int layer, ARange range) =>
      Crossing.refuse;
}

void main() {
  const text = 'a(b(c)d)e(f)g';

  test('roundtrip passes a faithful syntax', () {
    roundtrip(const Groups(), text);
  });

  test('roundtrip catches a syntax that loses a character', () {
    expect(
      () => roundtrip(const Groups(lossy: true), text),
      throwsA(isA<TestFailure>()),
    );
  });

  test('derivable passes a syntax that derives over enough', () {
    derivable(const Groups(), text, seed: 1);
  });

  test('derivable catches a syntax that derives over too little', () {
    expect(
      () => derivable(const Groups(narrow: true), text, seed: 1),
      throwsA(isA<TestFailure>()),
    );
  });

  test('preorder nests elements by the tokens they cover', () {
    expect(preorder(decoded(const Groups(), text)), [
      '0:#document',
      '1:group',
      '2:group',
      '1:group',
    ]);
  });

  test('isomorphic catches elements nested differently', () {
    expect(
      () => isomorphic([
        '0:#document',
        '1:group',
        '1:group',
        '1:group',
      ], decoded(const Groups(), text)),
      throwsA(isA<TestFailure>()),
    );
  });
}
