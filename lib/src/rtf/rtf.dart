import 'package:libara/libara.dart';

import '../formats.dart';
import '../lexing.dart';
import '../limits.dart';
import 'pages.dart';
import 'read.dart';
import 'scan.dart';

/// RTF, as Word, LibreOffice, TextEdit, Pages and WordPad write it, kept as
/// written.
///
/// A document is read from the file's bytes, each item the code point of
/// the same value, as `Text.of(String.fromCharCodes(bytes))` gives them:
/// RTF is defined over bytes, and the data after `\bin` is raw bytes a
/// decoding would change. A form holding any other item, or not beginning
/// with `{\rtf`, is refused.
///
/// Layer 2 holds one token for each brace, each control word, under its
/// own name and saying its parameter as `value`, and with its data where it
/// is `\bin`, each control symbol, `#symbol`, each `\'hh`, `#escape`, each
/// `\uN` with its fallback, `#unicode`, each run of text below 128,
/// `#text`, each byte past 127, `#character`, and each run of line breaks,
/// which RTF ignores, `#break`. A token that stands for characters says
/// them as `shows`, through the code page the header sets. What does not
/// scan is an `#error`.
final class RTF implements Syntax {
  /// The RTF syntax, reading within [limits].
  const RTF({this.limits = standard});

  /// What reading may build.
  final Limits limits;

  @override
  Result<Layered<int>> decode(Sequence<int> form) => bytes('rtf', form).flatMap(
    (form) => _signed(form)
        ? decoded('rtf', _Grammar(limits), limits, form)
        : const Failure(Kind.syntax, r'rtf: the text does not begin {\rtf'),
  );

  /// [value]'s text, where it was read as RTF, and otherwise a refusal:
  /// RTF is read, and imported, but nothing is written as RTF.
  @override
  Result<Sequence<int>> encode(Layered<int> value) => value.grammar is _Grammar
      ? Success(value.items)
      : const Failure(
          Kind.invalid,
          'rtf: only a document read as RTF is written as RTF',
        );
}

/// Whether [form] begins `{\rtf`.
bool _signed(Sequence<int> form) {
  const signature = r'{\rtf';
  if (form.length < signature.length) {
    return false;
  }
  for (var at = 0; at < signature.length; at++) {
    if (form.item(at) != signature.codeUnitAt(at)) {
      return false;
    }
  }
  return true;
}

/// How far into the text the header is looked for the code page.
const _header = 1024;

/// The code page [document]'s header sets: MacRoman where it says `\mac` or
/// `\ansicpg10000`, and Windows-1252 otherwise.
Page _page(Layered<int> document) {
  final start = String.fromCharCodes(document.items.slice(0, _header).items);
  return RegExp(r'\\mac(?![a-z])|\\ansicpg10000(?!\d)').hasMatch(start)
      ? Page.mac
      : Page.windows;
}

final class _Grammar implements Grammar<int> {
  const _Grammar(this.limits);

  final Limits limits;

  @override
  int get depth => 3;

  /// At layer 2, the tokens, with what stands within a hidden destination
  /// showing nothing; at layer 3, the elements. Each is read whole, as
  /// [affected] asks.
  @override
  Derived derive(Layered<int> document, int layer, Range region) {
    if (layer == 3) {
      return elements(document, region);
    }
    final (:ranges, :diagnostics) = tokens(
      document,
      region,
      limits,
      scanner(_page(document)),
    );
    return (ranges: hidden(ranges), diagnostics: diagnostics);
  }

  /// The whole text at layer 2, since whether a token's text is hidden
  /// depends on the groups around it, and every token at layer 3.
  @override
  Range affected(Layered<int> document, int layer, Range changed) => layer == 2
      ? span(0, document.items.length)
      : span(0, document.layer(2).length);

  /// No structural edit: RTF is read, not edited.
  @override
  Result<Derivation<int>> edit(Layered<int> document, Edit<int> change) =>
      const Failure(Kind.invalid, 'rtf: an RTF document is not edited');

  /// No text edit: RTF is read, not edited.
  @override
  Result<Change<int>> valid(Layered<int> document, Edit<int> change) =>
      const Failure(Kind.invalid, 'rtf: an RTF document is not edited');

  /// [text] as it stands, since nothing is typed into RTF.
  @override
  List<int> escaped(List<int> text, {bool raw = false}) => text;

  /// Nothing is moved.
  @override
  Crossing crossing(Layered<int> document, int layer, ARange range) =>
      Crossing.refuse;
}
