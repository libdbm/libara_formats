# libara_formats

Markup syntaxes for [libara](https://github.com/libdbm/libara): XML, HTML,
LMNL, Markdown, man, ms, me and LaTeX, and JSON and Dart source, each a
libara `Format` from a text to a layered document.

A document keeps its text exactly as it was read. Its markup is a layer of
tokens over the text, and its elements a layer of ranges over the tokens,
both read again over only the stretch an edit touches. Writing a document in
the syntax it was read in gives back its text byte for byte; writing it in
another converts it.

## Use

```dart
import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';

final read = formats['md']!.decode(Text.of('# Notes\n\nA quick fox.\n'));
if (read case Success(value: final document)) {
  // Type a word, and the layers above the text are read again.
  final edited = document.apply(Edit(1, Insert(11, Text.of('brown '))));
  if (edited case Success(:final value)) {
    // Write it as XML.
    final xml = formats['xml']!.encode(value.document);
  }
}
```

`formats` maps each syntax's name and file extension, in lower case, to its
format: `xml`, `html` and `htm`, `lmnl`, `markdown` and `md`, `man` and the
section numbers `1` to `9`, `ms`, `me`, `latex` and `tex`, `json`, and `dart`.

`example/main.dart` reads, edits and converts a document, and
[doc/layers.md](doc/layers.md) sets out how each syntax maps onto the
layers.

## License

BSD 3-Clause; see [LICENSE](LICENSE).
