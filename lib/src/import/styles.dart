/// What a word processor's paragraph style is in the shared vocabulary:
/// one table for every importer and word processor format.
library;

/// Each style's name, lower case with its spaces taken out, and the element
/// a paragraph of that style is, with the kind of list it is an item of.
const Map<String, ({String name, String? list})> _styles = {
  'heading1': (name: 'h1', list: null),
  'heading2': (name: 'h2', list: null),
  'heading3': (name: 'h3', list: null),
  'heading4': (name: 'h4', list: null),
  'heading5': (name: 'h5', list: null),
  'heading6': (name: 'h6', list: null),
  'title': (name: 'h1', list: null),
  'normal': (name: 'p', list: null),
  'body': (name: 'p', list: null),
  'bodytext': (name: 'p', list: null),
  'default': (name: 'p', list: null),
  'listbullet': (name: 'li', list: 'ul'),
  'bulleted': (name: 'li', list: 'ul'),
  'listnumber': (name: 'li', list: 'ol'),
  'numbered': (name: 'li', list: 'ol'),
  'quote': (name: 'blockquote', list: null),
  'blocktext': (name: 'blockquote', list: null),
  'code': (name: 'pre', list: null),
  'preformatted': (name: 'pre', list: null),
  'htmlpreformatted': (name: 'pre', list: null),
  'horizontalline': (name: 'hr', list: null),
};

/// The element a paragraph of [style] is, with the kind of list it is an
/// item of, if any: a heading of [level] where the file gives the paragraph
/// an outline level from 1 to 6, whatever its style, and otherwise what the
/// table says of the style's name, case and spaces ignored. A name the
/// table does not know is a paragraph.
({String name, String? list}) styled(String style, {int? level}) {
  if (level != null && level >= 1 && level <= 6) {
    return (name: 'h$level', list: null);
  }
  return _styles[style.toLowerCase().replaceAll(' ', '')] ??
      (name: 'p', list: null);
}
