part of 'roff.dart';

/// A paper in the me macro package.
///
/// Its table reads paragraphs, items and bullets, section headings ranked
/// by number or by a step from the last, and the parenthesised containers;
/// running heads and feet, and what else a paper says, are a `#pi` showing
/// nothing.
final class Me implements Format<Layered<int>, Sequence<int>> {
  /// The me package, reading within [limits].
  const Me({this.limits = standard});

  /// What reading may build.
  final Limits limits;

  @override
  Result<Layered<int>> decode(Sequence<int> form) =>
      _decoded('me', _me, _meNotations, limits, form);

  @override
  Result<Sequence<int>> encode(Layered<int> value) =>
      _encoded('me', _meNotations, value);
}

const Map<String, _Macro> _me = {
  'pp': _Paragraph(),
  'lp': _Paragraph(),
  'xp': _Paragraph(),
  'ip': _Item(),
  'np': _Item(),
  'bu': _Item(tag: '•'),
  'sh': _Headed(inline: true),
  'uh': _Headed(level: 1, inline: true),
  'tp': _Hidden(),
  'b': _Font(['strong']),
  'i': _Font(['em']),
  'r': _Font(['span']),
  'bx': _Font(['strong']),
  'u': _Font(['u']),
  'q': _Font(['q']),
  'bi': _Alternating('strong', 'em'),
  'rb': _Font(['strong']),
  '(l': _Opening('pre', verbatim: true),
  ')l': _Closing('pre'),
  '(q': _Opening('blockquote'),
  ')q': _Closing('blockquote'),
  '(f': _Opening('footnote'),
  ')f': _Closing('footnote'),
  '(c': _Opening('div', kind: 'center'),
  ')c': _Closing('div'),
  '(z': _Opening('div', kind: 'keep'),
  ')z': _Closing('div'),
  '(b': _Opening('div', kind: 'keep'),
  ')b': _Closing('div'),
  '(d': _Opening('div', kind: 'delayed'),
  ')d': _Closing('div'),
  '(x': _Ignored(')x'),
  'TS': _Table(),
  'PS': _Opening('pre', kind: 'picture', verbatim: true),
  'PE': _Closing('pre'),
  'EQ': _equation,
  'EN': _Closing('equation'),
  'br': _Breaking(),
  'he': _Hidden(),
  'fo': _Hidden(),
  'eh': _Hidden(),
  'oh': _Hidden(),
  'ef': _Hidden(),
  'of': _Hidden(),
  'sp': _Hidden(),
  'bp': _Breaking('bp'),
  'ne': _Hidden(),
  'ce': _Hidden(),
  'sz': _Hidden(),
  'in': _Hidden(),
  'ta': _Hidden(),
  'ad': _Hidden(),
  'na': _Hidden(),
  'hy': _Hidden(),
  'nh': _Hidden(),
  'lo': _Hidden(),
  'ld': _Hidden(),
  'sc': _Hidden(),
};

/// How the package represents each element it can, the faces aside.
const Map<String, (String, String)> _meNotations = {
  'p': ('.pp\n', ''),
  'h1': ('.sh 1 ', ''),
  'h2': ('.sh 2 ', ''),
  'h3': ('.sh 3 ', ''),
  'h4': ('.sh 4 ', ''),
  'h5': ('.sh 5 ', ''),
  'h6': ('.sh 6 ', ''),
  'li': ('.ip\n', ''),
  'blockquote': ('.(q\n', '.)q\n'),
  'div': ('.(c\n', '.)c\n'),
  'pre': ('.(l\n', '.)l\n'),
  'footnote': ('.(f\n', '.)f\n'),
  'equation': ('.EQ\n', '.EN\n'),
};
