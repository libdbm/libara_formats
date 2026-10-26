import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// Ported from markwrite's `edit_neutrality_test`. There a rule claimed an
/// edit left the tokens alone, and the claim was checked; here every edit
/// is read again over the region it affects, so every small edit of every
/// source is checked: the layers it leaves are a fresh read's.
///
/// One source per thing that could read an edit and be changed by it, as
/// markwrite chose them.
const sources = [
  '# Title\nsome *emphasis* and `code` here\n',
  // A table: what makes the first line a row of headings is the ruling
  // line below it.
  '| head | next |\n| --- | :-- |\n| one | two |\n',
  // A definition and a use of it: an edit inside the definition reaches far
  // beyond its own block.
  '[home]: /url "Home"\n\nGo [home] now, or [away][home].\n',
  // An autolink, which runs to the next angle wherever that stands.
  'Write to <mail@example.com> or see <https://example.com/a>.\n',
  // A reference, which reads up to thirty-two characters ahead.
  'Ten &nbsp; spaces &amp; an ampersand &#65; and a letter.\n',
  // A fence, whose rest names the language the block says it is in.
  '```dart\nplain words within\n```\n\nAfter the fence.\n',
  // A setext heading, made by the line under it, and a rule.
  'Underlined heading\n===\n\nAnother\n---\n\n* * *\n\nWords.\n',
  // An indented code block, whose indent is what makes it one.
  'A paragraph.\n\n    indented code here\n    and a second line\n',
  // Lists, whose markers and content indent are read from a line's start.
  '- one item\n- two item\n\n10. tenth\n11. eleventh\n\n  - nested\n',
  // A quotation, a hard break, and a heading closed with its own hashes.
  '> quoted words\n> more\n\nbroken  \nline\n\n## Closed ##\n',
  // A picture, whose whole markup is one token saying what it says.
  'See ![a gull](gull.png "Title") and *more* words.\n',
];

const replacements = [
  '', 'z', 'zz', '\n', '-', '<', //
  ' ', '&', ';', '`', '*', '[', '#', '1', '.', '|', '=', 'a',
];

void main() {
  const markdown = Markdown();
  for (final source in sources) {
    test('every small edit of "${source.split('\n').first}" reads afresh', () {
      final document = decoded(markdown, source);
      final length = document.items.length;
      for (var start = 0; start <= length; start++) {
        for (var size = 0; size <= 3 && start + size <= length; size++) {
          for (final replacement in replacements) {
            if (size == 0 && replacement.isEmpty) {
              continue;
            }
            final next = value(
              document.apply(
                Edit(
                  1,
                  Replace(
                    value(Range.create(start, size)),
                    Text.of(replacement),
                  ),
                ),
              ),
            ).document;
            expect(
              layers(next),
              layers(decoded(markdown, string(next.items))),
              reason: 'replacing {$start,$size} with "$replacement"',
            );
          }
        }
      }
    });
  }
}
