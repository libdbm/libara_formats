[](head "element")
# NAME
markwrite - edit a document in the notation it was written in
# SYNOPSIS
**markwrite**
\[*options*\]
\[*file*\]
# DESCRIPTION
**markwrite**
opens a document and shows it two ways at once: as the page it will print
and as the text it is written in. The markup stays in the stream. A tag in
XML, a hash in Markdown, a request line in roff and a sawtooth bracket in
LMNL are each a token over the characters that represent them, and what the
document means is derived from the tokens rather than kept beside them.
An edit is made to the stream and nothing else. The tokens after it move
with the text, the tokens inside it are read again, and everything the
page was made of that the edit did not touch is kept. That is what lets
a keystroke in a long book cost what the paragraph it falls in costs.
Seven notations are read and written:
**XML**,
**HTML**,
**Markdown**,
**LMNL**,
and the
**man**,
**ms**
and
**me**
macro packages of roff, with
**eqn**
for the mathematics in the last three.
Word and OpenDocument files are imported and exported through their
own readers and writers rather than as notations.
# OPTIONS
**--look*** name*
Open the document under the named stylesheet rather than the one it
carries. A look is a stylesheet that ships with the application; the
names are those the View menu lists.
**--source**
Open with the source pane showing and the printed pane hidden, which is
how a document is opened for proofreading its markup.
**--export*** kind*
Write the document out as
*pdf*,
*docx*
or
*odt*
and exit without opening a window.
**--version**
Print the version and exit.
# FILES
*~/Library/Application Support/Markwrite/settings*
Where the menus stand and whether documents save themselves, one setting
to a line, readable and mendable by hand.
# NOTES
A request this page's reader does not know shows nothing and is kept as
it was written, so a page from the shelf opens, prints and saves back
byte for byte. Registers, strings, conditionals and macros of a page's
own are among what is kept and not read: a page that represents its words
through them shows less than
**man**(1)
would.
The escapes for glyphs are read by name, so “the em dash — and the
bullet •” show as the characters they name, and \\& stands for the
zero-width space it always has.
# EXAMPLES
Open a Markdown chapter under the Book look:
```
$ markwrite --look Book chapter.md
```

Write a manual page out as a Word document without opening it:
```
$ markwrite --export docx markwrite.1
```

# SEE ALSO
**man**(7),
**groff\_ms**(7),
**groff\_me**(7),
**eqn**(1)
The documentation under
[the repository
](https://github.com/gtnicol/markwrite)

describes the range algebra the editor rests on.
