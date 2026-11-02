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
import 'rank.dart';
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

/// A syntax whose tokens are not in the order its content is read, such as
/// one that stores its tables apart from the text that refers to them: a
/// document read in it is converted only by importing it, and the tree
/// writers and LMNL refuse it.
abstract interface class Linked {}

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
///
/// Where the element crossed another and was cut, so that a tree holds it,
/// it is several nodes, each a [piece] of the [pieces] it was cut into.
final class Node {
  /// [element], over the content from [start] to [end]: its [piece], in the
  /// order of the content, of [pieces], and the [join] its pieces share.
  Node(
    this.element,
    this.start,
    this.end, {
    this.piece = 0,
    this.pieces = 1,
    this.join = 0,
  });

  /// The element.
  final Placed element;

  /// Where its content starts.
  final int start;

  /// Where its content ends.
  final int end;

  /// Which piece of the element this is, counting from 0.
  final int piece;

  /// How many pieces the element was cut into: 1 where it was not cut.
  final int pieces;

  /// What the pieces of an element that was cut share, and no other
  /// element's do: the elements cut, counted from 1 in the order of their
  /// first pieces. 0 where the element was not cut.
  final int join;

  /// The elements it holds, in order.
  final List<Node> kids = [];

  /// The element's name.
  String get name => element.name;

  /// What the element says under [key], if anything.
  String? operator [](String key) => element.said[key];
}

/// A document's content and its elements as a tree.
typedef Tree = ({String content, List<Node> roots});

/// [document]'s content and its elements as a tree.
///
/// Where no element crosses another, each is one node, nested as
/// [structure] places it. Where some do, each is cut where it crosses one
/// placed before it, as [_split] places them.
Result<Tree> nodes(Layered<int> document, String syntax) {
  if (linked<Tree>(document, syntax) case final refusal?) {
    return refusal;
  }
  final (:content, :offsets, :elements) = projected(document);
  final roots = <Node>[];
  final open = <Node>[];
  for (final element in elements) {
    open.length = min(open.length, element.depth);
    if (open.isNotEmpty &&
        (open.last.element.last < element.last ||
            open.last.element.first > element.first)) {
      return Success((content: content, roots: _split(elements, offsets)));
    }
    final node = Node(element, offsets[element.first], offsets[element.last]);
    (open.isEmpty ? roots : open.last.kids).add(node);
    open.add(node);
  }
  return Success((content: content, roots: roots));
}

/// A refusal from [syntax] where [document] was read in a [Linked] syntax,
/// and otherwise nothing.
Failure<T>? linked<T>(Layered<int> document, String syntax) =>
    document.grammar is Linked
    ? Failure(
        Kind.invalid,
        '$syntax: the document is not stored in reading order; import it to '
        'convert it',
      )
    : null;

/// [elements], some of which cross, as a tree, with [offsets] where each
/// token's share of the content starts.
///
/// They are placed one at a time: blocks before inlines, then by their
/// first token, the longer first, then in the order given. Each goes down
/// to the deepest node that holds it; where it crosses a node already
/// placed, it is cut at that node's edge, and the piece within the node
/// placed inside it. A node placed is never cut again, so of a block and an
/// inline that cross the inline is cut, and of two of one rank the one that
/// starts later.
List<Node> _split(List<Placed> elements, List<int> offsets) {
  final order = [for (var index = 0; index < elements.length; index++) index]
    ..sort((one, other) {
      final (a, b) = (elements[one], elements[other]);
      final rank = (block(a.name) ? 0 : 1) - (block(b.name) ? 0 : 1);
      if (rank != 0) {
        return rank;
      }
      if (a.first != b.first) {
        return a.first - b.first;
      }
      final longer = (b.last - b.first) - (a.last - a.first);
      return longer != 0 ? longer : one - other;
    });
  final root = _Piece(-1, 0, offsets.length);
  final pieces = [for (final _ in elements) <_Piece>[]];
  for (final index in order) {
    final element = elements[index];
    _place(root, index, element.first, element.last, pieces);
  }
  // A piece's place among its element's, in the order of the content.
  final place = <_Piece, int>{};
  for (final made in pieces) {
    made.sort((one, other) => one.first - other.first);
    for (final (at, piece) in made.indexed) {
      place[piece] = at;
    }
  }
  // The elements cut, numbered in the order of their first pieces.
  final cut = [
    for (final (index, made) in pieces.indexed)
      if (made.length > 1) index,
  ]..sort((one, other) => pieces[one].first.first - pieces[other].first.first);
  final joins = {for (final (at, index) in cut.indexed) index: at + 1};
  List<Node> built(_Piece holder) => [
    for (final piece in holder.kids)
      Node(
        elements[piece.element],
        offsets[piece.first],
        offsets[piece.last],
        piece: place[piece]!,
        pieces: pieces[piece.element].length,
        join: joins[piece.element] ?? 0,
      )..kids.addAll(built(piece)),
  ];
  return built(root);
}

/// Places the piece of element [index] over tokens [first] to [last] in
/// [holder], which holds it, recording each piece it is cut into in
/// [pieces].
void _place(
  _Piece holder,
  int index,
  int first,
  int last,
  List<List<_Piece>> pieces,
) {
  final kids = holder.kids;
  // The kids are in order and do not cross, so their ends only rise: the
  // first that can touch the piece is found by halving.
  var start = 0;
  var end = kids.length;
  while (start < end) {
    final middle = (start + end) >> 1;
    if (kids[middle].last < first) {
      start = middle + 1;
    } else {
      end = middle;
    }
  }
  if (first == last) {
    // An empty piece goes inside a kid it stands within, and otherwise after
    // the empty kids standing where it does.
    while (start < kids.length && kids[start].first <= first) {
      final kid = kids[start];
      if (first < kid.last) {
        _place(kid, index, first, last, pieces);
        return;
      }
      start++;
    }
    final piece = _Piece(index, first, last);
    kids.insert(start, piece);
    pieces[index].add(piece);
    return;
  }
  bool touches(_Piece kid) => kid.first == kid.last
      ? first <= kid.first && kid.first < last
      : kid.first < last && first < kid.last;
  while (start < kids.length &&
      !touches(kids[start]) &&
      kids[start].first < last) {
    start++;
  }
  end = start;
  while (end < kids.length && touches(kids[end])) {
    end++;
  }
  var from = first;
  var to = last;
  // A kid the piece starts within: the part within it goes inside it.
  if (start < end && kids[start].first < from) {
    final kid = kids[start];
    if (to <= kid.last) {
      _place(kid, index, from, to, pieces);
      return;
    }
    _place(kid, index, from, kid.last, pieces);
    from = kid.last;
    start++;
  }
  // A kid the piece ends within: likewise.
  if (start < end && kids[end - 1].last > to) {
    final kid = kids[end - 1];
    _place(kid, index, kid.first, to, pieces);
    to = kid.first;
    end--;
  }
  if (from == to) {
    return;
  }
  // What is left covers its kids whole; one kid over all of it holds it,
  // since that kid was placed first.
  if (end - start == 1 && kids[start].first == from && kids[start].last == to) {
    _place(kids[start], index, from, to, pieces);
    return;
  }
  final piece = _Piece(index, from, to)..kids.addAll(kids.sublist(start, end));
  kids.replaceRange(start, end, [piece]);
  pieces[index].add(piece);
}

/// A piece of an element as [_split] places it: the element's index, the
/// tokens it covers, and the pieces it holds, in order.
final class _Piece {
  _Piece(this.element, this.first, this.last);

  final int element;
  final int first;
  final int last;
  final List<_Piece> kids = [];
}

/// [document] written as a tree of tags, as XML and HTML represent one, an
/// element nothing is written in ending as [empty] says, and the content
/// of one of [verbatim] as it stands.
///
/// Where [safe], what a browser would run is not written: an element it
/// would run is a `span`, and an attribute that would run is left out.
///
/// Where [marked], each piece of an element cut so that it nests says its
/// `part`, `initial`, `medial` or `final`, and the `join` its pieces share;
/// an element cut that already says either is refused, since the marks
/// would take its place.
Result<Sequence<int>> tree(
  Layered<int> document,
  String syntax, {
  required String Function(String name) empty,
  Set<String> verbatim = const {},
  bool safe = false,
  bool marked = false,
}) => nodes(document, syntax).flatMap((tree) {
  if (marked) {
    for (final node in _walked(tree.roots)) {
      for (final key in ['part', 'join']) {
        if (node.pieces > 1 && node.element.said.containsKey(key)) {
          return Failure(
            Kind.invalid,
            '$syntax: ${node.name} is cut so that it nests, and already says '
            '$key, which marks its pieces',
          );
        }
      }
    }
  }
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
      if (marked && node.pieces > 1) {
        final part = node.piece == 0
            ? 'initial'
            : node.piece == node.pieces - 1
            ? 'final'
            : 'medial';
        written.write(' part="$part" join="${node.join}"');
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
  return Success(Text.of(written.toString()) as Sequence<int>);
});

/// [roots] and every node they hold, in pre-order.
Iterable<Node> _walked(List<Node> roots) sync* {
  for (final node in roots) {
    yield node;
    yield* _walked(node.kids);
  }
}
