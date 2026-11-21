# Design note: note durations

Status: discussion (2026-11-21), superseded. This note records how the
design was reached. The current notation is in
`2026-11-21-notation-language.md` and `2026-11-21-score.md`, and its
open questions are settled or marked later in
`2026-11-21-iteration-2.md`.

Related: `2026-11-21-colotomy.md`, `../../../references/2026-11-21-reference-gold-2005.md`.

The examples below use the syntax as it was when this note was written
(`(part NAME INSTRUMENT ...)`, options as lists). The current syntax,
with `(part INSTRUMENT :name NAME ...)` and `:key value` options, is in
`2026-11-21-notation-language.md`.

This note covers issue 1 of three notation issues:

1. how to notate the duration of notes more easily (this note)
2. separating display from music (later)
3. gong cycles and their numbering (later)

## Considerations

### The step grid is inefficient

Today every token is one step (ADR 0002), like a step sequencer, and
`(steps-per-pulse N)` sets the grid for the whole piece. A piece with
one fast instrument forces every part onto the finest subdivision, so a
slow part such as the jegogan is mostly `_` tokens. The kempli, which
always plays the same thing, has to be typed out in full.

### The kempli pulse is the unit of time

What we call a pulse is a stroke of the kempli. The kempli is different
from every other instrument: it is always the same, so there is nothing
for the user to notate. The only variation is that it can be silent for
a segment, which is rare and can wait.

So the pulse becomes the only absolute unit of time, and every duration
is an exact fraction or multiple of it. Guile has exact rationals, so a
part of quarter-pulse notes adds up to exactly 8 pulses with no rounding.
The kempli part is implied: one stroke per pulse for the length of the
piece.

### The step is derived, not declared

The step sequencer is still the right picture: a piece is a grid of
equal steps, with notes on it. What changes is where the step size comes
from. A step is the smallest time unit the composition uses. If the
shortest reyong note is 1/4 pulse and nothing is shorter, a step is 1/4
pulse.

So the user writes pulses and durations, and the reader works out the
step: the largest time that divides every note's start, every duration,
and the pulse itself. In practice that is 1 / (the least common multiple
of all the denominators):

| Durations used | Step | Steps per pulse |
|---|---|---|
| 1, 2 | 1 pulse | 1 |
| 1, 1/2 | 1/2 pulse | 2 |
| 2, 1, 1/4 | 1/4 pulse | 4 |
| 1/4, 1/3 | 1/12 pulse | 12 |

The pulse is always a whole number of steps, so pulse lines and numbers
fall on step boundaries. (A piece of only two-pulse notes still has a
step of one pulse.)

This keeps the inside of the program as it is: the reader turns rational
times into integer steps, and the piece, layout and JSON contract keep
working on an integer grid with `steps-per-pulse`, which is now computed
instead of written. ADR 0002 is narrowed rather than reversed: time is
still a grid of equal steps, but a token is no longer one step and the
user no longer chooses the step size.

### Each part has its own pace

Each instrument tends to move at its own pace: the jegogan is slow (about
one note every two pulses), the ugal and gangsa play about one note per
pulse, and the reyong is faster (about four notes per pulse). Writing
every note's duration would be tedious, so a note with no duration
should get a sensible default.

We first put the default on the instrument, then rejected that: the pace
depends on the piece and the section (a pengawak is sparser than a
pengecet), not on the instrument. The default belongs to the part. This
also keeps `instrument` a purely physical description (its keys), with
everything about how it is played in the `part`.

### Don't reinvent LilyPond

The first proposal (a multiplier of the default, `e2*2`) started to
reinvent LilyPond, so we looked at what LilyPond does and borrowed its
concepts, but not its syntax:

| LilyPond | Borrowed as |
|---|---|
| durations carry over until changed (`c4 d e f2`) | the same: a part's first note sets its pace |
| duration attached to the note (`c4`) | `e2:2`, `o:1/2` |
| `\relative` (nearest octave to the previous note) | `(relative ...)` |
| bar check `\|` | `\|` as a pulse check, replacing the `/` separator |
| `\repeat unfold` | `(rep N ...)` (already planned) |
| `\tuplet`, `\scaleDurations` | `(* M ...)` |
| `r` vs `s` (visible rest vs space) | relates to open question 2 in 01 (damped rest vs nothing new) |

Not borrowed:
- **Durations as reciprocals** (`4` = quarter note). That fits a
  whole-note system; ours counts in pulses, so durations are multiples
  of a pulse (`:2`, `:1/4`).
- **LilyPond's surface syntax.** `'`, `,` and `<>` clash with
  Guile's `read` (ADR 0001). The planned parenthesis-free surface syntax
  could bring the LilyPond feel later with a small tokenizer (for
  example `(ice-9 peg)`); the semantics chosen now carry over to it.

With durations that carry over, a multiplier of "the default" stops
making sense, because the current duration depends on what came before.
So durations are absolute, in pulses: `:2` means two pulses on every
instrument.

### Relative octaves fit a five-tone scale

In a five-tone scale the nearest octave is never a tie: the steps up and
down to the same degree add up to 5, so one of them is 2 or fewer. A
bare degree name in `relative` mode therefore always has one meaning,
and most octave numbers can be dropped from melodies.

### Pulse checks replace column alignment

With one token per step, columns line up across parts in the source.
With durations they don't, so a mistake is harder to see. A pulse check
(like LilyPond's bar check) puts the error where the mistake is instead
of at the end of the part.

The pulse check is written `|`, as in LilyPond, rather than the current
`/` separator. `01-notation.md` lists `|` as a character to avoid,
because R7RS reads `|...|` as an escaped symbol. A test with Guile 3.0.9
(2026-11-21) shows this only happens when the `r7rs-symbols` reader
option is enabled, and it is off by default:

```
"5 6 5 4 | 6 5 4 _ |"   -> (5 6 5 4 | 6 5 4 _ |)       ; default
"5 6 5 4 | 6 5 4 _ |"   -> (5 6 5 4 #{ 6 5 4 _ }#)     ; r7rs-symbols on
```

So the reader must make sure `r7rs-symbols` is off when it reads a
file, and a test must check that, or `|` would silently swallow the
tokens between two bars. The same test shows that `e2:2`, `o:1/2`,
`-:3` and `5:1/4` each read as a single symbol.

`/` is then dropped as a separator, so there is one way to mark pulses.

## The notation so far

Changes from `doc/design/01-notation.md`:

- **Time.** The unit is the kempli pulse. Times and durations are
  written as exact rationals in pulses. The option `(steps-per-pulse N)`
  goes: the reader derives the step from the shortest time unit the
  piece uses, and the piece is still an integer step grid inside.
- **Kempli.** Implied: one stroke per pulse, not written in the source.
- **Durations.** A suffix `:D` on a note, key number or rest, with D a
  positive integer or fraction in pulses: `e2:2`, `5:1/4`, `-:3`,
  `·:3`.
- **Carry-over** (proposed, see open question 1). A duration stays in
  force until the next one. A part starts at 1 pulse, so a part's first
  note sets its pace: `a1:2 o1 e1 i1` is four two-pulse notes.
  Existing one-pulse files keep their meaning.
- **Hold.** `_` extends the previous note by the current duration. It
  is still an error at the start of a part or after a rest.
- **Scaling.** `(* M TOKEN ...)` multiplies the durations inside it by
  M, like a tuplet bracket. It nests, and it is how a chord gets a
  duration: `(* 2 (2 5))`.
- **Pulse check.** `|` must fall on a pulse boundary; otherwise it is an
  error that says where the part drifted. It takes no time. It replaces
  the `/` separator, which goes.
- **Relative octaves.** `(relative START TOKEN ...)`: START is a note
  with its octave; each later bare degree name goes to the octave
  nearest the previous note.
- **Repeats.** `(rep N TOKEN ...)`, as already planned. Durations carry
  over from one repetition to the next.
- **Unchanged.** Key numbers (`5`) and note names (`e2`) are both valid;
  chords `(2 5)`; rests `-` and `·`; scale aliases are input names.
- **Length.** Every part must add up to the same number of pulses, and
  that number must be whole.

## A complete example

The music is invented, to show the notation; it is not a transcription.

```scheme
(piece "Duration demo")

(use gong-kebyar)

;; The template has no jegogan yet.
(instrument jegogan selisir  i1 o1 e1 u1 a1)

;; 8 pulses. The kempli is implied: 8 strokes.

;; first note sets the pace: 4 notes x 2 pulses = 8
(part jegogan jegogan  a1:2 o1 e1 i1)

;; relative: o = o2, i = i2, e = e2, o = o2, a = a1, i = i2, a = a1
;; durations: 1 1 1 2 1/2 1/2 1 1 = 8
(part ugal ugal  (relative a1 o i e:2 o:1/2 a i:1 a))

;; key numbers on the template's reyong (1 = e1 ... 12 = u3)
;; 1/4 pulse per note; each | checks that a pulse is complete
(part polos reyong
  (rep 2  5:1/4 6 5 4 | 6 5 4 _ |)
  (rep 2  4 5 4 3 | 5 4 3 _ |))

;; 1 + 3 + 1 + 1 + 1 + 1 = 8
;; P:1 is needed: after -:3 the current duration is 3 pulses
(part gong gong  G -:3 P:1 - P -)

(group "Jegogan"       jegogan)
(group "Ugal"          ugal)
(group "Reyong"        polos)
(group "Gong & kempur" gong)
```

`examples/tenzer1.nts` would change only by removing
`(steps-per-pulse 1)` and the kempli part and group.

## Open questions

1. **Carry-over durations: yes or no?** Most other choices depend on
   this one. If no, `:2` means 2 x the part's pace and parts need a
   setting such as `(part reyong :name polos :pace 1/4 ...)`.
2. **Pulse checks.** `|` is optional wherever a pulse boundary falls.
   Should it ever be required, for example at gong-cycle boundaries
   (issue 3)? Should a different mark check a whole cycle?
3. **Relative mode details.** How to write a jump larger than the
   nearest octave (`a+` / `a-`?); whether `relative` needs an explicit
   start note; how key numbers inside `relative` affect the reference
   note; whether it applies to whole parts or only to groups of tokens.
4. **Chord durations.** `(* 2 (2 5))`, or a duration inside the chord
   such as `(2 5 :2)`. One way is better than two.
5. **Repeats now or later?** Fast parts (the reyong) need them soon: 8
   pulses at 1/4 is 32 tokens.
6. **List heads.** `rep`, `*` and `relative` start lists, and so do
   chords. A stroke set could have a stroke called `rep`, which would make
   a chord `(rep y)` ambiguous. Reserve these names, or mark chords
   differently.
7. **The implied kempli.** The `gong-kebyar` template defines a kempli
   instrument. Is an explicit kempli part still allowed (for example to
   silence a segment), or is it an error? Silencing a segment, e.g.
   `(kempli-off FROM TO)`, can wait.
8. **Piece length.** Must it be a whole number of pulses? The closing
   gong at pulse 9 of `tenzer1.nts` is really pulse 1 of the next cycle;
   that belongs with gong cycles (issue 3).
9. **Error positions.** Errors would report pulse positions such as
   "part `ugal`, pulse 5 1/2" or "ugal ends at pulse 7 1/2, expected 8".
   Settle the format.
10. **Step size.** The derived step is piece-wide. One triplet among
    quarter notes makes the step 1/12 pulse for the whole piece. Is that
    acceptable, should it be per section later, and should the user be
    able to ask for a finer step than the music needs?

## What would change if this is adopted

- New ADR narrowing 0002 (time is still a grid of equal steps, but the
  step is derived and a token is no longer one step) and replacing the
  `steps-per-pulse` option of 0009 with a derived value.
- `01-notation.md`: time section, part tokens and rules, kempli,
  examples; `|` replaces `/` and comes off the list of characters to
  avoid.
- `03-reader.md` must also say that the reader reads with
  `r7rs-symbols` off.
- `02-piece.md`: little change. Events stay in integer steps;
  `steps-per-pulse` is derived by the reader; the kempli part is
  generated.
- `03-reader.md`: token parsing (`:` suffix, `*`, `rep`, `relative`,
  pulse checks), deriving the step and converting to integer steps,
  kempli generation, new error cases, positions in pulses.
- `04-layout.md` and `05-typst-backend.md`: no change needed, since the
  piece is still an integer step grid.
- `templates/`, `examples/`, `tests/golden/` and the manual.
