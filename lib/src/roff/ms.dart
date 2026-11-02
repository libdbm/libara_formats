part of 'roff.dart';

/// A paper in the ms macro package.
///
/// Its table reads a title, its authors and their affiliations, an
/// abstract, numbered headings, quotations, displays, footnotes and keeps;
/// what else a paper says is a `#pi` showing nothing.
final class Ms implements Syntax {
  /// The ms package, reading within [limits].
  const Ms({this.limits = standard});

  /// What reading may build.
  final Limits limits;

  @override
  Result<Layered<int>> decode(Sequence<int> form) =>
      _decoded('ms', _ms, _msNotations, limits, form);

  @override
  Result<Sequence<int>> encode(Layered<int> value) =>
      _encoded('ms', _msNotations, value);
}

const Map<String, _Macro> _ms = {
  'TL': _Paragraph('title'),
  'AU': _Paragraph('author'),
  'AI': _Paragraph('affiliation'),
  'AB': _Opening('abstract'),
  'AE': _Closing('abstract'),
  'NH': _Headed(),
  'SH': _Headed(level: 1),
  'PP': _Paragraph(),
  'LP': _Paragraph(),
  'XP': _Paragraph(),
  'IP': _Item(),
  'QP': _Paragraph('blockquote'),
  'QS': _Opening('blockquote'),
  'QE': _Closing('blockquote'),
  'RS': _Opening('div', kind: 'indent'),
  'RE': _Closing('div'),
  'DS': _Opening('pre', verbatim: true),
  'LD': _Opening('pre', verbatim: true),
  'ID': _Opening('pre', verbatim: true),
  'CD': _Opening('pre', verbatim: true),
  'BD': _Opening('pre', verbatim: true),
  'DE': _Closing('pre'),
  'FS': _Opening('footnote'),
  'FE': _Closing('footnote'),
  'KS': _Opening('div', kind: 'keep'),
  'KF': _Opening('div', kind: 'keep'),
  'KE': _Closing('div'),
  'TS': _Table(),
  'PS': _Opening('pre', kind: 'picture', verbatim: true),
  'PE': _Closing('pre'),
  'EQ': _equation,
  'EN': _Closing('equation'),
  'br': _Breaking(),
  'B': _Font(['strong']),
  'I': _Font(['em']),
  'R': _Font(['span']),
  'BI': _Alternating('strong', 'em'),
  'BX': _Font(['strong']),
  'UL': _Font(['u']),
  'CW': _Font(['code']),
  'SM': _Font(['small']),
  'LG': _Font(['span']),
  'NL': _Font(['span']),
  'sp': _Hidden(),
  'bp': _Breaking('bp'),
  'ND': _Hidden(),
  'DA': _Hidden(),
  'RP': _Hidden(),
  '1C': _Hidden(),
  '2C': _Hidden(),
  'MC': _Hidden(),
  'ne': _Hidden(),
  'ce': _Hidden(),
  'in': _Hidden(),
  'ta': _Hidden(),
  'TA': _Hidden(),
  'ad': _Hidden(),
  'na': _Hidden(),
  'hy': _Hidden(),
  'nh': _Hidden(),
};

/// How the package represents each element it can, the faces aside.
const Map<String, (String, String)> _msNotations = {
  'p': ('.PP\n', ''),
  'h1': ('.NH 1\n', ''),
  'h2': ('.NH 2\n', ''),
  'h3': ('.NH 3\n', ''),
  'h4': ('.NH 4\n', ''),
  'h5': ('.NH 5\n', ''),
  'h6': ('.NH 6\n', ''),
  'title': ('.TL\n', ''),
  'author': ('.AU\n', ''),
  'affiliation': ('.AI\n', ''),
  'abstract': ('.AB\n', '.AE\n'),
  'li': ('.IP\n', ''),
  'blockquote': ('.QS\n', '.QE\n'),
  'div': ('.RS\n', '.RE\n'),
  'pre': ('.DS\n', '.DE\n'),
  'footnote': ('.FS\n', '.FE\n'),
  'equation': ('.EQ\n', '.EN\n'),
};
