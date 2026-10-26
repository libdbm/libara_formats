// Markup that came from somewhere else.
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

void main() {
  group('Markup pasted from somewhere else', () {
    test('keeps what a document is made of', () {
      expect(
        Foreign.cleaned('<p><b>Bold</b> and <i>italic</i>.</p>'),
        '<p><b>Bold</b> and <i>italic</i>.</p>',
      );
    });

    test('and drops what a page is made of', () {
      // Which is nearly all of what a browser puts on the clipboard.
      final held = Foreign.cleaned(
        "<meta charset='utf-8'>"
        '<span style="color:#000;font-family:Arial">'
        '<span class="x">Some <b>words</b>.</span></span>',
      );

      expect(held, 'Some <b>words</b>.');
    });

    test('and a div holding words is the paragraph it stands for', () {
      // A mail client and a browser write a paragraph as a div; one holding
      // other blocks is layout and goes.
      expect(
        Foreign.cleaned('<div>One</div><div>Two</div>'),
        '<p>One</p><p>Two</p>',
      );
      expect(
        Foreign.cleaned('<div class="page"><p>One</p><p>Two</p></div>'),
        '<p>One</p><p>Two</p>',
      );
    });

    test('and emphasis represented as a style is the emphasis it is', () {
      // Which is how a browser and Google Docs say bold and italic.
      expect(
        Foreign.cleaned(
          '<span style="font-weight:700;font-style:italic">a</span>'
          '<span style="text-decoration:underline">b</span>'
          '<span style="text-decoration:line-through">c</span>',
        ),
        '<b><i>a</i></b><u>b</u><s>c</s>',
      );
    });

    test('and a bold element saying it is not bold is a wrapper', () {
      // Google Docs wraps what it copies in one.
      expect(
        Foreign.cleaned(
          '<b style="font-weight:normal" id="docs-internal-guid-1">'
          '<p>Words <span style="font-weight:700">here</span></p></b>',
        ),
        '<p>Words <b>here</b></p>',
      );
    });

    test('and reads a list the way Word writes one', () {
      // Word writes a list as paragraphs that each say which list and level
      // they belong to, with the marker written out for a reader that does
      // not know lists.
      const word =
          "<p class=MsoListParagraph style='mso-list:l0 level1 lfo1'>"
          '<!--[if !supportLists]-->1.<span style=\'font:7.0pt "Times"\'>'
          '&nbsp;&nbsp;</span><!--[endif]-->First<o:p></o:p></p>'
          "<p class=MsoListParagraph style='mso-list:l0 level2 lfo1'>"
          '<!--[if !supportLists]-->a.<span>&nbsp;</span><!--[endif]-->'
          'Inner</p>'
          "<p class=MsoListParagraph style='mso-list:l1 level1 lfo2'>"
          '<!--[if !supportLists]-->·<span>&nbsp;</span><!--[endif]-->'
          'Bullet</p>'
          '<p class=MsoNormal>After</p>';

      expect(
        Foreign.cleaned(word),
        '<ol><li>First</li><ol><li>Inner</li></ol></ol>'
        '<ul><li>Bullet</li></ul><p>After</p>',
      );
    });
    test('and reads a Word list level out of range as the nearest', () {
      expect(
        Foreign.cleaned('<p style="mso-list:l0 level0 lfo1">x</p>'),
        '<ul><li>x</li></ul>',
      );
      final deep = Foreign.cleaned(
        '<p style="mso-list:l0 level2000000 lfo1">x</p>',
      );
      expect('<ul>'.allMatches(deep!), hasLength(9));
    });

    test('and drops what an element says about how it looks', () {
      // The look belongs to the document being pasted into, which is what
      // every word processor means by pasting and matching the style.
      expect(
        Foreign.cleaned(
          '<p style="font-size:48px;color:red" class="lede">Hello</p>',
        ),
        '<p>Hello</p>',
      );
    });

    test('and keeps what an element says about what it is', () {
      expect(
        Foreign.cleaned('<a href="https://example.com" title="x">a link</a>'),
        '<a href="https://example.com">a link</a>',
      );
      expect(
        Foreign.cleaned('<img src="one.png" alt="a gull" width="40">'),
        '<img src="one.png" alt="a gull"/>',
      );
      expect(
        Foreign.cleaned(
          '<table><tr><td colspan="2" bgcolor="red">a</td></tr></table>',
        ),
        '<table><tr><td colspan="2">a</td></tr></table>',
      );
    });

    test('and closes what the page left open', () {
      // A fragment that leaves an element open swallows the document it
      // lands in, and a page's markup is full of tags nothing closes.
      expect(Foreign.cleaned('<p>One<p>Two'), '<p>One<p>Two</p></p>');
      expect(Foreign.cleaned('<b>bold'), '<b>bold</b>');
    });

    test('and keeps a list a list', () {
      expect(
        Foreign.cleaned('<ul><li>One</li><li>Two</li></ul>'),
        '<ul><li>One</li><li>Two</li></ul>',
      );
    });
    test('and says nothing for markup that holds no words', () {
      expect(Foreign.cleaned('<div><span></span></div>'), isNull);
      expect(Foreign.cleaned('   '), isNull);
    });

    test('and words with no markup at all are the words', () {
      expect(Foreign.cleaned('just words'), 'just words');
    });
  });

  group('Markup pasted with its formatting kept', () {
    test('keeps the look a fixed set of properties says', () {
      expect(
        Foreign.kept(
          '<p style="text-align:center;font-family:Arial;margin:0">'
          '<span style="color:#ff0000;font-size:14pt;font-weight:bold">'
          'Red</span> plain</p>',
        ),
        '<p style="text-align:center">'
        '<span style="font-size:14pt;color:#ff0000"><b>Red</b></span>'
        ' plain</p>',
      );
    });

    test('and a block carries its own weight and slant as a style', () {
      expect(
        Foreign.kept('<p style="font-weight:bold;font-style:italic">A</p>'),
        '<p style="font-weight:bold;font-style:italic">A</p>',
      );
      // A heading is bold by nature and is not told twice.
      expect(Foreign.kept('<h2 style="font-weight:bold">A</h2>'), '<h2>A</h2>');
    });

    test('and is what matching the style is where nothing was said', () {
      const plain = '<p>Words <b>here</b></p>';
      expect(Foreign.kept(plain), Foreign.cleaned(plain));
    });
  });

  group('A pasted link', () {
    test('keeps a target that goes somewhere and drops one that runs', () {
      expect(
        Foreign.cleaned('<a href="https://example.invalid/x">x</a>'),
        '<a href="https://example.invalid/x">x</a>',
      );
      expect(
        Foreign.cleaned('<a href="mailto:x@example.invalid">x</a>'),
        '<a href="mailto:x@example.invalid">x</a>',
      );
      expect(
        Foreign.cleaned('<a href="notes/x.html">x</a>'),
        '<a href="notes/x.html">x</a>',
      );
      expect(
        Foreign.cleaned('<a href="javascript:alert(1)">x</a>'),
        '<a>x</a>',
      );
      expect(
        Foreign.cleaned('<a href=" JavaScript:alert(1)">x</a>'),
        '<a>x</a>',
      );
      expect(Foreign.cleaned('<a href="data:text/html,x">x</a>'), '<a>x</a>');
      expect(
        Foreign.cleaned('<img src="javascript:x" alt="y">'),
        '<img alt="y"/>',
      );
    });

    test('drops one that runs however it is padded', () {
      expect(
        Foreign.cleaned('<a href="java&#9;script:alert(1)">x</a>'),
        '<a>x</a>',
      );
      expect(
        Foreign.cleaned('<a href="java&#10;script:alert(1)">x</a>'),
        '<a>x</a>',
      );
      expect(
        Foreign.cleaned('<a href="&#1;javascript:alert(1)">x</a>'),
        '<a>x</a>',
      );
    });
  });
}
