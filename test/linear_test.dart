@Tags(['perf'])
library;

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

/// Inputs that once cost the square of their size: each is timed at a size
/// and at four times it, where what is linear grows as its length does and
/// what is quadratic as the square of it.

/// The most the cost may grow, against how much the input's length grew.
const growth = 2.0;

/// The fewest microseconds of [doing], over a few rounds, so a pause in
/// the VM does not count.
int timed(void Function() doing) {
  var best = 1 << 62;
  for (var round = 0; round < 3; round += 1) {
    final watch = Stopwatch()..start();
    doing();
    watch.stop();
    if (watch.elapsedMicroseconds < best) {
      best = watch.elapsedMicroseconds;
    }
  }
  return best;
}

/// Checks that [doing] an input [made] of [size] grows with its length.
void linear(
  int size,
  String Function(int size) made,
  void Function(String) doing,
) {
  final small = made(size);
  final large = made(size * 4);
  doing(small);
  final ratio = timed(() => doing(large)) / timed(() => doing(small));
  final longer = large.length / small.length;
  expect(
    ratio / longer,
    lessThan(growth),
    reason: 'grew $ratio times over ${longer}x the length',
  );
}

void main() {
  test('Pasting many divs that never close', () {
    linear(4000, (size) => '<div>x' * size, Foreign.cleaned);
  });

  test('Marking emphasis in a long Markdown document', () {
    linear(1500, (size) => 'one two three\n\n' * size, (text) {
      final document = (const Markdown().decode(
        Text.of(text),
      ) as Success<Layered<int>>).value;
      expect(document.apply(Edit(2, Mark(Open(0, 'em')))), isA<Success>());
    });
  });

  test('Reading HTML blocks nested in many divs', () {
    // Past the depth a document is read with by default, so with none.
    linear(4000, (size) => '<div>' * size, (text) {
      expect(
        const HTML(limits: Limits()).decode(Text.of(text)),
        isA<Success>(),
      );
    });
  });

  test('Reading HTML that reopens many formatting elements', () {
    linear(
      1000,
      (size) => '<b x=i>' * size + '</p><p>x' * 200,
      (text) => expect(const HTML().decode(Text.of(text)), isA<Success>()),
    );
  });

  for (final opener in [r'\( ', r'\foo[ ']) {
    test('Reading LaTeX with many an unclosed $opener', () {
      linear(2000, (size) => '$opener x ' * size, (text) {
        expect(const LaTeX().decode(Text.of(text)), isA<Success>());
      });
    });
  }

  for (final escape in [r'\[x', r'\f[B']) {
    test('Reading roff with many an unclosed $escape', () {
      linear(4000, (size) => 'words $escape here\n' * size, (text) {
        expect(const Man().decode(Text.of(text)), isA<Success>());
      });
    });
  }

  test('Opening a roff container at the head of many paragraphs', () {
    linear(500, (size) => '.PP\nwords\n' * size, (text) {
      final document =
          (const Man().decode(Text.of(text)) as Success<Layered<int>>).value;
      expect(
        document.apply(Edit(1, Insert(0, Text.of('.RS\n')))),
        isA<Success>(),
      );
    });
  });

  Result<Layered<int>> markdown(String text) =>
      const Markdown().decode(Text.of(text));

  test('Reading a Markdown paragraph of many links', () {
    linear(2000, (size) => '[a](b) ' * size, (text) {
      expect(markdown(text), isA<Success>());
    });
  });

  test('Reading a Markdown paragraph of backtick runs that never close', () {
    // Runs of every length, so that no two close each other.
    linear(
      200,
      (size) => [for (var run = 1; run <= size; run++) '`' * run].join(' x '),
      (text) => expect(markdown(text), isA<Success>()),
    );
  });

  test('Reading Markdown brackets that open links never made', () {
    linear(2000, (size) => '[a ' * size + '[b](c)' * size, (text) {
      expect(markdown(text), isA<Success>());
    });
  });
}
