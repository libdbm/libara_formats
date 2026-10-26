import 'dart:io';

import 'package:libara/libara.dart' show ARange;
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart' as reference;

import 'harness.dart';

/// The reference parser's elements in pre-order, as `depth:name`, under a
/// `#document` at depth 0. Read as a fragment, since several samples hold
/// more than one element at the top.
List<String> expected(String text) {
  final order = ['0:#document'];
  void walk(reference.XmlNode node, int depth) {
    for (final child in node.children) {
      if (child is reference.XmlElement) {
        order.add('$depth:${child.name.qualified}');
        walk(child, depth + 1);
      }
    }
  }

  walk(reference.XmlDocumentFragment.parse(text), 1);
  return order;
}

/// XML's layer 3: elements paired from the tokens, under a root. Ported
/// from markwrite's `dom_test` and the layer-3 cases of `xml_lex_test`.
void main() {
  const xml = XML();

  group('Elements nest as the reference parser says', () {
    for (final text in const [
      '<p>Hi <a>there</a> bye</p>',
      '<doc><h>Title</h><p>One <i>two</i> three.</p><p>Second.</p></doc>',
      '<a><b><c>deep</c></b></a>',
      '<p>a<br/>b</p>',
      '<list><item>x</item><item>y</item></list>',
      '<?xml version="1.0"?><!-- c --><p>x<![CDATA[<q>]]></p>',
    ]) {
      test(text, () {
        isomorphic(expected(text), decoded(xml, text));
      });
    }

    for (final file
        in Directory('test/samples')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.xml'))) {
      test(file.uri.pathSegments.last, () {
        final text = file.readAsStringSync();
        final document = decoded(xml, text);
        isomorphic(expected(text), document);
        expect(problems(document, 3), isEmpty);
      });
    }
  });

  group('An element', () {
    test('runs from its start tag to its end tag', () {
      final document = decoded(xml, '<p>The <i>quick</i> fox.</p>');
      final elements = {
        for (final range in document.layer(3).items)
          said(range as ARange, ''): range,
      };
      expect(elements['p']!.start, 0);
      expect(elements['p']!.length, 7);
      expect(elements['i']!.start, 2);
      expect(elements['i']!.length, 3);
    });

    test('carries the attributes its start tag says', () {
      final document = decoded(xml, '<a href="/x" name="top">go</a>');
      final element = document
          .layer(3)
          .items
          .cast<ARange>()
          .firstWhere((range) => said(range, '') == 'a');
      expect(said(element, 'href'), '/x');
      expect(said(element, 'name'), 'top');
    });

    test('that is empty is its one token', () {
      final document = decoded(xml, '<p>a<br/>b</p>');
      final br = document
          .layer(3)
          .items
          .cast<ARange>()
          .firstWhere((range) => said(range, '') == 'br');
      expect((br.start, br.length), (2, 1));
    });

    test('the document is the whole layer, not a range of its own', () {
      expect(
        decoded(xml, '<p>hi</p>').layer(3).items.map((range) => '$range'),
        ['{0,3,:p}'],
      );
      expect(preorder(decoded(xml, '')), ['0:#document']);
    });
  });
}
