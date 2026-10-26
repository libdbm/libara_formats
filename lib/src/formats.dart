import 'package:libara/libara.dart';

import 'dart/dart.dart';
import 'html/html.dart';
import 'json/json.dart';
import 'latex/latex.dart';
import 'lmnl/lmnl.dart';
import 'markdown/markdown.dart';
import 'roff/roff.dart';
import 'xml/xml.dart';

/// Every syntax here, under its name and each of its file extensions, in
/// lower case.
const Map<String, Format<Layered<int>, Sequence<int>>> formats = {
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
  'tex': LaTeX(),
  'markdown': Markdown(),
  'md': Markdown(),
  'xml': XML(),
};
