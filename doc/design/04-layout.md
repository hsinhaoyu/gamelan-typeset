# 04 — Layout

Status: partly implemented (draft v1): slices 1–3 of 4 (the JSON
writer in 05, "Note style", and `layout-piece`); writing figure files
and golden tests (slice 4) are planned (see "Slices"). Modules:
`(notasi style)`, `(notasi layout)`

## Responsibility

Make every *musical* layout decision and produce a figure description
(the JSON contract in 05-typst-backend.md). Layout knows music, not
Typst; the Typst template knows drawing, not music.

## Public interface

```
(layout-piece piece #:key (style (default-style))) → figure
```

**Implemented** (slice 3, `feat/layout`), in `(notasi layout)`, tests in
`tests/layout.scm`. "Systems", "Groups and lanes", "Lane labels" and
"Sizes" below are implemented too.

The figure is the JSON value of 05's contract itself, as `(notasi json)`
writes it: alists with symbol keys for objects, vectors for arrays, the
symbol `null` for null. Writing it out is then just `write-json`
(slice 4), and layout is tested with `equal?`. Keys come in this order:

| Object | Keys |
|---|---|
| figure | `version` (1), `title`, `steps_per_pulse`, `sizes`, `systems`, `caption` |
| sizes | `label_width`, `lane_width`, `step_width`, `row_height` |
| system | `start`, `steps`, `groups` |
| group | `label`, `subtitle`, `lanes`, `voices` |
| voice | `name`, `events` |
| event | `start`, `dur`, `lane`, `text`, `fill`, `text_color`, `continued` |

- `title` is the piece's title. `caption` is `null`: a piece has no
  caption until `text` (v2) or a document (06) supplies one.
- A group's `subtitle` is `null` when it has none; a voice's `name` is
  its part's name as a string.
- An event's `fill` is `null` when the look's fill is `#f` (strokes).

`style` says how notes look (see "Note style" below). It is optional;
`(default-style)` is used when it is left out. In v1 it is set from
Guile (and later from the command line); a `style` form in the notation
is an open question.

## Decisions layout makes

### Systems

- Split the piece into systems of `steps-per-system` steps (default: one
  system for the whole piece). The last system may be shorter. A piece
  of length 0 has no systems.
- Events crossing a system boundary are cut at every boundary they
  cross. The first piece has `continued: false`; every later piece has
  `continued: true`, so it can be drawn differently (e.g. no label,
  open left edge).
- Each system carries its absolute start step, so pulse numbers continue
  across systems; an event's `start` is relative to its system.

### Groups and lanes

- One block of rows per group, in the piece's group order. Every group
  appears in every system, with one voice per part in the group's part
  order, even when it has no events in that system.
- `lanes` is the group's lane labels (see "Lane labels"), top first,
  from `group-lanes`; they are the same in every system. An event's
  `lane` is the 0-based index of its note in that list.
- A chord gives one event per note, with the same start and duration.
  A voice's events are sorted by start, then by lane.
- Each event's `text`, `fill` and `text_color` come from
  `(note-look style instrument note)` (see "Note style").
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

**Implemented** (slice 2, `feat/layout-style`). Module `(notasi style)`,
which depends only on `(notasi piece)`; tests in `tests/style.scm`.
Layout (slice 3) imports it.

How each note looks is decided by a **colour scheme**: a procedure
`(scheme style instrument note) → look`. A **look** is an immutable
record whose fields go straight into the JSON event:

| Field | Accessor | Meaning |
|---|---|---|
| fill | `look-fill` | the note's colour as a hex string, or `#f` for no box |
| text | `look-text` | the text in the note |
| text color | `look-text-color` | the text's colour as a hex string |

with `make-look` and `look?`. `(note-look style instrument note)`
calls the style's scheme and returns the look.

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
- The text colour is `(text-color-for fill)`: white (`#ffffff`) if its
  WCAG contrast ratio with the fill is at least 3:1 (the minimum for
  bold text, which note text is), otherwise near-black (`#222222`).
  Contrast uses WCAG relative luminance of sRGB:
  each channel c/255 is linearised as c/12.92 if ≤ 0.04045, else
  ((c + 0.055)/1.055)^2.4; L = 0.2126 R + 0.7152 G + 0.0722 B; and the
  ratio of two luminances is (L1 + 0.05)/(L2 + 0.05), lighter over
  darker. So strong colours get white text and light ones dark text.
- **Strokes are shown as a character only**: no box (`fill` is `#f`),
  the stroke's display form (or its name) in near-black (`#222222`). `(dag (display
  "D"))` in the stroke set sets the character.
- Parts are not told apart: polos and sangsih in one group are drawn in
  the same pitch colours, so the group shows the composite melody.
  The group's label and subtitle say which parts it holds.

**The style** is an immutable record made with
`(make-style #:key scheme palette degree-colors)`; `(default-style)` is
`(make-style)`. Predicate `style?`; accessors `style-scheme`,
`style-palette`, `style-degree-colors`.

| Field | Default | Meaning |
|---|---|---|
| `scheme` | `'by-degree` | a scheme name, or a procedure `(style instrument note) → look` |
| `palette` | `'dark2` | a palette name (below), or a list of colours |
| `degree-colors` | `'()` | overrides by degree name, e.g. `((ding . "#000000"))` |

`make-style` checks its arguments and raises an `&error` whose
irritants include the bad value for: an unknown scheme name (anything
that is neither `by-degree` nor a procedure), an unknown palette name,
an empty colour list, a colour that is not a string `#rrggbb` (hex
digits in either case), or a `degree-colors` entry that is not
`(SYMBOL . COLOUR)`, and for a `palette` or `degree-colors` of the
wrong type (`#:palette 42`, `#:degree-colors 'x`). For a malformed
entry, the irritants include the entry or its bad part. A degree name
that no scale has is allowed; it is just never used. Keys are degree
names, not aliases: `(i . "#000000")` overrides nothing, even where
`i` is an alias of `ding`. Overrides apply to pitched notes only;
strokes are always drawn as a character. The accessors return resolved values: `style-scheme`
a procedure (`by-degree` for the name), `style-palette` the list of
colours, all colours in lowercase. `by-degree` is exported, so a
custom scheme can fall back on it.

The colours notasi makes (palettes, overrides, text colours) are
lowercase `#rrggbb` strings, and a stroke's `fill` is `#f`. A custom
scheme's look is used as it is.

**Palettes.** The eight qualitative palettes of ColorBrewer (Cynthia
Brewer, colorbrewer2.org), at their largest size. `(palette-names)`
lists them in this order; `(palette-colors NAME)` returns a palette's
colours as a list (an `&error` for an unknown name).

| Name | Colours |
|---|---|
| `dark2` | `#1b9e77 #d95f02 #7570b3 #e7298a #66a61e #e6ab02 #a6761d #666666` |
| `set1` | `#e41a1c #377eb8 #4daf4a #984ea3 #ff7f00 #ffff33 #a65628 #f781bf #999999` |
| `set2` | `#66c2a5 #fc8d62 #8da0cb #e78ac3 #a6d854 #ffd92f #e5c494 #b3b3b3` |
| `set3` | `#8dd3c7 #ffffb3 #bebada #fb8072 #80b1d3 #fdb462 #b3de69 #fccde5 #d9d9d9 #bc80bd #ccebc5 #ffed6f` |
| `paired` | `#a6cee3 #1f78b4 #b2df8a #33a02c #fb9a99 #e31a1c #fdbf6f #ff7f00 #cab2d6 #6a3d9a #ffff99 #b15928` |
| `accent` | `#7fc97f #beaed4 #fdc086 #ffff99 #386cb0 #f0027f #bf5b17 #666666` |
| `pastel1` | `#fbb4ae #b3cde3 #ccebc5 #decbe4 #fed9a6 #ffffcc #e5d8bd #fddaec #f2f2f2` |
| `pastel2` | `#b3e2cd #fdcdac #cbd5e8 #f4cae4 #e6f5c9 #fff2ae #f1e2cc #cccccc` |

The values are copied into the code with ColorBrewer's attribution, as
its licence (Apache 2.0) requires. `dark2` is the default: strong
colours that mostly take white text (all but its green and yellow).

### Sizes

- Step column width, row height and label column width are layout
  outputs, because the background and note layers in Typst must use
  identical fixed column widths (see 05). Widths are estimated from the
  number of characters, for the whole figure (all systems):
  - `label_width` (group labels and subtitles): 0.6em × the longest
    group label or subtitle + 1.5em.
  - `lane_width` (lane labels): 0.52em × the longest lane label + 1em.
  - `step_width` `"2.6em"` and `row_height` `"1.5em"`, fixed.
  - Lengths are strings in `em` with one decimal, even when whole,
    rounded to the nearest, ties upward: `"10.5em"`, `"3.6em"`,
    `"2.0em"`. With no groups the longest label counts as 0.
  - Sizes come from the piece's groups and their lanes, whether or not
    there are systems (a piece of length 0 still has its groups).
  These match the prototype (`polos + sangsih` → 10.5em, `neng1` →
  3.6em) and will be tuned against real Typst output in the backend
  milestone.

## Slices

Milestone 3 (`feat/json` + `feat/layout` in the build order) is built
in four slices, each its own branch and PR into `dev`, started with
`/start-milestone <branch>`:

1. **Implemented.** `feat/json`: the JSON writer `(notasi json)`, as specified under
   "JSON writing" in 05.
2. **Implemented.** `feat/layout-style`: "Note style": the ColorBrewer palettes,
   `make-style` and `default-style`, the `by-degree` scheme and the
   text-colour contrast rule.
3. **Implemented.** `feat/layout`: `layout-piece` → figure: systems and cut events,
   groups and lanes, events with their look, sizes.
4. `feat/layout-golden`: writing the figure as JSON (05's contract),
   `make golden`, and golden tests for every file in `examples/`.

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
