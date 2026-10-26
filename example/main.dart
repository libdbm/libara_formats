// Reads a Markdown document, edits it, and writes it as XML and LaTeX,
// using only the public API.
// ignore_for_file: avoid_print

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';

void main() {
  final markdown = formats['md']!;
  final read = markdown.decode(Text.of('# Notes\n\nA quick fox.\n'));
  if (read case Failure(:final message)) {
    print('not read: $message');
    return;
  }
  var document = (read as Success<Layered<int>>).value;

  // Layer 1 is the text, layer 2 its tokens, layer 3 its elements.
  for (final (_, element) in document.markers(3)) {
    print('element ${element.get('')} over tokens $element');
  }

  // A keystroke: text typed at layer 1, the layers above read again.
  document = applied(document, Edit(1, Insert(11, Text.of('brown '))));

  // A structural edit: emphasis around "brown", asked for at layer 2 as a
  // close and an open, each written as Markdown represents it.
  document = applied(document, Edit(2, Mark(Close(16, 'em'))));
  document = applied(document, Edit(2, Mark(Open(11, 'em'))));
  print('markdown: ${text(markdown.encode(document))}');

  // Conversion: the same document written in other syntaxes.
  print('xml:      ${text(formats['xml']!.encode(document))}');
  print('latex:\n${text(formats['tex']!.encode(document))}');
}

/// [document] after [edit], or as it was where the edit is refused.
Layered<int> applied(Layered<int> document, Edit<int> edit) =>
    switch (document.apply(edit)) {
      Success(:final value) => value.document,
      Failure(:final message) => () {
        print('refused: $message');
        return document;
      }(),
    };

/// What [written] says, or why there is nothing.
String text(Result<Sequence<int>> written) => switch (written) {
  Success(:final value) => String.fromCharCodes(value.items),
  Failure(:final message) => 'refused: $message',
};
