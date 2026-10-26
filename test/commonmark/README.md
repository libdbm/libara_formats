# The CommonMark conformance suite

`spec.json` is the official test suite for CommonMark 0.31.2, taken verbatim
from <https://spec.commonmark.org/0.31.2/spec.json>. It is kept here rather
than fetched so that the tests run offline and say the same thing on every
machine and in every year.

Six hundred and fifty-two examples, each a piece of Markdown and the HTML it
must come to. The suite is what makes conformance a number rather than a
claim: `commonmark_test.dart` reads it, sets each example through the codec,
writes the derived structure back out as HTML, and counts.

The renderer lives in the test rather than in the library. What the codec
owes is the structure it derives from the source; what that structure means
in somebody else's vocabulary is a question the suite asks and no part of
this application does.
