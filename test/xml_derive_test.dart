import 'dart:io';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// After any edit, both layers are what a fresh read of the edited text
/// gives, however little was read again.
void main() {
  const xml = XML();

  for (final name in ['markwrite', 'ranges', 'htpasswd']) {
    test('editing $name.xml at random derives what a fresh read does', () {
      derivable(
        xml,
        File('test/samples/$name.xml').readAsStringSync(),
        seed: name.hashCode,
        edits: 500,
      );
    });
  }

  test('an edit inside an element reads that element again', () {
    final document = value(
      decoded(
        xml,
        '<doc><p>a</p><p>b</p></doc>',
      ).apply(Edit(1, Insert(17, Text.of('<i>c</i>')))),
    ).document;
    expect(preorder(document), ['0:#document', '1:doc', '2:p', '2:p', '3:i']);
  });

  test('an edit that unbalances an element reads past it', () {
    final document = value(
      decoded(
        xml,
        '<doc><p>a</p><p>b</p></doc>',
      ).apply(Edit(1, Delete(value(Range.create(17, 4))))),
    ).document;
    expect(layers(document), layers(decoded(xml, '<doc><p>a</p><p>b</doc>')));
  });

  test('typing at either end of the text pairs what it adds', () {
    var document = decoded(xml, '<p>x</p>');
    document = value(document.apply(Edit(1, Insert(8, Text.of('<q/>')))))
        .document;
    document = value(document.apply(Edit(1, Insert(0, Text.of('<r/>')))))
        .document;
    expect(preorder(document), ['0:#document', '1:r', '1:p', '1:q']);
  });
}
