# 04 — Layout

Status: planned, not implemented yet (draft v1). Module: `(gamelan layout)`

## Responsibility

Make every *musical* layout decision and produce a figure description
(the JSON contract in 05-typst-backend.md). Layout knows music, not
Typst; the Typst template knows drawing, not music.

## Public interface

```
(layout-piece piece #:style style) → figure   ; plain Scheme data (alists/vectors)
```

`figure` is converted to JSON by `(gamelan typst)`. Keeping it plain
data makes layout easy to test with `equal?`.

## Decisions layout makes

### Systems

- Split the piece into systems of `steps-per-system` steps (default: one
  system for the whole piece).
- Events crossing a system boundary are cut into two events. The second
  half is marked `continued: true` so it can be drawn differently
  (e.g. no label, open left edge).
- Each system carries its absolute start step, so beat numbers continue
  across systems.

### Groups and lanes

- One block of rows per group, in source order.
- Lanes are the notes the group actually uses, highest pitch at the top
  (`group-lanes` from `(gamelan piece)`). Unused instrument notes are not drawn,
  which keeps figures compact.
- Option for later: `#:all-lanes #t` to draw the instrument's full range.
- Stroke instruments: one lane per stroke type, in instrument order.

### Text in cells

- Pitched notes show the degree name (`ding`), without the octave number,
  since the lane position already shows the octave.
- Strokes show the stroke name.
- Lane labels show the full note name (`ding2`) in small grey text.

### Colours

- Each part gets a colour. Default palette assigned by group role:
  - interlocking parts in one group get two contrasting colours
  - melody instruments: dark blues
  - colotomic: warm browns, gong strongest
  - drums: purples
- A `style` alist can override any colour by part name.
- Colours are chosen in Guile and written as hex strings; the Typst side
  never picks colours.

### Sizes

- Step column width, row height and label column width are layout
  outputs. The label width is estimated from the longest label
  (characters × an average width), because the background and note layers
  in Typst must use identical fixed column widths (see 05).

## Not layout's job

- Drawing, fonts, page size: Typst template.
- Validation: reader.

## Open questions

- Should colotomic strokes (gong) also be drawn as a full-height line
  across the system? Layout would emit a `markers` list per system.
- Automatic system breaks at gong strokes instead of a fixed length.
