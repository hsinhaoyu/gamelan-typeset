# Error messages

When notasi can't read a file, it stops at the first problem and tells
you where it is and what is wrong:

```text
{{#include mistakes/not-a-number.txt}}
```

This says: in the file `not-a-number.gml`, on line 2, the number of
steps per pulse is the word `four`, not a number.

Fix that one problem and try again. If there is another, notasi will
tell you about it next.

## The piece needs a title

```scheme
{{#include mistakes/no-title.gml}}
```

```text
{{#include mistakes/no-title.txt}}
```

The title must be in double quotes: `(piece "Gilak")`.

## Unknown form

```scheme
{{#include mistakes/misspelt-form.gml}}
```

```text
{{#include mistakes/misspelt-form.txt}}
```

The first word inside each pair of brackets says what the line is.
notasi doesn't know `pice`; check the spelling.

## Unknown piece option

```scheme
{{#include mistakes/unknown-option.gml}}
```

```text
{{#include mistakes/unknown-option.txt}}
```

The `piece` line accepts only `steps-per-pulse` and `steps-per-system`
(see [Steps and pulses](steps-and-pulses.md)).

## Not a whole number

```scheme
{{#include mistakes/not-a-number.gml}}
```

```text
{{#include mistakes/not-a-number.txt}}
```

Write the number in digits, with no decimal point: `(steps-per-pulse 4)`.

## Missing bracket

```scheme
{{#include mistakes/missing-bracket.gml}}
```

```text
{{#include mistakes/missing-bracket.txt}}
```

Every `(` needs a matching `)`. Here the `piece` line is never closed,
so notasi reaches the end of the file still looking for the `)`. The
line number points to where it gave up, at the end of the file. The
missing bracket is somewhere before that.

## Not supported yet

```scheme
{{#include mistakes/not-yet.gml}}
```

```text
{{#include mistakes/not-yet.txt}}
```

notasi is still learning to read music. For now a file holds its
`piece` line, scales, stroke sets and instruments, but not yet the
parts they play. This manual will show parts as soon as they work.

## Mistakes in scales and instruments

### No scale with that name

```scheme
{{#include mistakes/undefined-scale.gml}}
```

```text
{{#include mistakes/undefined-scale.txt}}
```

The instrument names a scale that isn't defined. Here `selisir` is
misspelt.

### Not a note of the scale

```scheme
{{#include mistakes/wrong-note-name.gml}}
```

```text
{{#include mistakes/wrong-note-name.txt}}
```

Each note must be a degree (or alias) of the instrument's scale. Here
`dang1` is misspelt.

### No octave number

```scheme
{{#include mistakes/missing-octave.gml}}
```

```text
{{#include mistakes/missing-octave.txt}}
```

Notes on a pitched instrument need an octave: write `dong1`, not `dong`.

### Notes out of order

```scheme
{{#include mistakes/notes-out-of-order.gml}}
```

```text
{{#include mistakes/notes-out-of-order.txt}}
```

List an instrument's notes from lowest to highest, in the order of the
scale: `ding1 dong1 deng1`.

## Other messages

- **no (piece TITLE ...) form**: the file has no `piece` line. Add one
  at the top.
- **the (piece ...) form must come first**: move the `piece` line above
  everything else.
- **a second (piece ...) form**: a file holds one piece. Remove the
  extra `piece` line, or put the second piece in its own file.
- **option … given twice**: remove one of the two settings.
- **… is already defined in this file**: two scales, stroke sets or
  instruments have the same name. Rename or remove one.
- **… ends in a digit, which would be read as an octave**: rename the
  scale degree or alias so it doesn't end in a number.
- **… is used twice in …**: a scale or stroke set uses the same name or
  alias twice.
- **… is listed twice**: a drum or gong lists the same stroke twice.
