part of 'roff.dart';

/// A manual page: the man macro package.
///
/// What the package knows is in its table. A section heading is a heading,
/// a paragraph a paragraph, a tagged paragraph a term and its description,
/// an indented paragraph an item with its tag, and the font requests set
/// their arguments. Everything else a page may say, a condition, a string,
/// a register, a macro of the page's own, is a `#pi` showing nothing.
final class Man implements Syntax {
  /// The man package, reading within [limits].
  const Man({this.limits = standard});

  /// What reading may build.
  final Limits limits;

  @override
  Result<Layered<int>> decode(Sequence<int> form) =>
      _decoded('man', _man, _manNotations, limits, form);

  @override
  Result<Sequence<int>> encode(Layered<int> value) =>
      _encoded('man', _manNotations, value);
}

const Map<String, _Macro> _man = {
  'TH': _Titled('head', ['name', 'section', 'date', 'source', 'manual']),
  'SH': _Lined('h1'),
  'SS': _Lined('h2'),
  'PP': _Paragraph(),
  'LP': _Paragraph(),
  'P': _Paragraph(),
  'HP': _Paragraph(),
  'TP': _Tagged(),
  'IP': _Item(),
  'RS': _Opening('div', kind: 'indent'),
  'RE': _Closing('div'),
  'nf': _Opening('pre', verbatim: true),
  'fi': _Closing('pre'),
  'EX': _Opening('pre', verbatim: true),
  'EE': _Closing('pre'),
  'TS': _Table(),
  'PS': _Opening('pre', kind: 'picture', verbatim: true),
  'PE': _Closing('pre'),
  'EQ': _equation,
  'EN': _Closing('equation'),
  'UR': _Opening('a', attribute: 'href'),
  'UE': _Closing('a'),
  'MT': _Opening('a', attribute: 'href', prefix: 'mailto:'),
  'ME': _Closing('a'),
  'SY': _Opening('pre', kind: 'synopsis', verbatim: true),
  'YS': _Closing('pre'),
  'br': _Breaking(),
  'B': _Font(['strong']),
  'I': _Font(['em']),
  'SM': _Font(['small']),
  'SB': _Font(['small', 'strong']),
  'BI': _Alternating('strong', 'em'),
  'IB': _Alternating('em', 'strong'),
  'BR': _Alternating('strong', 'span'),
  'RB': _Alternating('span', 'strong'),
  'IR': _Alternating('em', 'span'),
  'RI': _Alternating('span', 'em'),
  'sp': _Hidden(),
  'ad': _Hidden(),
  'na': _Hidden(),
  'hy': _Hidden(),
  'nh': _Hidden(),
  'ft': _Hidden(),
  'ne': _Hidden(),
  'in': _Hidden(),
  'ti': _Hidden(),
  'ta': _Hidden(),
  'PD': _Hidden(),
  'DT': _Hidden(),
};

/// How the package represents each element it can, the faces aside.
const Map<String, (String, String)> _manNotations = {
  'p': ('.PP\n', ''),
  'h1': ('.SH ', ''),
  'h2': ('.SS ', ''),
  'li': ('.IP\n', ''),
  'div': ('.RS\n', '.RE\n'),
  'pre': ('.nf\n', '.fi\n'),
  'a': ('.UR ', '.UE\n'),
  'equation': ('.EQ\n', '.EN\n'),
};
