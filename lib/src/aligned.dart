/// A stretch of text written again as the fewest edits that make it, so
/// that what the old and new texts share stands, and whatever is marked
/// over it, an annotation among them, keeps it.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:libara/libara.dart';

import 'lexing.dart';

/// The layer-1 edits that write [written] in place of [stretch] of
/// [document]'s text: what the two share is left standing, and what lies
/// between is taken, put in or replaced, from the end back, so each edit's
/// positions are the text's as it was. One replacement where they share
/// nothing, where they are the same, or where the alignment would take more
/// than [_most] steps.
List<Edit<int>> replaced(Layered<int> document, Range stretch, String written) {
  final now = written.runes.toList();
  final runs = _aligned(document.slice(stretch).items.toList(), now);
  final edits = <Edit<int>>[];
  var (old, next) = (0, 0);
  for (final (from, to, length) in runs) {
    final (taken, put) = (from - old, to - next);
    if (taken > 0 || put > 0) {
      final at = stretch.start + old;
      final items = Text.of(String.fromCharCodes(now.sublist(next, to)));
      edits.add(
        Edit(
          1,
          put == 0
              ? Delete(span(at, taken))
              : taken == 0
              ? Insert(at, items)
              : Replace(span(at, taken), items),
        ),
      );
    }
    (old, next) = (from + length, to + length);
  }
  return edits.isEmpty
      ? [Edit(1, Replace(stretch, Text.of(written)))]
      : edits.reversed.toList();
}

/// Where [old] and [now] agree: runs of equal items, each as where it
/// starts in each and how long it is, in order, ending with an empty run at
/// both their ends. A Myers diff between their common start and end.
List<(int, int, int)> _aligned(List<int> old, List<int> now) {
  var head = 0;
  while (head < old.length && head < now.length && old[head] == now[head]) {
    head++;
  }
  var tail = 0;
  while (tail < old.length - head &&
      tail < now.length - head &&
      old[old.length - 1 - tail] == now[now.length - 1 - tail]) {
    tail++;
  }
  final a = old.sublist(head, old.length - tail);
  final b = now.sublist(head, now.length - tail);
  final runs = <(int, int, int)>[if (head > 0) (0, 0, head)];
  for (final (x, y, length) in _myers(a, b)) {
    runs.add((head + x, head + y, length));
  }
  if (tail > 0) {
    runs.add((old.length - tail, now.length - tail, tail));
  }
  runs.add((old.length, now.length, 0));
  return runs;
}

/// The runs of equal items along a shortest edit from [a] to [b], each as
/// where it starts in each and how long it is; none where the edit would
/// take more than [_most] steps, the whole being taken as replaced.
List<(int, int, int)> _myers(List<int> a, List<int> b) {
  final n = a.length;
  final m = b.length;
  if (n == 0 || m == 0) {
    return const [];
  }
  final most = min(n + m, _most);
  // The furthest x reached on each diagonal k, from -d to d, kept for every
  // step so the path can be found again backwards.
  final trace = <Int32List>[];
  var frontier = Int32List(3);
  var found = -1;
  for (var d = 0; d <= most && found < 0; d++) {
    // frontier holds diagonals -(d+1)..(d+1) of the step before.
    final next = Int32List(2 * d + 5);
    int at(int k) => frontier[k + d + 1];
    for (var k = -d; k <= d; k += 2) {
      var x = k == -d || (k != d && at(k - 1) < at(k + 1))
          ? at(k + 1)
          : at(k - 1) + 1;
      var y = x - k;
      while (x < n && y < m && a[x] == b[y]) {
        x++;
        y++;
      }
      next[k + d + 2] = x;
      if (x >= n && y >= m) {
        found = d;
        break;
      }
    }
    trace.add(frontier);
    frontier = next;
  }
  if (found < 0) {
    return const [];
  }
  final runs = <(int, int, int)>[];
  var x = n;
  var y = m;
  for (var d = found; d > 0; d--) {
    final held = trace[d];
    int at(int k) => held[k + d + 1];
    final k = x - y;
    final down = k == -d || (k != d && at(k - 1) < at(k + 1));
    final previous = down ? k + 1 : k - 1;
    final px = at(previous);
    final py = px - previous;
    final sx = down ? px : px + 1;
    final sy = sx - k;
    if (x > sx) {
      runs.add((sx, sy, x - sx));
    }
    x = px;
    y = py;
  }
  if (x > 0) {
    runs.add((0, 0, x));
  }
  return runs.reversed.toList();
}

/// The most steps an alignment may take: more than any rewriting of an
/// element's markup, and few enough that the frontiers kept, which grow as
/// the square of the steps, stay at a few megabytes.
const _most = 1024;
