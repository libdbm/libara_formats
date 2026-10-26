/// The html5lib tree-construction cases in `test/html5lib/`, read from
/// their `.dat` format.
library;

import 'dart:io';

/// One case: where it comes from, what is parsed, and the elements the
/// standard builds, in pre-order as `depth:name` under `0:#document`.
typedef Case = ({
  String file,
  int number,
  String data,
  List<String> elements,
  bool fragment,
  bool scripted,
  bool foreign,
});

/// Whether [file] needs a script run to say what it builds.
bool scripting(String file) => file.startsWith('scripted_');

/// Every case in every file.
List<Case> cases() => [
  for (final file
      in Directory('test/html5lib').listSync().whereType<File>().toList()
        ..sort((one, other) => one.path.compareTo(other.path)))
    if (file.path.endsWith('.dat')) ..._read(file),
];

List<Case> _read(File file) {
  final name = file.uri.pathSegments.last;
  final found = <Case>[];
  final lines = file.readAsLinesSync();
  var at = 0;
  var number = 0;
  while (at < lines.length) {
    if (lines[at] != '#data') {
      at++;
      continue;
    }
    at++;
    final data = <String>[];
    while (at < lines.length && !lines[at].startsWith('#')) {
      data.add(lines[at]);
      at++;
    }
    var fragment = false;
    var scripted = true;
    final tree = <String>[];
    while (at < lines.length && lines[at] != '#data') {
      final line = lines[at];
      if (line.startsWith('#document-fragment')) {
        fragment = true;
      } else if (line == '#script-off') {
        scripted = false;
      } else if (line == '#document') {
        at++;
        // A text node holding a line end runs on to lines without the
        // bar, which belong to it.
        while (at < lines.length &&
            lines[at] != '#data' &&
            (lines[at].startsWith('|') || !lines[at].startsWith('#'))) {
          if (lines[at].startsWith('|')) {
            tree.add(lines[at]);
          }
          at++;
        }
        continue;
      }
      at++;
    }
    final (elements, foreign) = _elements(tree);
    found.add((
      file: name,
      number: number++,
      data: data.join('\n'),
      elements: elements,
      fragment: fragment,
      scripted: scripted,
      foreign: foreign,
    ));
  }
  return found;
}

/// The elements of a `#document` tree, the children of a template's
/// `content` taken to be the template's own; and whether any is SVG or
/// MathML.
(List<String>, bool) _elements(List<String> tree) {
  final order = ['0:#document'];
  var foreign = false;
  // The depths of the `content` lines open, each lifting what is below it.
  final contents = <int>[];
  for (final line in tree) {
    final body = line.substring(2);
    final depth = (body.length - body.trimLeft().length) ~/ 2;
    final text = body.trimLeft();
    while (contents.isNotEmpty && depth <= contents.last) {
      contents.removeLast();
    }
    if (text == 'content') {
      contents.add(depth);
      continue;
    }
    if (!text.startsWith('<') ||
        !text.endsWith('>') ||
        text.startsWith('<!--') ||
        text.startsWith('<!DOCTYPE') ||
        text.startsWith('<?')) {
      continue;
    }
    final name = text.substring(1, text.length - 1);
    if (name.startsWith('svg ') || name.startsWith('math ')) {
      foreign = true;
    }
    order.add('${depth - contents.length + 1}:$name');
  }
  return (order, foreign);
}
