/// Which element names are blocks: what a tree writer keeps whole where an
/// inline crosses one, cutting the inline instead.
library;

/// The names that are blocks: HTML's flow content that is not phrasing
/// content, and the names the other syntaxes here give what stands as a
/// block, which HTML has no name for.
const Set<String> blocks = {
  // HTML.
  'address', 'article', 'aside', 'blockquote', 'body', 'caption', 'dd',
  'details', 'dialog', 'div', 'dl', 'dt', 'fieldset', 'figcaption',
  'figure', 'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'head',
  'header', 'hgroup', 'hr', 'html', 'li', 'main', 'menu', 'nav', 'ol', 'p',
  'pre', 'section', 'summary', 'table', 'tbody', 'td', 'tfoot', 'th',
  'thead', 'tr', 'ul',
  // The other syntaxes: front matter, a displayed equation, a picture, and
  // a LaTeX document's two parts.
  'abstract', 'affiliation', 'author', 'document', 'equation', 'preamble',
  'tikzpicture', 'title',
};

/// The names known to be inlines: HTML's phrasing content, and the names
/// the other syntaxes give what stands within a line. A name in neither
/// table is an inline as well; this one says which are so by design.
const Set<String> inlines = {
  // HTML.
  'a', 'abbr', 'area', 'audio', 'b', 'bdi', 'bdo', 'br', 'button',
  'canvas', 'cite', 'code', 'data', 'datalist', 'del', 'dfn', 'em',
  'embed', 'i', 'iframe', 'img', 'input', 'ins', 'kbd', 'label', 'map',
  'mark', 'math', 'meter', 'noscript', 'object', 'output', 'picture',
  'progress', 'q', 'ruby', 's', 'samp', 'script', 'select', 'slot',
  'small', 'span', 'strong', 'sub', 'sup', 'svg', 'template', 'textarea',
  'time', 'u', 'var', 'video', 'wbr',
  // The other syntaxes: a footnote stands where its mark is.
  'footnote',
};

/// Whether an element called [name] is a block.
bool block(String name) => blocks.contains(name);
