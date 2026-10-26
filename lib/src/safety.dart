/// What a browser would run rather than show, shared by every path that
/// writes HTML from markup it did not read as HTML.
library;

/// The characters a URL parser strips from anywhere in a target.
final RegExp _stripped = RegExp('[\t\n\r]');

/// The control characters and spaces a URL parser strips from its start.
final RegExp _leading = RegExp('^[\u0000- ]+');

/// Whether [target] would run rather than go somewhere: a script or data
/// scheme, however it is cased, padded or broken by a tab or a newline.
bool runs(String target) {
  final scheme = target
      .replaceAll(_stripped, '')
      .replaceFirst(_leading, '')
      .toLowerCase();
  return scheme.startsWith('javascript:') ||
      scheme.startsWith('vbscript:') ||
      scheme.startsWith('data:');
}

/// The elements whose content a browser runs, loads or reads as something
/// other than words.
const Set<String> active = {
  'script', 'style', 'iframe', 'frame', 'frameset', 'object', 'embed', //
  'noscript', 'template', 'base', 'link', 'meta',
};

/// Whether an attribute named [key] saying [value] would run: an event
/// handler, or a target that [runs].
bool handles(String key, String value) {
  final name = key.toLowerCase();
  return name.startsWith('on') || (_targets.contains(name) && runs(value));
}

/// The attributes whose value a browser follows.
const Set<String> _targets = {
  'href', 'src', 'action', 'formaction', 'xlink:href', 'poster', 'data', //
  'background', 'cite', 'srcset',
};
