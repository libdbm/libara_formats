# Pasted markup

What six programs put on the clipboard as HTML when a heading, a paragraph
with emphasis and a link, a nested list, a table with a spanning cell and a
picture are copied: Word for Mac, LibreOffice Writer, Chrome, Safari, Apple
Mail and Google Docs.

These are not captures taken from the programs. They were written on
2026-09-09 to the shape each program is known to write: Word's `mso-list`
paragraphs with the marker between `[if !supportLists]` comments and its
`o:p` elements, LibreOffice's `class="western"` and its paragraph inside
each item, Chrome's `box-sizing` on everything, Safari's `caret-color` and
`-webkit-text-stroke-width`, Mail's `div` per line and `font` elements,
Google Docs' `b` wrapper saying it is not bold and its emphasis represented as
`font-weight:700` on spans. Each should be replaced by a capture from the
program itself the first time one is pasted by hand, and the tests in
`pasted_test.dart` kept passing against it.

To capture one, copy the document in the program and run markwrite's
`tool/pasted.sh <name>`. It writes every flavour on the pasteboard under
`<name>/` and the HTML one over `<name>.html`; the result goes in the table
under "Owner evidence" in `documentation/support.md`.
