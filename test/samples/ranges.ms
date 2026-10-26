.\" A short paper in the ms macro package, written for the sample corpus.
.\" It is the source of the four other notations beside it.
.RP
.TL
Markup That Stays in the Stream
.AU
The markwrite authors
.AI
The sample corpus
.AB
A word processor usually keeps a tree of its document and writes the
markup out of it when the file is saved. This paper describes the other
arrangement, in which the markup is kept in the character stream as the
writer typed it and everything else is derived from it, and shows that
the arrangement is what lets one editor read seven notations and let a
keystroke cost what its paragraph costs.
.AE
.NH 1
The stream and the ranges over it
.PP
A document is a stream of characters and a set of ranges over it. A
range has a name and attributes, and covers a stretch of the stream; a
token is a range over the characters that represent a piece of markup, and
an element is a range derived from the tokens that open and close it.
The derivation is the codec's own. XML pairs an opening tag with its
closing tag; Markdown pairs a heading's marker with the end of its line;
roff pairs a request line with the next request that ends what it began.
.PP
Nothing derivable is stored. There is no tree, no role on a range, and
no ordinal read off the markup; the point index answers which elements
cover a position, and the resolver answers what a style makes of them.
.NH 1
Why an edit is cheap
.PP
An edit is a replacement of one stretch of the stream by another. Every
range past the edit moves by the difference in length, which is one
number recorded once rather than a write into every range that moved.
The tokens inside the edit are read again by the codec, over a window
that begins where the codec knows its state and ends where the tokens
it reads fall back into step with the tokens that stood, and only what
the window read is dropped and put on again. Everything keyed by a
token's identity, the measured widths, the shaped lines, the resolved
styles, stays warm.
.PP
Where the window cannot be bounded the whole document is read, and the
reading says so. A definition in Markdown that every other block reads,
a delim line in eqn that every later line reads, and the previous face
that roff brings back with
.B \efP
are each read whole, since a window
cannot know what stands outside it.
.NH 2
What it costs
.PP
Measured on a book of six hundred thousand characters, a keystroke in
the middle of a paragraph mutates the model in under seven milliseconds
at the ninety-ninth percentile, against sixty-three for reading the
whole book again. The frame the keystroke lands in is bounded by the
paragraph re-shaped, not the document.
.NH 1
Mathematics in three notations
.PP
A formula is read into one tree whatever it was written in, and what
sets a formula never learns which. MathML is elements and is walked as
they stand; TeX and eqn are text and are read by a reader each. So
.EQ
x sup 2 over y = sqrt {a + b}
.EN
is the same tree as its TeX, and sets the same.
.IP "1."
The reader for eqn shares the TeX reader's tables of symbols and
function names rather than carrying its own.
.IP "2."
A formula in running text stands between the delimiters a delim line
sets, and each such run is an inline element the reader reads.
.KS
.DS
.EQ
sum from i=1 to n x sub i
.EN
.DE
.KE
.NH 1
Conclusion
.PP
Keeping the markup in the stream makes the document what the writer
wrote, makes the codec a range constructor rather than a parser that
owns the document, and makes an edit local. The rest of the editor is
what one can build on that.
.FS
The sample corpus carries this paper in five notations, the others
written from this one by the codecs.
.FE
