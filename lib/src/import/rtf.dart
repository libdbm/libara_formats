/// RTF imported: read as RTF, then normalized as every import is.
library;

import 'package:libara/libara.dart';

import '../convert.dart';
import '../formats.dart';
import '../limits.dart';
import '../rtf/rtf.dart';
import 'assemble.dart';

/// The elements an import keeps: the shared vocabulary's, and none of the
/// RTF header's.
const Set<String> _kept = {
  'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'pre', 'hr', //
  'li', 'ul', 'ol', 'table', 'tr', 'td', 'th', 'strong', 'em', 'u', 's',
  'sup', 'sub', 'code', 'a', 'footnote', 'img',
};

/// The revisions an RTF file records.
const Set<String> _revisions = {'ins', 'del', 'format'};

/// RTF's importer: its file read with [RTF], its content and elements in
/// reading order made into the normalized LMNL document.
///
/// Where [revisions] is false, every revision is accepted: what was
/// inserted is kept and what was deleted is not. Where it is true, both
/// are kept, and each revision is an annotation over its characters, as
/// `assemble` makes it.
final class RTFImport implements Readable {
  /// RTF's importer, reading within [limits].
  const RTFImport({this.revisions = false, this.limits = standard});

  /// Whether revisions are kept as annotations.
  final bool revisions;

  /// What reading may build.
  final Limits limits;

  @override
  Result<Layered<int>> decode(Sequence<int> form) =>
      RTF(limits: limits).decode(form).flatMap(_imported);

  Result<Layered<int>> _imported(Layered<int> document) {
    final (:content, :offsets, :elements) = projected(document);
    // Where each UTF-16 unit of the content falls, in code points.
    final points = <int>[];
    var point = 0;
    for (var unit = 0; unit <= content.length; unit++) {
      points.add(point);
      if (unit < content.length &&
          !(unit > 0 &&
              _low(content.codeUnitAt(unit)) &&
              _high(content.codeUnitAt(unit - 1)))) {
        point++;
      }
    }
    // A unit's place is that of the character it is part of.
    int at(int unit) => points[unit];
    final spans = <Span>[];
    final noted = <Span>[];
    for (final element in elements) {
      final span = (
        start: at(offsets[element.first]),
        end: at(offsets[element.last]),
        name: element.name,
        said: element.said,
      );
      if (_revisions.contains(element.name)) {
        noted.add(span);
      } else if (_kept.contains(element.name)) {
        spans.add(span);
      }
    }
    if (revisions) {
      return assemble(
        'rtf',
        content,
        spans,
        revisions: [
          for (final span in noted)
            if (span.start < span.end) span,
        ],
        limits: limits,
      );
    }
    return _accepted(content, spans, [
      for (final span in noted)
        if (span.name == 'del') span,
    ]);
  }

  /// [content] and [spans] with the text [deleted] holds taken away, and
  /// each span moved and cut to what is left.
  Result<Layered<int>> _accepted(
    String content,
    List<Span> spans,
    List<Span> deleted,
  ) {
    final characters = content.runes.toList();
    final gone = List.filled(characters.length + 1, false);
    for (final span in deleted) {
      for (var at = span.start; at < span.end; at++) {
        gone[at] = true;
      }
    }
    // Where each place falls once what is gone is taken away.
    final moved = <int>[];
    var kept = 0;
    for (var at = 0; at <= characters.length; at++) {
      moved.add(kept);
      if (at < characters.length && !gone[at]) {
        kept++;
      }
    }
    return assemble(
      'rtf',
      String.fromCharCodes([
        for (final (at, character) in characters.indexed)
          if (!gone[at]) character,
      ]),
      [
        for (final span in spans)
          (
            start: moved[span.start],
            end: moved[span.end],
            name: span.name,
            said: span.said,
          ),
      ],
      limits: limits,
    );
  }
}

bool _high(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

bool _low(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
