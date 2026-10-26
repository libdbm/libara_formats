import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';
import 'html5lib.dart';
import 'html_dom_test.dart' show built;

/// The html5lib tree-construction cases, the standard's own: each element
/// tree they hold, the elements alone, against layer 3's.
///
/// Left out, and counted: cases that parse a fragment, cases with scripting
/// off, since this reads with it on, and cases whose result a script
/// decides. Skipped, with the reason: cases where the standard would foster
/// content out of a table, which stays
/// where it is written here by design; and `selectedcontent`, whose
/// content the standard copies from an option, copies no markup in the text
/// represents; and markup inside an SVG or MathML element that HTML reads as
/// text, such as `title`, which the tokenizer, knowing no context, holds in
/// one token.
void main() {
  const html = HTML();

  for (final kase in cases()) {
    if (kase.fragment || !kase.scripted || scripting(kase.file)) {
      continue;
    }
    final document = decoded(html, kase.data);
    final skip =
        problems(document, 3).any((problem) => problem.startsWith('fostered'))
        ? 'fostered content stays where it is written, by design'
        : kase.data.contains('selectedcontent')
        ? 'selectedcontent holds copies no markup represents'
        : _marked(kase.elements)
        ? 'markup inside a foreign title, style or script is one token here'
        : null;
    test('${kase.file} #${kase.number}', () {
      expect(built(document), kase.elements, reason: kase.data);
    }, skip: skip ?? false);
  }
}

/// Whether [elements], as `depth:name` in pre-order, put an element inside
/// a foreign element whose name HTML reads as text.
bool _marked(List<String> elements) {
  const raw = {
    'title', 'style', 'script', 'textarea', 'xmp', 'iframe', 'noembed', //
    'noframes', 'noscript', 'plaintext',
  };
  for (var at = 0; at + 1 < elements.length; at++) {
    int depth(String element) =>
        int.parse(element.substring(0, element.indexOf(':')));
    final parts = elements[at]
        .substring(elements[at].indexOf(':') + 1)
        .split(' ');
    if (parts.length == 2 &&
        raw.contains(parts.last) &&
        depth(elements[at + 1]) > depth(elements[at])) {
      return true;
    }
  }
  return false;
}
