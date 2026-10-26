// What survives a paste from each of the programs people copy from.
import 'dart:io';

import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

/// What `samples/pasted/<name>.html` comes to, matching the style.
String pasted(String name) =>
    Foreign.cleaned(File('test/samples/pasted/$name.html').readAsStringSync())!;

void main() {
  // Every capture holds the same document: a heading, a paragraph with
  // emphasis and a link, a nested list, a table with a spanning cell and a
  // picture. What each program wraps round it differs, and what comes
  // through should not.
  for (final name in const [
    'word',
    'libreoffice',
    'chrome',
    'safari',
    'mail',
    'docs',
  ]) {
    group('Pasted from $name', () {
      final held = pasted(name);

      test('keeps the heading', () {
        expect(held, matches(RegExp(r'<h[12]>[^<]+</h[12]>')));
      }, skip: name == 'mail' ? 'a mail has no heading' : null);

      test('keeps the emphasis as elements', () {
        expect(held, matches(RegExp(r'<(b|strong)>[^<]+</(b|strong)>')));
        expect(held, matches(RegExp(r'<(i|em)>[^<]+</(i|em)>')));
      });

      test('keeps the link and where it goes', () {
        expect(held, contains('<a href="https://example.'));
      });

      test('keeps the list nested', () {
        expect(held, contains('<li>'));
        expect(
          held,
          matches(RegExp(r'<(ul|ol)>.*<(ul|ol)>.*</(ul|ol)>.*</(ul|ol)>')),
        );
      }, skip: name == 'mail' ? 'a mail list is one level' : null);

      test('keeps the table and its span', () {
        expect(held, contains('<table>'));
        expect(held, matches(RegExp(r'<t[dh] (col|row)span="2">')));
      }, skip: name == 'mail' ? 'a mail has no table' : null);

      test(
        'keeps the picture as one',
        () {
          expect(held, contains('<img src="'));
          expect(held, contains('alt="A gull"'));
        },
        skip: name == 'word'
            ? 'Word names a temporary file the paste cannot reach, and the '
                  'pasteboard carries no picture beside words'
            : null,
      );

      test('and nothing of the page', () {
        expect(held, isNot(contains('<div')));
        expect(held, isNot(contains('<span')));
        expect(held, isNot(contains('<meta')));
        expect(held, isNot(contains('<o:p')));
        expect(held, isNot(contains('style=')));
        expect(held, isNot(contains('class=')));
        expect(held, isNot(contains('font-family')));
        expect(held, isNot(contains('@page')));
        expect(held, isNot(contains('supportLists')));
      });
    });
  }

  test('Word marks its list paragraphs, and they come through as a list', () {
    expect(
      pasted('word'),
      contains(
        '<ol><li>North</li><ol><li>Scotland</li></ol><li>South</li></ol>'
        '<ul><li>Risks</li></ul>',
      ),
    );
  });

  test('Google Docs represents emphasis as a style, and it comes through', () {
    expect(
      pasted('docs'),
      contains('the <b>budget</b> and the <i>timeline</i>'),
    );
    // The bold wrapper that says it is not bold is gone.
    expect(pasted('docs'), isNot(startsWith('<b')));
  });

  test(
    'Apple Mail writes a div per line, and they come through as paragraphs',
    () {
      expect(pasted('mail'), startsWith('<p>Hello,</p>'));
      expect(pasted('mail'), contains('<p>Thanks,</p><p>Sam</p>'));
    },
  );

  test('keeping the formatting keeps the sizes and colours and no face', () {
    final held = Foreign.kept(
      File('test/samples/pasted/docs.html').readAsStringSync(),
    )!;
    expect(held, contains('style="font-size:11pt;color:#1155cc"'));
    expect(held, isNot(contains('font-family')));
    expect(held, isNot(contains('background-color')));
  });
}
