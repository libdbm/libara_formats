import 'package:libara_formats/src/tags.dart';
import 'package:test/test.dart';

/// The scanner XML and HTML both stand on, asked directly, at the grain of
/// one tag rather than one document. Ported from markwrite's `tags_test`;
/// the names of the non-element constructs are the DOM's.
void main() {
  group('Where a tag ends', () {
    test('at the first close, for an ordinary tag', () {
      expect(closing('<p>one', 0), 2);
      expect(closing('one<em>two', 3), 6);
    });

    test('and past a close standing inside a quoted value', () {
      expect(closing('<a title="a > b">x', 0), 16);
      expect(closing("<a title='a > b'>x", 0), 16);
    });

    test('and past several of them', () {
      expect(closing('<a one=">" two=">">x', 0), 18);
    });

    test('and nowhere, where nothing closes it', () {
      expect(closing('<p one two', 0), -1);
      expect(closing('<a title="never closed', 0), -1);
    });

    test('and a quote of one kind inside a value quoted with the other', () {
      expect(closing('''<a title="it's">x''', 0), 15);
    });
  });

  group('What a tag is called', () {
    for (final (token, wanted) in <(String, String)>[
      ('<p>', 'p'),
      ('</p>', 'p'),
      ('<br/>', 'br'),
      ('<br />', 'br'),
      ('<p class="a">', 'p'),
      ('<p\nclass="a">', 'p'),
      ('<p\tclass="a">', 'p'),
      ('<PARA>', 'PARA'),
      ('<a:b>', 'a:b'),
      ('<p', 'p'),
      ('<>', ''),
      ('</>', ''),
      ('<', ''),
    ]) {
      test('"$token" is called "$wanted"', () {
        expect(called(token), wanted);
      });
    }
  });

  group('What a construct that is not an element is called', () {
    test('a comment, which shows nothing', () {
      expect(saying('<!-- a note -->', 0, 15), ('#comment', ''));
    });

    test('a doctype and a processing instruction, which show nothing', () {
      expect(saying('<!DOCTYPE html>', 0, 15), ('#doctype', ''));
      expect(saying('<!doctype html>', 0, 15), ('#doctype', ''));
      expect(saying('<?xml version="1"?>', 0, 19), ('#pi', ''));
    });

    test('a declaration other than a doctype keeps a name of its own', () {
      expect(saying('<!ELEMENT p ANY>', 0, 16), ('#declaration', ''));
    });

    test('a character section, which shows what stands inside it', () {
      expect(saying('<![CDATA[a > b]]>', 0, 17), ('#cdata', 'a > b'));
    });

    test('and an empty one shows nothing at all', () {
      expect(saying('<![CDATA[]]>', 0, 12), ('#cdata', ''));
    });
  });

  group('Where such a construct ends', () {
    test('a comment, at its own terminator', () {
      expect(skipped('<!-- a note -->after', 0), 15);
    });

    test('a character section, at its own and not at the first close', () {
      expect(skipped('<![CDATA[a > b]]>after', 0), 17);
    });

    test('a declaration and an instruction, at the first close', () {
      expect(skipped('<!DOCTYPE html>after', 0), 15);
      expect(skipped('<?xml version="1"?>after', 0), 19);
    });

    test('and nowhere, where any of them is unterminated', () {
      expect(skipped('<!-- never closed', 0), -1);
      expect(skipped('<![CDATA[ never closed', 0), -1);
      expect(skipped('<!DOCTYPE html', 0), -1);
    });

    test('a comment closed by the shortest thing that closes one', () {
      expect(skipped('<!---->after', 0), 7);
    });
  });

  group('What a tag says about itself', () {
    test('a name and a value, quoted either way', () {
      expect(pairs('<a href="/x">'), [('href', '/x')]);
      expect(pairs("<a href='/x'>"), [('href', '/x')]);
    });

    test('and several, in the order they were written', () {
      expect(pairs('<a href="/x" rel="next" id="one">'), [
        ('href', '/x'),
        ('rel', 'next'),
        ('id', 'one'),
      ]);
    });

    test('and one written without quotes', () {
      expect(pairs('<a href=x rel=next>'), [('href', 'x'), ('rel', 'next')]);
    });

    test('and an unquoted one holding the slashes a path is made of', () {
      expect(pairs('<a href=/index.html>'), [('href', '/index.html')]);
      expect(pairs('<img src=/a/b.png>'), [('src', '/a/b.png')]);
      expect(pairs('<a href=a/b/c d=e>'), [('href', 'a/b/c'), ('d', 'e')]);
    });

    test('and the slash that closes an empty tag still closes it', () {
      expect(pairs('<img src=a/>'), [('src', 'a')]);
      expect(pairs('<br/>'), isEmpty);
    });

    test('and one written with no value, which says itself', () {
      expect(pairs('<input disabled>'), [('disabled', '')]);
      expect(pairs('<input disabled checked>'), [
        ('disabled', ''),
        ('checked', ''),
      ]);
    });

    test('and one whose value is empty, which is not the same thing', () {
      expect(pairs('<a href="">'), [('href', '')]);
    });

    test('and space around the equals, wherever it stands', () {
      expect(pairs('<a href = "/x">'), [('href', '/x')]);
      expect(pairs('<a\n  href="/x"\n  rel="next"\n>'), [
        ('href', '/x'),
        ('rel', 'next'),
      ]);
    });

    test('and nothing, for a tag that says nothing', () {
      expect(pairs('<p>'), isEmpty);
      expect(pairs('</p>'), isEmpty);
      expect(pairs('<br/>'), isEmpty);
    });

    test('and a value carrying what would otherwise end the tag', () {
      expect(pairs('<a title="a > b">'), [('title', 'a > b')]);
      expect(pairs('<a title="a / b">'), [('title', 'a / b')]);
    });

    test('and it stops rather than guessing where a quote never closes', () {
      expect(pairs('<a href="never'), isEmpty);
    });
  });
}
