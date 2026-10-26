/// Markdown's inlines: the standard's second phase, what the characters
/// between a leaf block's words mean.
///
/// Ported from markwrite's `inlines.dart` and `links.dart`. Each mark
/// that is syntax is a token named for the element it belongs to, and each
/// element a span from its first token to its last; positions are UTF-16
/// units of the text read.
library;

import 'dart:math';

import '../entities.dart';
import '../lexing.dart' show Found;

part 'links.dart';

/// What a link's title says where the link is an element Markdown cannot
/// represent standing in for itself, its destination the element's name.
const standing = 'element';

/// What the words of a leaf block come to.
typedef Inlines = ({List<Found> tokens, List<Found> elements});

/// Where a link written by name goes, its destination and title, looked up
/// by the name as [labelled] makes it.
typedef Links = (String, String?)? Function(String label);

/// A stretch of the words, from [start] for [length].
final class _Range {
  _Range(this.start, this.length);

  _Range.between(this.start, int end) : length = end - start;

  final int start;
  final int length;

  int get end => start + length;

  bool contains(_Range other) => start <= other.start && other.end <= end;

  bool covers(int at) => start <= at && at < end;
}

/// The words of one leaf block, as one string with a way back to the text.
///
/// A block's own markers stand inside the stretch it covers: a quotation
/// carried over three lines has an angle on each of them, and the words are
/// what is left when they are taken away. The scan below works on the words,
/// so the markers have to be out of the way, and every position it finds has
/// to be a position in the text again.
final class Content {
  /// The words.
  final String text;

  /// Where each character of [text] stands in the text read.
  final List<int> at;

  /// The words [text], standing in the text read at [at].
  const Content(this.text, this.at);

  /// The words of [source] from [start] to [end] with [holes] left out.
  factory Content.of(
    String source,
    int start,
    int end,
    List<(int, int)> holes,
  ) {
    final held = StringBuffer();
    final places = <int>[];
    var index = start;
    final sorted = [...holes]..sort((a, b) => a.$1 - b.$1);
    for (final (from, to) in sorted) {
      if (to <= index || from >= end) {
        continue;
      }
      for (var at = index; at < from && at < end; at += 1) {
        held.write(source[at]);
        places.add(at);
      }
      index = to > index ? to : index;
    }
    for (var at = index; at < end; at += 1) {
      held.write(source[at]);
      places.add(at);
    }
    return Content(held.toString(), places);
  }

  /// The stretch of the text read under the [length] characters from
  /// [from], or nothing where they do not stand together there.
  (int, int)? spanned(int from, int length) {
    if (length <= 0 || from + length > at.length) {
      return null;
    }
    if (at[from + length - 1] - at[from] != length - 1) {
      return null;
    }
    return (at[from], at[from] + length);
  }

  /// The stretch of the text read from character [from] to [to] of the
  /// words, holes and all.
  (int, int) reach(int from, int to) =>
      (at[from], to > from ? at[to - 1] + 1 : at[from]);
}

/// A bracket on the stack the second walk keeps: where it stands, whether
/// a bang opened it, how many runs, tokens, elements and shadows stood when
/// it did, and whether it may still close a link.
final class _Opener {
  _Opener(
    this.at,
    this.delimiters,
    this.held,
    this.made,
    this.shadows, {
    required this.image,
  });

  final int at;
  final int delimiters;
  final int held;
  final int made;
  final int shadows;
  final bool image;
  bool active = true;
}

/// One run of emphasis characters, waiting to be paired.
final class _Delimiter {
  _Delimiter(this.at, this.length, this.mark, this.opens, this.closes);

  int at;
  int length;
  final String mark;
  final bool opens;
  final bool closes;
  bool live = true;
}

/// A label as it is looked up: case folded, and its whitespace run together,
/// so that `[Foo  bar]` and `[foo bar]` are the one name.
String labelled(String held) =>
    held.trim().toLowerCase().replaceAll(_spaces, ' ');

/// Whether [held] may be a name a link is looked up by.
///
/// A name holds no bracket that is not escaped. `[[[foo]]]` is three brackets
/// round a word rather than a name, and a definition that seems to give one
/// gives nothing: what would look it up cannot be represented.
bool _nameable(String held) {
  for (var at = 0; at < held.length; at += 1) {
    if (held[at] == r'\') {
      at += 1;
      continue;
    }
    if (held[at] == '[' || held[at] == ']') {
      return false;
    }
  }
  return held.trim().isNotEmpty;
}

/// The definition standing at [at], as where it ends, what it names, where
/// it goes and what it is called.
///
/// A paragraph that begins with one is not a paragraph: it says where a link
/// goes and shows nothing, which is why it is read before the inlines.
(int, String, String, String?)? defined(String text, int at) {
  var index = at;
  while (index < text.length && (text[index] == ' ' || text[index] == '\t')) {
    index += 1;
  }
  if (index >= text.length || text[index] != '[') {
    return null;
  }
  final closed = _bracketed(text, index, _Spent());
  if (closed == null) {
    return null;
  }
  final label = text.substring(index + 1, closed - 1);
  // A definition that gives a name nothing can represent gives nothing, and the
  // line stays the paragraph it was written as.
  if (!_nameable(label) || closed >= text.length || text[closed] != ':') {
    return null;
  }
  index = closed + 1;
  // One line ending may stand between the colon and the destination, and
  // another between the destination and the title.
  var lines = 0;
  while (index < text.length && _space(text[index])) {
    if (text[index] == '\n' && ++lines > 1) {
      return null;
    }
    index += 1;
  }
  final String destination;
  var angled = false;
  if (index < text.length && text[index] == '<') {
    final close = _angled(text, index);
    if (close < 0) {
      return null;
    }
    destination = text.substring(index + 1, close);
    index = close + 1;
    angled = true;
  } else {
    final from = index;
    while (index < text.length && !_space(text[index])) {
      index += 1;
    }
    destination = text.substring(from, index);
  }
  // Somewhere is where a link written in angles may point, and nowhere is
  // still somewhere: `<>` is the empty address, represented.
  if (destination.isEmpty && !angled) {
    return null;
  }
  final over = index;
  lines = 0;
  while (index < text.length && _space(text[index])) {
    if (text[index] == '\n' && ++lines > 1) {
      break;
    }
    index += 1;
  }
  // A title is a thing of its own and stands apart from the address: with
  // nothing between them, `<bar>(baz)` says one thing that is neither.
  final apart = index > over;
  String? title;
  if (lines <= 1 &&
      apart &&
      index < text.length &&
      (text[index] == '"' || text[index] == "'" || text[index] == '(')) {
    final closer = text[index] == '(' ? ')' : text[index];
    final close = _closes(text, index + 1, closer);
    if (close >= 0 && !text.substring(index + 1, close).contains('\n\n')) {
      title = says(text.substring(index + 1, close));
      index = close + 1;
    }
  }
  // Whatever is left of the line has to be nothing, or this was a paragraph
  // that merely began like a definition.
  var end = title == null ? over : index;
  var scan = end;
  while (scan < text.length && _lineBlank(text[scan])) {
    scan += 1;
  }
  if (scan < text.length && text[scan] != '\n') {
    if (title == null) {
      return null;
    }
    // The title was somebody's words rather than a title.
    title = null;
    end = over;
    scan = end;
    while (scan < text.length && _lineBlank(text[scan])) {
      scan += 1;
    }
    if (scan < text.length && text[scan] != '\n') {
      return null;
    }
  }
  return (
    scan < text.length ? scan + 1 : scan,
    labelled(label),
    _unescaped(destination),
    title,
  );
}

/// The tokens and elements the words of [content] come to, a link written
/// by name looked up in [links].
///
/// Code spans first, since nothing inside one is anything else, then the
/// escapes, the references and the autolinks; then the links and the
/// pictures; and last the emphasis, which is settled by pairing the runs
/// that can open with the runs that can close.
Inlines inlined(Content content, Links links) {
  final held = <Found>[];
  final made = <Found>[];
  final delimiters = <_Delimiter>[];
  final text = content.text;
  // Where each length of backtick run stands, found at the first one.
  Map<int, List<int>>? runs;
  // Where each token and element stands in the words, kept beside it: the
  // walks below reason in the words, and a token says where it is in the
  // text.
  final places = <_Range>[];
  final spots = <_Range>[];
  // What a token stands inside of and is therefore not: a link's closing
  // syntax and a picture's whole syntax are markup, so a reference or an
  // escape found in one is part of the address rather than a character the
  // reader is shown.
  final shadows = <_Range>[];
  bool mark(
    int from,
    int length,
    String name, [
    Map<String, String> attributes = const {},
  ]) {
    final range = content.spanned(from, length);
    if (range == null) {
      return false;
    }
    held.add((range.$1, range.$2, name, attributes));
    places.add(_Range(from, length));
    return true;
  }

  void make(
    int from,
    int to,
    String name, [
    Map<String, String> said = const {},
  ]) {
    final (start, end) = content.reach(from, to);
    made.add((start, end, name, said));
    spots.add(_Range.between(from, to));
  }

  // What has been read already, which nothing reads into again: what a code
  // span, an autolink, a reference or an escape covers, and a link's closing
  // markup. This is how the standard's order of precedence is kept.
  final spent = _Spent();

  // The first walk: what nothing may read inside.
  var index = 0;
  while (index < text.length) {
    final character = text[index];
    switch (character) {
      case r'\':
        if (index + 1 < text.length && _punctuation(text[index + 1])) {
          mark(index, 2, '#escape', {'shows': text[index + 1]});
          spent.add(_Range(index, 2));
          index += 2;
          continue;
        }
        // A break at the end of the words breaks before nothing, so the
        // last line of a block never carries one. The line may end with a
        // return before its newline, which is the ending's markup.
        final ending = _ending(text, index + 1);
        if (ending > 0 && index + 1 + ending < text.length) {
          if (mark(index, 1, 'br')) {
            make(index, index + 1, 'br');
          }
          spent.add(_Range(index, 1 + ending));
          index += 1 + ending;
          continue;
        }
        index += 1;
      case '`':
        final run = _run(text, index, '`');
        final close = _closing(runs ??= _runs(text), index + run, run);
        if (close < 0) {
          index += run;
          continue;
        }
        // A space at each end belongs to the markup rather than to the
        // code, so that a span may hold a backtick of its own: `` ` ``. Both
        // ends or neither, and never where the whole of it is spaces.
        final inside = text.substring(index + run, close);
        final stripped =
            inside.length > 1 &&
            _space(inside[0]) &&
            _space(inside[inside.length - 1]) &&
            inside.trim().isNotEmpty;
        final width = run + (stripped ? 1 : 0);
        if (mark(index, width, 'code') &&
            mark(close - (stripped ? 1 : 0), width, 'code')) {
          make(index, close + run, 'code');
        }
        spent.add(_Range.between(index, close + run));
        index = close + run;
      case '&':
        final found = _reference(text, index);
        if (found != null) {
          mark(index, found.$1, '#entity', {'shows': found.$2});
          spent.add(_Range(index, found.$1));
          index += found.$1;
          continue;
        }
        index += 1;
      case '<':
        final found = _autolink(text, index);
        if (found != null) {
          if (mark(index, 1, 'a') && mark(index + found.$1 - 1, 1, 'a')) {
            make(index, index + found.$1, 'a', {'href': found.$2});
          }
          spent.add(_Range(index, found.$1));
          index += found.$1;
          continue;
        }
        index += 1;
      case '\n':
        // A return before the newline is the ending's markup.
        final base = index > 0 && text[index - 1] == '\r' ? index - 1 : index;
        // Two spaces before a line ending is a break the writer asked for.
        var spaces = 0;
        while (spaces < base && text[base - spaces - 1] == ' ') {
          spaces += 1;
        }
        if (spaces >= 2 && index + 1 < text.length) {
          if (mark(base - spaces, index - base + spaces, 'br')) {
            make(base - spaces, index, 'br');
          }
          spent.add(_Range(base - spaces, index - base + spaces));
        }
        index += 1;
      default:
        index += 1;
    }
  }

  // The second walk: brackets, and then the runs that may become emphasis.
  // An opener is put on a stack and read no further, and a closer takes the
  // last opener off and asks what follows it. A link may not hold a link,
  // and the standard settles that by closing the innermost first: once one
  // is made, every opener before it that could make another is stood down.
  //
  // A run inside a link's words may not pair with one outside them, so the
  // words are settled on their own the moment the link closes.
  final openers = <_Opener>[];
  index = 0;
  while (index < text.length) {
    final past = spent.past(index);
    if (past > index) {
      index = past;
      continue;
    }
    final character = text[index];
    switch (character) {
      case '!' when index + 1 < text.length && text[index + 1] == '[':
        openers.add(
          _Opener(
            index,
            delimiters.length,
            held.length,
            made.length,
            shadows.length,
            image: true,
          ),
        );
        index += 2;
      case '[':
        openers.add(
          _Opener(
            index,
            delimiters.length,
            held.length,
            made.length,
            shadows.length,
            image: false,
          ),
        );
        index += 1;
      case ']':
        if (openers.isEmpty) {
          index += 1;
          continue;
        }
        final opener = openers.removeLast();
        final closes = index + 1;
        final at = opener.image ? opener.at + 1 : opener.at;
        final target = opener.active
            ? _target(text, closes) ?? _referred(text, at, closes, links, spent)
            : null;
        if (target == null) {
          index += 1;
          continue;
        }
        final (end, address, title) = target;
        if (opener.image) {
          // What stood inside a picture's markup is its words, read for
          // what a reader who cannot see it is shown, and nothing else: the
          // picture is one token, so everything the walk made inside it is
          // taken back once the words are read off it.
          final alt = _shown(
            text,
            opener.at + 2,
            index,
            held,
            places,
            delimiters.sublist(opener.delimiters),
          );
          held.length = opener.held;
          places.length = opener.held;
          made.length = opener.made;
          spots.length = opener.made;
          shadows.length = opener.shadows;
          delimiters.removeRange(opener.delimiters, delimiters.length);
          final said = {'src': address, 'alt': alt, 'title': ?title};
          if (!mark(opener.at, end - opener.at, 'img', said)) {
            index += 1;
            continue;
          }
          make(opener.at, end, 'img', said);
          shadows.add(_Range.between(opener.at, end));
          spent.add(_Range.between(opener.at, end));
        } else {
          // An element Markdown cannot represent is written as a link standing
          // in for itself, and read back as the element it stands for.
          final name = title == standing && address.isNotEmpty ? address : 'a';
          final said = name == 'a'
              ? {'href': address, 'title': ?title}
              : <String, String>{};
          if (content.spanned(opener.at, 1) == null ||
              content.spanned(index, end - index) == null) {
            index += 1;
            continue;
          }
          mark(opener.at, 1, name);
          mark(index, end - index, name, said);
          shadows.add(_Range.between(index, end));
          spent.add(_Range.between(index, end));
          _emphasis(delimiters.sublist(opener.delimiters), mark, make);
          delimiters.removeRange(opener.delimiters, delimiters.length);
          make(opener.at, end, name, said);
          // Every link opener before this one is spent, so the walk back
          // stops at the first a link before this one spent.
          for (final earlier in openers.reversed) {
            if (earlier.image) {
              continue;
            }
            if (!earlier.active) {
              break;
            }
            earlier.active = false;
          }
        }
        index = end;
      case '*' || '_':
        final run = _run(text, index, character);
        final before = index == 0 ? ' ' : text[index - 1];
        final after = index + run < text.length ? text[index + run] : ' ';
        final left =
            !_apart(after) &&
            (!_marked(after) || _apart(before) || _marked(before));
        final right =
            !_apart(before) &&
            (!_marked(before) || _apart(after) || _marked(after));
        delimiters.add(
          _Delimiter(
            index,
            run,
            character,
            character == '*' ? left : left && (!right || _marked(before)),
            character == '*' ? right : right && (!left || _marked(after)),
          ),
        );
        index += run;
      default:
        index += 1;
    }
  }
  _emphasis(delimiters, mark, make);
  // What stands inside markup is part of it. A reference in a link's
  // address says what the address is, not what the reader sees, so what
  // the first walk made there is dropped: that walk ran before the walk
  // that found the link it stands in.
  if (shadows.isEmpty) {
    return (tokens: held, elements: made);
  }
  // The markup that casts a shadow is kept: only what stands inside it.
  // Sorted by start, the furthest any shadow starting before a place
  // reaches says whether one holds it, and the furthest one starting with
  // it reaches says whether one holds more than it.
  shadows.sort((one, other) => one.start - other.start);
  final reaches = <int>[];
  final widest = <int, int>{};
  for (final shadow in shadows) {
    reaches.add(max(reaches.lastOrNull ?? 0, shadow.end));
    widest[shadow.start] = max(widest[shadow.start] ?? 0, shadow.end);
  }
  bool shaded(_Range place) {
    var (low, high) = (0, shadows.length);
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (shadows[middle].start < place.start) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return (low > 0 && reaches[low - 1] >= place.end) ||
        (widest[place.start] ?? -1) > place.end;
  }

  return (
    tokens: [
      for (var at = 0; at < held.length; at += 1)
        if (!shaded(places[at])) held[at],
    ],
    elements: [
      for (var at = 0; at < made.length; at += 1)
        if (!shaded(spots[at])) made[at],
    ],
  );
}

/// The emphasis the delimiter runs come to.
///
/// The standard's own walk: for every run that can close, the nearest run
/// before it that can open and matches makes a pair, two characters where
/// both have two and one otherwise, and everything between the two is
/// spent. A run that pairs with nothing is words.
void _emphasis(
  List<_Delimiter> delimiters,
  bool Function(int, int, String, [Map<String, String>]) mark,
  void Function(int, int, String, [Map<String, String>]) make,
) {
  // Below which no opener can be found for a closer of a given kind, kept
  // per kind once a search has come up empty: the standard's openers_bottom,
  // which keeps a run of closers linear.
  final bottoms = <String, int>{};
  for (var at = 0; at < delimiters.length; at += 1) {
    final closer = delimiters[at];
    if (!closer.live || !closer.closes || closer.length == 0) {
      continue;
    }
    final kind = '${closer.mark}${closer.opens}${closer.length % 3}';
    final bottom = bottoms[kind] ?? 0;
    var paired = false;
    for (var back = at - 1; back >= bottom; back -= 1) {
      final opener = delimiters[back];
      if (!opener.live || !opener.opens || opener.mark != closer.mark) {
        continue;
      }
      // The rule of threes: where either run both opens and closes, the two
      // lengths may not add to a multiple of three unless both are.
      if ((closer.opens || opener.closes) &&
          (opener.length + closer.length) % 3 == 0 &&
          !(opener.length % 3 == 0 && closer.length % 3 == 0)) {
        continue;
      }
      final many = opener.length >= 2 && closer.length >= 2 ? 2 : 1;
      final name = many == 2 ? 'strong' : 'em';
      final from = opener.at + opener.length - many;
      if (mark(from, many, name) & mark(closer.at, many, name)) {
        make(from, closer.at + many, name);
      }
      paired = true;
      opener.length -= many;
      closer.length -= many;
      closer.at += many;
      if (opener.length == 0) {
        opener.live = false;
      }
      if (closer.length == 0) {
        closer.live = false;
      }
      // Everything standing between the two is spent: a run that could have
      // paired across the pair just made cannot pair at all.
      for (var between = back + 1; between < at; between += 1) {
        delimiters[between].live = false;
      }
      if (closer.length == 0) {
        break;
      }
      back = at;
    }
    if (!paired) {
      bottoms[kind] = at;
    }
  }
}

/// How many of [mark] stand at [at].
int _run(String text, int at, String mark) {
  var index = at;
  while (index < text.length && text[index] == mark) {
    index += 1;
  }
  return index - at;
}

/// Where each run of backticks in [text] starts, by its length, in order.
Map<int, List<int>> _runs(String text) {
  final runs = <int, List<int>>{};
  var index = text.indexOf('`');
  while (index >= 0) {
    final run = _run(text, index, '`');
    (runs[run] ??= []).add(index);
    index = text.indexOf('`', index + run);
  }
  return runs;
}

/// Where the run of [length] backticks closing one that ends at [from]
/// stands, among the [runs] of the text, or less than nothing where none
/// does.
int _closing(Map<int, List<int>> runs, int from, int length) {
  final starts = runs[length];
  if (starts == null) {
    return -1;
  }
  var (low, high) = (0, starts.length);
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (starts[middle] < from) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low < starts.length ? starts[low] : -1;
}

/// The reference at [at]: how long it is and what it shows.
(int, String)? _reference(String text, int at) {
  // A name is short, and the search for its end is bounded to say so
  // rather than finding a semicolon a paragraph away and throwing it out.
  var close = at + 1;
  final most = min(at + longest + 1, text.length);
  while (close < most && text[close] != ';') {
    close += 1;
  }
  if (close >= most) {
    return null;
  }
  final shows = entity(text.substring(at + 1, close));
  return shows == null ? null : (close + 1 - at, shows);
}

/// The autolink at [at]: how long it is and where it goes.
(int, String)? _autolink(String text, int at) {
  // Read to the closing angle and no further: a space or another angle
  // before it says this is no autolink.
  var close = at + 1;
  while (close < text.length &&
      text[close] != '>' &&
      text[close] != ' ' &&
      text[close] != '<') {
    close += 1;
  }
  if (close >= text.length || text[close] != '>' || close == at + 1) {
    return null;
  }
  final held = text.substring(at + 1, close);
  if (_scheme.hasMatch(held)) {
    return (close + 1 - at, _encoded(held));
  }
  // An address, which is written without a scheme and reached with one.
  return _mail.hasMatch(held)
      ? (close + 1 - at, 'mailto:${_encoded(held)}')
      : null;
}

final RegExp _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]{1,31}:');
final RegExp _mail = RegExp(
  r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}"
  r'[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$',
);
final RegExp _punctuated = RegExp(r'''[!-/:-@\[-`{-~]''');
final RegExp _spaces = RegExp(r'\s+');

/// Whether [character] is one of the ASCII marks, which is what a backslash
/// may stand before: `\«` is a backslash and a guillemet, where `\*` is an
/// asterisk.
bool _punctuation(String character) => _punctuated.hasMatch(character);

/// Whether [character] is a space, a tab or a line ending.
bool _space(String character) =>
    character == ' ' ||
    character == '\t' ||
    character == '\n' ||
    character == '\r';

/// Whether [character] is what may stand at the end of a line and say
/// nothing: a space, a tab, or the return before a newline.
bool _lineBlank(String character) =>
    character == ' ' || character == '\t' || character == '\r';

/// How many characters the line ending at [at] takes: two for a return and
/// a newline, one for a newline, none where no line ends there.
int _ending(String text, int at) {
  if (at < text.length && text[at] == '\n') {
    return 1;
  }
  if (at + 1 < text.length && text[at] == '\r' && text[at + 1] == '\n') {
    return 2;
  }
  return 0;
}

/// Whether [character] is punctuation to the rules that decide which side of
/// a word a run of asterisks stands on.
///
/// Those rules alone are stated over the whole of Unicode, so a pound sign
/// and a euro sign are punctuation here. What is here is the ASCII marks
/// and the blocks a document of prose actually holds; a letter of any
/// script falls outside all of them, which is the case that has to be right.
bool _marked(String character) {
  final unit = character.codeUnitAt(0);
  if (unit < 0x80) {
    return _punctuation(character);
  }
  return (unit >= 0x00A1 && unit <= 0x00BF) ||
      unit == 0x00D7 ||
      unit == 0x00F7 ||
      (unit >= 0x2010 && unit <= 0x2027) ||
      (unit >= 0x2030 && unit <= 0x205E) ||
      (unit >= 0x2060 && unit <= 0x206F) ||
      (unit >= 0x20A0 && unit <= 0x20CF) ||
      (unit >= 0x2100 && unit <= 0x2BFF) ||
      (unit >= 0x3001 && unit <= 0x303F) ||
      (unit >= 0xFE30 && unit <= 0xFE6F) ||
      (unit >= 0xFF01 && unit <= 0xFF20);
}

/// Whether [character] is a space to the same rules: more than the ASCII
/// ones, since a no-break space holds two words apart as surely as a space.
bool _apart(String character) {
  final unit = character.codeUnitAt(0);
  if (unit < 0x80) {
    return _space(character) || unit == 0x0B || unit == 0x0C;
  }
  return unit == 0x00A0 ||
      unit == 0x1680 ||
      (unit >= 0x2000 && unit <= 0x200A) ||
      unit == 0x2028 ||
      unit == 0x2029 ||
      unit == 0x202F ||
      unit == 0x205F ||
      unit == 0x3000;
}

/// A destination with its escapes read and what an address may not hold
/// written as the bytes it stands for, since what it means is a place rather
/// than markup.
String _unescaped(String held) => _encoded(says(held));

/// [held] as the characters it stands for: an escape says the mark after it
/// and a reference says what it names.
String says(String held) {
  final out = StringBuffer();
  for (var at = 0; at < held.length; at += 1) {
    if (held[at] == r'\' &&
        at + 1 < held.length &&
        _punctuation(held[at + 1])) {
      out.write(held[at + 1]);
      at += 1;
      continue;
    }
    if (held[at] == '&') {
      final shown = _reference(held, at);
      if (shown != null) {
        out.write(shown.$2);
        at += shown.$1 - 1;
        continue;
      }
    }
    out.write(held[at]);
  }
  return out.toString();
}

/// What a destination comes to once what an address may not hold is written
/// as the bytes it stands for. The marks a URL is made of are left alone,
/// and so is a run already written that way, since encoding an encoding says
/// something else.
String _encoded(String held) {
  final out = StringBuffer();
  for (var at = 0; at < held.length; at += 1) {
    final character = held[at];
    if (_safe.hasMatch(character)) {
      out.write(character);
      continue;
    }
    if (character == '%' &&
        at + 2 < held.length &&
        _pairs.hasMatch(held.substring(at + 1, at + 3))) {
      out.write(held.substring(at, at + 3));
      at += 2;
      continue;
    }
    final unit = held.codeUnitAt(at);
    final paired = unit >= 0xD800 && unit <= 0xDBFF && at + 1 < held.length;
    final rune = paired
        ? 0x10000 + ((unit - 0xD800) << 10) + (held.codeUnitAt(at + 1) - 0xDC00)
        : unit;
    for (final byte in _bytes(rune)) {
      out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
    if (paired) {
      at += 1;
    }
  }
  return out.toString();
}

final RegExp _safe = RegExp(r"[A-Za-z0-9\-_.+!*'(),#@?=;:/&$~]");
final RegExp _pairs = RegExp(r'^[0-9A-Fa-f]{2}$');

/// [rune] as the bytes it is written in.
List<int> _bytes(int rune) {
  if (rune < 0x80) {
    return [rune];
  }
  if (rune < 0x800) {
    return [0xC0 | (rune >> 6), 0x80 | (rune & 0x3F)];
  }
  if (rune < 0x10000) {
    return [
      0xE0 | (rune >> 12),
      0x80 | ((rune >> 6) & 0x3F),
      0x80 | (rune & 0x3F),
    ];
  }
  return [
    0xF0 | (rune >> 18),
    0x80 | ((rune >> 12) & 0x3F),
    0x80 | ((rune >> 6) & 0x3F),
    0x80 | (rune & 0x3F),
  ];
}

/// The stretches a walk has claimed, kept in order so that asking whether
/// a position is inside one is a halving rather than a walk of them all.
final class _Spent {
  final List<_Range> _held = [];

  /// Claims [range], which stands apart from everything claimed already.
  void add(_Range range) {
    var low = 0;
    var high = _held.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_held[middle].start < range.start) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    _held.insert(low, range);
  }

  /// Where the walk may read at or after [at]: the end of the claimed
  /// stretch [at] stands in, or [at] itself where it stands in none.
  int past(int at) {
    var low = 0;
    var high = _held.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_held[middle].start <= at) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low == 0) {
      return at;
    }
    final held = _held[low - 1];
    return held.covers(at) ? held.end : at;
  }
}

/// What a picture's words come to when they are read rather than written:
/// `![foo *bar*]` shows `foo bar`, with the asterisks gone, a reference
/// standing for its character, and a picture inside it standing for its
/// own words. Read off the tokens the walk has already made between [from]
/// and [to], with the runs in [delimiters] settled into a scratch so the
/// emphasis inside is found without anything being read again.
String _shown(
  String text,
  int from,
  int to,
  List<Found> held,
  List<_Range> places,
  List<_Delimiter> delimiters,
) {
  final cuts = <(_Range, String?)>[];
  for (var at = 0; at < held.length; at += 1) {
    final place = places[at];
    if (place.start >= from && place.end <= to) {
      final (_, _, name, said) = held[at];
      cuts.add((place, said['shows'] ?? (name == 'img' ? said['alt'] : null)));
    }
  }
  _emphasis(delimiters, (at, length, name, [said = const {}]) {
    cuts.add((_Range(at, length), null));
    return true;
  }, (from, to, name, [said = const {}]) {});
  cuts.sort((one, other) => one.$1.start - other.$1.start);
  final out = StringBuffer();
  var at = from;
  for (final (place, shows) in cuts) {
    if (place.start < at) {
      continue;
    }
    out.write(text.substring(at, place.start));
    if (shows != null) {
      out.write(shows);
    }
    at = place.end;
  }
  out.write(text.substring(at, to));
  return out.toString();
}
