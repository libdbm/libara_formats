/// What every syntax's `encode` reads off a document read in another: its
/// content, and its elements placed over that content.
///
/// Layer 2 tiles the text in every syntax, so the content is read off the
/// tokens alone: a run of `#text` is content as it stands, a token saying
/// what it `shows` leaves that behind, such as a reference or an escape, an
/// element whose content HTML reads as it stands leaves what its tags hold,
/// and the rest of the markup leaves nothing.
library;

import 'dart:math';

import 'package:libara/libara.dart';

import 'lexing.dart';
import 'safety.dart';
import 'tags.dart' show escaped;

/// An element of a document: the tokens it spans, from [first] up to
/// [last], how many elements hold it, its name, and what it says.
typedef Placed = ({
  int first,
  int last,
  int depth,
  String name,
  Map<String, String> said,
});

/// A syntax whose elements can tie, an implied one covering what it
/// holds, which says how they nest.
abstract interface class Nesting {
  /// [document]'s elements in pre-order, each with how many hold it.
  List<(ARange, int)> nesting(Layered<int> document);
}

/// An element of a version as its structure places it: its [marker], the
/// [element] it is in layer 3, over the tokens, how many elements hold it,
/// its [depth], and the stretch of the text its tokens cover, its
/// [extent], in code points.
typedef Nested = ({Marker marker, ARange element, int depth, Range extent});

/// [document]'s elements in pre-order, each with its depth and its stretch
/// of the text.
///
/// Where the syntax says how its elements nest, as HTML's tree construction
/// does for elements that tie or that it implied, that is the order;
/// elsewhere the longer of two that start together holds the other, and of
/// two alike the first read does. An element of no tokens stands, empty,
/// where its place among the tokens is.
List<Nested> structure(Layered<int> document) {
  final markers = document.markers(3);
  final List<(ARange, int)> ordered;
  if (document.grammar case final Nesting syntax) {
    ordered = syntax.nesting(document);
  } else {
    final sorted =
        [for (final (_, element) in markers) element].indexed.toList()..sort(
          (one, other) => one.$2.start != other.$2.start
              ? one.$2.start.compareTo(other.$2.start)
              : one.$2.end != other.$2.end
              ? other.$2.end.compareTo(one.$2.end)
              : one.$1.compareTo(other.$1),
        );
    final open = <ARange>[];
    ordered = [];
    for (final (_, element) in sorted) {
      // An empty element holds nothing, and one that has ended no more.
      while (open.isNotEmpty &&
          (open.last.length == 0 || open.last.end <= element.start)) {
        open.removeLast();
      }
      ordered.add((element, open.length));
      open.add(element);
    }
  }
  // Each element's marker, found by the element it marks; two alike take
  // theirs in the order they stand.
  final marked = <ARange, List<Marker>>{};
  for (final (marker, element) in markers.reversed) {
    (marked[element] ??= []).add(marker);
  }
  final tokens = document.layer(2).items.cast<ARange>().toList();
  final length = document.items.length;
  int start(int index) => index < tokens.length ? tokens[index].start : length;
  return [
    for (final (element, depth) in ordered)
      if (start(element.start) case final first)
        (
          marker: marked[element]!.removeLast(),
          element: element,
          depth: depth,
          extent: span(
            first,
            (element.length == 0 ? first : tokens[element.end - 1].end) - first,
          ),
        ),
  ];
}

/// [document]'s content; where each token's share of it starts, and where
/// the last ends; and its elements in pre-order, as [structure] places them.
({String content, List<int> offsets, List<Placed> elements}) projected(
  Layered<int> document,
) {
  final points = document.items.items.toList();
  final content = StringBuffer();
  final offsets = <int>[];
  for (final token in document.layer(2).items.cast<ARange>()) {
    offsets.add(content.length);
    final words = String.fromCharCodes(points, token.start, token.end);
    final name = '${token.get('')}';
    if (name == prose) {
      content.write(words);
    } else if (token.get('shows') case final Str shows) {
      content.write(shows.value);
    } else if (!name.startsWith('#')) {
      content.write(_held(words));
    }
  }
  offsets.add(content.length);
  final ordered = [
    for (final one in structure(document)) (one.element, one.depth),
  ];
  return (
    content: content.toString(),
    offsets: offsets,
    elements: [
      for (final (element, depth) in ordered)
        (
          first: element.start,
          last: element.end,
          depth: depth,
          name: '${element.get('')}',
          said: stated(element.attributes),
        ),
    ],
  );
}

/// What a tag token holds after its start tag and before its end tag,
/// which only an element HTML reads as it stands, such as a `script`, has.
String _held(String words) {
  if (!words.startsWith('<')) {
    return '';
  }
  int? quote;
  for (var at = 1; at < words.length; at++) {
    final unit = words.codeUnitAt(at);
    if (quote != null) {
      if (unit == quote) {
        quote = null;
      }
    } else if (unit == 0x22 || unit == 0x27) {
      quote = unit;
    } else if (unit == 0x3E) {
      final rest = words.substring(at + 1);
      final end = rest.lastIndexOf('</');
      return end < 0 ? rest : rest.substring(0, end);
    }
  }
  return '';
}

/// An element as a writer walks it: the element, where its content starts
/// and ends, in UTF-16 units of [Tree.content], and the elements it holds.
final class Node {
  /// [element], over the content from [start] to [end].
  Node(this.element, this.start, this.end);

  /// The element.
  final Placed element;

  /// Where its content starts.
  final int start;

  /// Where its content ends.
  final int end;

  /// The elements it holds, in order.
  final List<Node> kids = [];

  /// The element's name.
  String get name => element.name;

  /// What the element says under [key], if anything.
  String? operator [](String key) => element.said[key];
}

/// A document's content and its elements as a tree.
typedef Tree = ({String content, List<Node> roots});

/// [document]'s content and its elements as a tree, or a refusal from
/// [syntax] where two elements overlap, which no tree holds.
Result<Tree> nodes(Layered<int> document, String syntax) {
  final (:content, :offsets, :elements) = projected(document);
  final roots = <Node>[];
  final open = <Node>[];
  for (final element in elements) {
    open.length = min(open.length, element.depth);
    if (open.isNotEmpty &&
        (open.last.element.last < element.last ||
            open.last.element.first > element.first)) {
      return Failure(
        Kind.invalid,
        '$syntax: ${open.last.name} and ${element.name} are overlapping '
        'elements, which $syntax cannot nest',
      );
    }
    final node = Node(element, offsets[element.first], offsets[element.last]);
    (open.isEmpty ? roots : open.last.kids).add(node);
    open.add(node);
  }
  return Success((content: content, roots: roots));
}

/// [document] written as a tree of tags, as XML and HTML represent one, an
/// element nothing is written in ending as [empty] says, and the content
/// of one of [verbatim] as it stands; or a refusal from [syntax] where two
/// elements overlap.
///
/// Where [safe], what a browser would run is not written: an element it
/// would run is a `span`, and an attribute that would run is left out.
Result<Sequence<int>> tree(
  Layered<int> document,
  String syntax, {
  required String Function(String name) empty,
  Set<String> verbatim = const {},
  bool safe = false,
}) => nodes(document, syntax).map((tree) {
  final written = StringBuffer();
  void walk(int start, int end, List<Node> kids, bool raw) {
    var at = start;
    void words(int to) {
      final run = tree.content.substring(at, to);
      written.write(raw ? run : escaped(run));
    }

    for (final node in kids) {
      words(node.start);
      final name = safe && active.contains(node.name) ? 'span' : node.name;
      written.write('<$name');
      for (final MapEntry(:key, :value) in node.element.said.entries) {
        if (!safe || !handles(key, value)) {
          written.write(' $key="${escaped(value)}"');
        }
      }
      if (node.start == node.end && node.kids.isEmpty) {
        written.write(empty(name));
      } else {
        written.write('>');
        walk(node.start, node.end, node.kids, verbatim.contains(name));
        written.write('</$name>');
      }
      at = node.end;
    }
    words(end);
  }

  walk(0, tree.content.length, tree.roots, false);
  return Text.of(written.toString()) as Sequence<int>;
});
