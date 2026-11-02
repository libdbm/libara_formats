import 'package:libara/libara.dart';

import 'dart/dart.dart';
import 'html/html.dart';
import 'import/rtf.dart';
import 'json/json.dart';
import 'latex/latex.dart';
import 'lmnl/lmnl.dart';
import 'markdown/markdown.dart';
import 'roff/roff.dart';
import 'rtf/rtf.dart';
import 'xml/xml.dart';

/// A syntax a document is read from.
abstract interface class Readable {
  /// The document [form] holds, or a failure for a form this syntax cannot
  /// read.
  Result<Layered<int>> decode(Sequence<int> form);
}

/// A syntax a document is written in.
abstract interface class Writable {
  /// [value] in this syntax, or a failure for a document it cannot write.
  Result<Sequence<int>> encode(Layered<int> value);
}

/// A syntax that documents are both read from and written in: every format
/// in [formats].
///
/// One type for the three it is, so that a list of syntaxes is a list of
/// [Syntax] rather than of what they have in common.
abstract interface class Syntax
    implements Format<Layered<int>, Sequence<int>>, Readable, Writable {}

/// Every syntax here, under its name and each of its file extensions, in
/// lower case.
const Map<String, Syntax> formats = {
  'dart': Dart(),
  'htm': HTML(),
  'html': HTML(),
  '1': Man(),
  '2': Man(),
  '3': Man(),
  '4': Man(),
  '5': Man(),
  '6': Man(),
  '7': Man(),
  '8': Man(),
  '9': Man(),
  'json': JSON(),
  'latex': LaTeX(),
  'lmnl': LMNL(),
  'man': Man(),
  'me': Me(),
  'ms': Ms(),
  'rtf': RTF(),
  'tex': LaTeX(),
  'markdown': Markdown(),
  'md': Markdown(),
  'xml': XML(),
};

/// Every importer here, under its name and each of its file extensions, in
/// lower case: each reads a word processor's file into the normalized
/// document, as LMNL, and writes nothing.
const Map<String, Readable> importers = {'rtf': RTFImport()};
