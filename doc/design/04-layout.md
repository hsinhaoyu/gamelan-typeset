# 04 — Layout

Status: planned, not implemented yet (draft v1). Module: `(notasi layout)`

## Responsibility

Make every *musical* layout decision and produce a figure description
(the JSON contract in 05-typst-backend.md). Layout knows music, not
Typst; the Typst template knows drawing, not music.

## Public interface

```
(layout-piece piece #:style style) → figure   ; plain Scheme data (alists/vectors)
```

`figure` is converted to JSON by `(notasi typst)`. Keeping it plain
data makes layout easy to test with `equal?`.

`style` says how notes look (see "Note style" below). It is optional;
`(default-style)` is used when it is left out. In v1 it is set from
Guile (and later from the command line); a `style` form in the notation
is an open question.

## Decisions layout makes

### Systems

- Split the piece into systems of `steps-per-system` steps (default: one
  system for the whole piece).
- Events crossing a system boundary are cut into two events. The second
  half is marked `continued: true` so it can be drawn differently
  (e.g. no label, open left edge).
- Each system carries its absolute start step, so pulse numbers continue
  across systems.

### Groups and lanes

- One block of rows per group, in source order.
- Lanes are the notes the group actually uses, highest pitch at the top
  (`group-lanes` from `(notasi piece)`). Unused instrument notes are not drawn,
  which keeps figures compact.
- Option for later: `#:all-lanes #t` to draw the instrument's full range.
- Stroke instruments: one lane per stroke type, in instrument order.
- A group's pitched parts all play one instrument (02-piece.md,
  invariant 6), so its pitched lanes never mix two instruments' ranges.

### Lane labels

Lane labels show the display form followed by the octave number
(`i2`) in small grey text; a stroke's label is its display form.

### Note style

How each note looks is decided by a **colour scheme**: a procedure
from an instrument and a note to the note's look, three values that
go straight into the JSON event:

| Value | Meaning |
|---|---|
| `fill` | the note's colour as a hex string, or `#f` for no box |
| `text` | the text in the note |
| `text_color` | the text's colour as a hex string |

Layout calls the scheme for every event and knows nothing about
colours itself. Adding a way of colouring (by part, by octave, …) means
adding a scheme; the JSON and the Typst template don't change. Colours
are chosen in Guile and written as hex strings; the Typst side never
picks colours (ADR 0005).

**v1 has one scheme, `by-degree`** (ADR 0017):

- **Pitched notes are coloured by scale degree.** Degree *k* of the
  scale (0-based, in scale order: ding 0, dong 1, …) gets colour *k* of
  the palette, in every octave and on every instrument, so a pitch has
  the same colour on the ugal and the reyong. With more degrees than
  colours, the palette repeats.
- The note's text is the degree's display form (`"i"` for `ding`, or
  the degree name if the scale sets none), without the octave number,
  since the lane already shows the octave.
- The text colour is white or near-black, whichever contrasts more with
  the fill (by relative luminance), so light palettes stay readable.
- **Strokes are shown as a character only**: no box (`fill` is `#f`),
  the stroke's display form (or its name) in near-black. `(dag (display
  "D"))` in the stroke set sets the character.
- Parts are not told apart: polos and sangsih in one group are drawn in
  the same pitch colours, so the group shows the composite melody.
  The group's label and subtitle say which parts it holds.

**The style** is a record made with
`(make-style #:key scheme palette degree-colors)`:

| Field | Default | Meaning |
|---|---|---|
| `scheme` | `by-degree` | a scheme name, or a procedure for a custom scheme |
| `palette` | `dark2` | a palette name (below), or a list of hex strings |
| `degree-colors` | `()` | overrides by degree name, e.g. `((ding . "#000000"))` |

**Palettes.** The eight qualitative palettes of ColorBrewer (Cynthia
Brewer, colorbrewer2.org), at their largest size: `dark2` (8),
`set1` (9), `set2` (8), `set3` (12), `paired` (12), `accent` (8),
`pastel1` (9), `pastel2` (8). The hex values are copied into the code,
with ColorBrewer's attribution as its licence (Apache 2.0) requires.
`dark2` is the default because white text stays readable on all its
colours.

### Sizes

- Step column width, row height and label column width are layout
  outputs. The label width is estimated from the longest label
  (characters × an average width), because the background and note layers
  in Typst must use identical fixed column widths (see 05).

## Not layout's job

- Drawing, fonts, page size: Typst template.
- Validation: reader.

## Open questions

- A `style` form in the notation (e.g. `(style (palette set2))`), so a
  piece or a template can carry its look. v1 sets the style from Guile
  only.
- A legend: one swatch per degree, beside the figure or in the caption.
- More schemes: by part (the old design, useful for showing
  interlocking), by octave (e.g. light and dark of one hue, which the
  `paired` palette suits), or per instrument.

- Should colotomic strokes (gong) also be drawn as a full-height line
  across the system? Layout would emit a `markers` list per system.
- Automatic system breaks at gong strokes instead of a fixed length.
