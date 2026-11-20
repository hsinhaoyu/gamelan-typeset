# 01 — Notation language

Status: planned, not implemented yet (draft v1)

## Goals

- As concise as possible to type.
- Readable by Guile's built-in `read` with no custom tokenizer.
- Fixed time grid: one token = one step.
- Instruments are lists of symbolic notes; octaves are distinguished.

## Scope: no playback yet

This package is a visualisation tool. It does not play pieces back:
there is no MIDI or audio output. Playback may be added later, so the
notation and the `piece` records must not throw away anything a player
would need. In particular:

- **Every token has a musical meaning, and display is kept separate.**
  Tokens say what sounds and when. How it looks (display forms,
  colours, `/` separators, system breaks) never changes what sounds,
  and nothing that matters for sound is expressed only through display.
- **Notes stay symbolic.** Playback would turn notes into pitches with
  a tuning table looked up by note name (ADR 0003; see the tuning
  tables planned in 06-analysis.md), not by storing frequencies on notes.
- **Durations are exact.** A note's length is its start step plus its
  `_` holds, so a player can tell when each note starts and stops.
- **The open questions affect sound, not just the picture.** Whether a
  rest damps the previous note (open question 2) and whether octave
  numbers are shared across instruments (open question 3) must be
  answered by what the music does, not by what is easiest to draw.
- **Time is in steps, not seconds.** Playback would also need a tempo
  (and tempo changes, which gamelan uses a lot). That would be added as
  new options or forms, without changing what a step is.

## File structure

A file (extension `.gml`) is a sequence of top-level forms. Order matters
only in that a name must be defined before it is used. Comments use `;`.

```scheme
(piece "Example kotekan"
  (steps-per-pulse 4)
  (steps-per-system 16))

(scale selisir
  (ding (alias i) (display "i"))
  (dong (alias o) (display "o"))
  (deng (alias e) (display "e"))
  (dung (alias u) (display "u"))
  (dang (alias a) (display "a")))

(strokes gong-strokes  G)
(strokes kendang-strokes
  (dag (display "D"))
  (dug (display "d"))
  du)

(instrument reyong selisir
  deng1 dung1 dang1 ding2 dong2 deng2 dung2 dang2 ding3 dong3 deng3 dung3)
(instrument ugal   selisir  ding1 dong1 deng1 dung1 dang1 ding2 dong2 deng2 dung2 dang2)
(instrument gong    gong-strokes    G)
(instrument kendang kendang-strokes dag dug du)

(part polos   reyong   1 _ 2 3 / _ 2 3 _ / ...)
(part sangsih reyong   - 5 4 _ / 5 4 _ 5 / ...)
(part gong    gong     1 _ _ _ / - - - - / ...)

(group "Reyong" polos sangsih)
```

## Forms

### `(piece TITLE OPTION ...)`

Exactly one per file, first. Options:

| Option | Default | Meaning |
|---|---|---|
| `(steps-per-pulse N)` | 4 | Steps per pulse (kempli stroke), for pulse numbers and shading |
| `(steps-per-system N)` | whole piece | Where the figure breaks into systems |

### `(scale NAME DEGREE ...)`

Names the degrees of a scale, in ascending order within one octave.
Used to validate instrument notes and for interval analysis.
Unpitched instruments use a stroke set instead (see `strokes` below).

Each DEGREE is either a bare name (`ding`) or a list of a name and
options:

```scheme
(ding (alias i) (display "i"))
```

| Option | Default | Meaning |
|---|---|---|
| `(alias NAME ...)` | none | Other names for the degree. An alias can be used anywhere the degree name can: `i2` means `ding2` in instrument definitions and part tokens. |
| `(display STRING)` | the degree name | Short form shown in the grid. Any text, including Unicode symbols. |

Rules:
- Degree names and aliases must be unique within the scale.
- Names and aliases must not end in a digit, so that the octave number
  in `ding2` is unambiguous.
- The reader resolves aliases: the piece always stores the degree's
  own name, so `i2` and `ding2` are the same note.

### `(strokes NAME STROKE ...)`

Names the strokes of unpitched instruments (gongs, drums, kempli). It
works like `scale`, but strokes have no pitch and no octave, so they are
not in any order.

Each STROKE uses the same syntax and options as a scale degree: a bare
name (`du`) or a name with `alias` and `display` options
(`(dag (display "D"))`).

Rules:
- Stroke names and aliases must be unique within the stroke set.
- A stroke set and a scale cannot share a name, because an instrument
  refers to either by name.
- Stroke names may end in a digit, since there is no octave number.

### `(instrument NAME SCALE-OR-STROKES NOTE ...)`

- With a scale, each NOTE is `DEGREE` followed by an octave number:
  `ding2`. The degree must be in the scale. Notes must be listed in
  ascending pitch order. Octave numbering is relative and local to the
  piece; it is not tied to any absolute pitch.
- With a stroke set, each NOTE is a stroke from that set (`G`, `dag`),
  in any order. The order sets the note indices and the lane order.
- Note indices are 1-based in list order.

### `(part NAME INSTRUMENT TOKEN ...)`

A line of music. Tokens:

| Token | Meaning |
|---|---|
| `3` | Strike note 3 of the instrument (1-based) |
| `ding2` | Strike the note named `ding2` (must exist on the instrument) |
| `_` | Hold: the previous note keeps sounding for this step |
| `-` or `·` | Rest: silence; the previous note is damped. The two are interchangeable. |
| `(2 5)` | Strike notes 2 and 5 together (a chord); members may be numbers or names |
| `/` | Visual separator; ignored; does not take a step |

Rules:
- `_` at the start of a part, or after a rest (`-` or `·`), is an error.
- The duration of a note = 1 + the number of `_` tokens after it.
- Every part must have the same total number of steps in v1 (see open
  questions).

Characters to avoid as tokens: `|` (Guile escaped-symbol syntax), `.`
(pair syntax), `#` (reader extensions). A lone `.` cannot be a rest:
Guile's `read` takes it as pair syntax, so `1 . 2` silently becomes an
improper list and `. .` is a read error. That is why the dot-like rest is
`·` (middle dot, U+00B7; Option+Shift+9 on a Mac US keyboard), which
Guile reads as an ordinary symbol.

### `(group LABEL PART ...)`

Draws several parts in one block of rows, sharing lanes. Used for
interlocking parts (polos + sangsih) and for the two kendang. Parts that
are not in any group are each drawn as their own group, labelled with the
part name.

Optional settings inside a group, after the part names:

```scheme
(group "Reyong" polos sangsih (subtitle "polos + sangsih"))
```

### `(text STRING)`

A caption or explanatory paragraph placed after the preceding figure.
(v2; see open questions.)

## Example: textbook excerpt (one line)

```scheme
(piece "Reyong kotekan" (steps-per-pulse 4))
(scale reyong-4  nang ning nong neng)          ; do mi fa sol
(strokes gong-strokes  G)
(instrument reyong reyong-4  nang1 ning1 nong1 neng1)
(instrument gong gong-strokes G)

(part polos   reyong  1 _ 1 2 / _ 1 2 _ / 2 1 _ 2)
(part sangsih reyong  4 3 4 _ / 3 4 _ 3 / _ 4 3 _)
(part gong    gong    1 - - - / - - - - / - - - -)
(group "Reyong" polos sangsih)
```

## Planned extensions (not v1)

- **Repeats**: `(x 4 1 _ 3 -)` repeats the enclosed tokens 4 times.
- **Looping parts**: a short part (e.g. a 16-step gong cycle) tiles across
  the piece length.
- **Sections**: named parts of a piece (pengawak, pengecet) each with
  their own parts.
- **Syllables**: display names per note for open and damped strokes, e.g.
  `nang` when held vs `na'` when short, derived from whether `_` follows.
- **Surface syntax**: a line-based text format without parentheses.

## Open questions

1. Looping vs equal length: should parts of different lengths be an error
   (v1 choice) or tile automatically?
2. Does a rest (`-` or `·`) mean "actively damped" or just "nothing new"? For Balinese
   playing the difference matters; v1 treats both as silence.
3. Should octave numbers be per instrument or shared across the piece, so
   that the ugal's `ding2` and the reyong's `ding2` are the same pitch?
   v1 assumes shared.
