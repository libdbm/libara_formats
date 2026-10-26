/// What a structural edit asks a syntax to write, said by its class.
///
/// A token's kind is never stored: a start tag and an end tag of `em` both
/// say only that they are called `em`, and which is which is read off the
/// text. A request to write one has no text yet, so it says by its class
/// which it wants. The token the syntax makes for it is a plain range
/// saying what a fresh read would say.
library;

import 'package:libara/libara.dart';

/// A request for a start tag called [name], with [attributes], at [at].
final class Open extends ARange {
  /// A start tag of [name] at [at].
  Open(int at, String name, [Map<String, String> attributes = const {}])
    : super.from(_point(at), _said(name, attributes));
}

/// A request for an end tag called [name] at [at], saying [attributes]
/// where a syntax represents something there, as Markdown represents where a
/// link goes.
final class Close extends ARange {
  /// An end tag of [name] at [at].
  Close(int at, String name, [Map<String, String> attributes = const {}])
    : super.from(_point(at), _said(name, attributes));
}

/// A request for an empty-element tag called [name], with [attributes], at
/// [at].
final class Empty extends ARange {
  /// An empty-element tag of [name] at [at].
  Empty(int at, String name, [Map<String, String> attributes = const {}])
    : super.from(_point(at), _said(name, attributes));
}

/// A request that the text in a range become a comment.
final class Comment extends ARange {
  /// A comment around the text in [range].
  Comment(Range range) : super.from(range, _said('#comment', const {}));
}

Range _point(int at) => switch (Range.create(at, 0)) {
  Success(:final value) => value,
  Failure(:final message) => throw ArgumentError(message),
};

Map<String, Value> _said(String name, Map<String, String> attributes) => {
  '': Str(Text.of(name)),
  for (final MapEntry(:key, :value) in attributes.entries)
    key: Str(Text.of(value)),
};
