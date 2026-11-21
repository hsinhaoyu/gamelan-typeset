# Design note: the notation language, revised after Gold (2005)

Status: agreed for iteration 2 (2026-11-21). The notation of the music,
checked against Gold, *Music in Bali* (2005). Nothing here is
implemented. It will replace `doc/design/01-notation.md`, with ADRs for
the decisions it changes. The goal of the iteration and every decision
are in `2026-11-21-iteration-2.md`, which wins where the two disagree.

Related: `2026-11-21-note-durations.md`, `2026-11-21-colotomy.md`,
`../../../references/2026-11-21-reference-gold-2005.md`, `2026-11-21-score.md` (how the
music is printed), `2026-11-21-internal-representation.md`. The
targets: `../targets/2026-11-21-jaya-semara-pangecet.nts` and
`../targets/2026-11-21-baris.nts`.

## Scope: enough to typeset Jaya Semara and Baris

Balinese music has much more than this notation can express (see "Not
covered"). The goal of this iteration is a notation powerful enough for
two published examples (`2026-11-21-iteration-2.md`):

- the pangecet of "Jaya Semara" as Gold notates it: one 16-pulse gong
  cycle with jegogan, jublag, panyacah, ugal, gangsa norot kotekan,
  gongs and kempli;
- Baris (gilak) as Tenzer notates it: one 8-pulse cycle with reyong
  polos and sangsih, ugal, calung, kempli, gongs and both hands of the
  two kendang, written as syllables.

Every feature below is marked:

- **[iteration 2]**: needed by one of the targets; build it.
- **[later]**: designed so it fits, but not built until a piece needs
  it.

| Feature | Scope |
|---|---|
| Durations in pulses, carried over (`e2:2`, `o3:1/4`) | iteration 2 |
| Hold `_` and rest `-` | iteration 2 |
| Times as exact rationals; the step derived by layout (no `steps-per-pulse`) | iteration 2 |
| Pulse check `\|`, cycle check `\|\|` | iteration 2 |
| Repeats `(rep N ...)` | iteration 2 |
| `(part INSTRUMENT ...)` with optional `:name NAME` | iteration 2 |
| Options written `:key value` (Common Lisp style) | iteration 2 |
| Colotomy with generated gong part; `:colotomy NAME`, `:pickup P` | iteration 2 |
| Implied kempli, one stroke per pulse | iteration 2 |
| Positions as cycle and pulse in error messages | iteration 2 |
| Strokes G (gong), GL (gong lanang), P (kempur), T (klentong) | iteration 2 |
| Stroke n (kelenang) | later |
| `:timekeeper INSTRUMENT`, e.g. the kajar | later |
| `:lines N`: lines inside long cycles | later |
| `(relative ...)` octaves | later |
| Duration scaling `(* M ...)` and chord durations | later |
| Gongs never damped (`:damped no`) | later (matters for playback, not drawing) |
| Departing from the colotomy, changing colotomies, sections | later |
| Longgor forms, other meters from figure 5.11 | later |
| Patterns: `pattern` with `:instrument`, `@NAME`, `(@ NAME ...)` with `:step` and names at the use | iteration 2 |
| Patterns written for a scale (`:scale`), shared between instruments | later |
| Pattern operators `:octave`, `:drop-first`, `:drop-last` | later |
| Scores: `score` with groups and printing options (`2026-11-21-score.md`) | iteration 2 |
| `:damped` forms of degrees and strokes; the score options for Tenzer's layout | iteration 2 |

## What the notation describes

A piece of Balinese gamelan music as layers of parts over a common
pulse, organised in gong cycles. Following Gold:

- The music is stratified: many parts play at once, each at its own
  density. The lower the instrument, the slower its part (pp. 55–56).
- A steady pulse is kept by the kempli (or kajar). Gold calls one
  stroke a beat; this project calls it a pulse (ADR 0009).
- Gongs mark a repeating cycle, the colotomic meter. The gong falls on
  the last pulse, which is also where the next cycle starts (p. 42).
- Pitches are the five degrees nding, ndong, ndeng, ndung, ndang,
  written i o e u a (p. 34).

The notation says what sounds and when. How it is drawn is decided
elsewhere (display is a separate design issue).

## Concepts

| Term | Meaning |
|---|---|
| pulse | One kempli stroke. The unit of time. Gold's "beat". |
| duration | A length of time in pulses: a whole number or a fraction (`2`, `1/4`). |
| step | The smallest unit of time a score prints: one column of its grid, derived by layout. |
| part | One line of music on one instrument. |
| pace | A part's current duration: the duration a note gets when none is written. |
| colotomy | A named cycle: a length in pulses and the gong patterns that mark it (Gold's colotomic meter). |
| cycle | One repetition of the colotomy. Cycle 1 is the first complete one. |
| position | A place in time: cycle and pulse ("cycle 2, pulse 4"), or a pulse number without a colotomy. |
| pickup | Pulses before the first complete cycle, when a piece opens on the gong. |
| pattern | A named list of tokens, written for one instrument, that its parts can play, join, repeat and transform. |
| score | How the music is printed: which parts, in which groups, with which options. A file may have several. |

## Files

A file (`.nts`, ADR 0022) is a sequence of forms read by Guile's `read`
(ADR 0001). The reader reads with the `r7rs-symbols` option off, so
that `|` and `||` are ordinary symbols. Comments start with `;`.

```scheme
(piece TITLE :key value ...)           ; first
(use TEMPLATE) ...                     ; then templates
(scale ...) (strokes ...) (instrument ...) (colotomy ...)   ; definitions
(pattern ...) ...                      ; named patterns
(part ...) ...                         ; the music
(score ...) ...                        ; how it is printed
```

Scales, stroke sets, instruments and colotomies usually come from a
template, so a piece often contains only `piece`, `use`, patterns,
parts and scores.

Everything except `score` describes the music. `score` describes how
it is printed; it is specified in `2026-11-21-score.md`.

## Options

Optional settings are written in Common Lisp style, as `:key value`
pairs:

```scheme
(piece "Jaya Semara: pangecet" :colotomy pangecet-16 :pickup 1)
(part pemade :name polos  o3:1/4 - o3 - || ...)
```

- A key is a symbol that starts with `:` followed by a letter. Guile's
  `read` returns `:pickup` as an ordinary symbol, because its `keywords`
  read option is off by default (checked with Guile 3.0.9); the reader
  keeps it off, as it keeps `r7rs-symbols` off. The notation reader
  recognises the leading colon.
- Each key takes exactly one value. A value with several items is a
  list: `:alias (i nding)`.
- Options come right after a form's positional arguments and before its
  body (tokens or sub-forms). Their order does not matter; each key may
  appear once. An unknown key is an error.
- Durations also use a colon, but never at the start: `o3:1/4` is a note
  with a duration, `:pickup` is a key.
- Options are not lists, so no list head has to be reserved for them.
  The only reserved list head in a part is `rep` (later also `*` and
  `relative`).

## Definitions

### `scale`, `strokes`

Unchanged from `01-notation.md`. A scale names its degrees in ascending
order, with input aliases:

```scheme
(scale selisir
  (ding :alias i) (dong :alias o) (deng :alias e)
  (dung :alias u) (dang :alias a))
```

A degree or stroke may also have `:display STRING`, the form drawn in
the grid, as in `01-notation.md`, and `:damped STRING`, the form for a
note that is cut short. Tenzer writes Baris with syllables, `nang` for
a ringing note and `na'` for a damped one:

```scheme
(dang :alias (a nang) :display "nang" :damped "na'")
```

Which form a note shows is decided by the score (see
`2026-11-21-score.md`, "Which name a note shows"). Without `:damped`
the display form is used for both.

A stroke set names the strokes of unpitched instruments. Following
Gold's symbols (p. 110):

```scheme
(strokes gong-strokes  G GL P T n)   ; gong wadon, gong lanang, kempur,
                                     ; klentong, kelenang
(strokes kempli-strokes K)
(strokes kajar-strokes  K)
```

### `instrument`

```scheme
(instrument NAME SCALE-OR-STROKES NOTE ...)
```

An instrument is its keys (or strokes) in ascending order, and nothing
about how it is played. It has no pace: pace belongs to parts. Ranges
in Gold's figure 2.7 (p. 40), in this project's octave numbering:

| Instrument | Keys |
|---|---|
| jegogan | i1 … a1 (5) |
| jublag / calung | i2 … a2 (5) |
| panyacah | i3 … a3 (5) |
| ugal | o1 … i3 (10) |
| gangsa pemade | o2 … i4 (10) |
| gangsa kantilan | o3 … i5 (10) |
| trompong | a1 … u3 (10) |
| reyong | e2 … u4 (12) |

The `(show-names yes)` option of `01-notation.md` is removed: whether
notes show their names is a display decision, made by layout. An
instrument has no options for now.

Octave numbers are shared by all instruments, so `o2` on the ugal and
`o2` on the jublag are the same pitch (open question 3 of
`01-notation.md`: decided yes). `templates/gong-kebyar.nts` has the
reyong at e1 … u3, an octave below figure 2.7; it is corrected to
e2 … u4 in this iteration.

### `colotomy`

```scheme
(colotomy NAME LENGTH :key value ... (PART INSTRUMENT TOKEN ...) ...)
```

- LENGTH is the cycle in pulses.
- Each `(PART INSTRUMENT TOKEN ...)` is a colotomic part over one cycle,
  in ordinary part tokens. A part shorter than LENGTH repeats; its
  length must divide LENGTH.
- Pulse k of a cycle starts at time k − 1, so the gong on pulse N
  starts at N − 1 and the cycle ends at N.
- `:timekeeper INSTRUMENT` **[later]**: the instrument that plays the
  pulse. Default `kempli`.
- `:lines N` **[later]**: the cycle is written in lines of N pulses.

The Jaya Semara meter (activity 2.4, p. 43) **[iteration 2]**:

```scheme
(colotomy pangecet-16 16
  (gong gong  -:3 P:1 -:3 T:1 -:3 P:1 -:3 G:1))
```

Other examples from Gold's figure 5.11 (p. 110) **[later]**:

```scheme
(colotomy gilak 8      (gong gong  -:3 GL:1 P - P G))
(colotomy bapang 8     (gong gong  - P - T - P - G))
(colotomy gegaboran 16 (gong gong  -:3 P:1 -:3 T:1 -:3 P:1 -:3 G:1))
(colotomy batel 2 :timekeeper kajar
  (gong gong  T:1/2 n P n))
```

## The piece

```scheme
(piece "Jaya Semara: pangecet" :colotomy pangecet-16 :pickup 1)
```

| Option | Default | Meaning |
|---|---|---|
| `:colotomy NAME` | none | The piece's colotomy. Its parts are generated for the whole piece. |
| `:pickup P` | 0 | The piece starts P pulses before the end of a cycle. An error without a colotomy. |

`(steps-per-pulse N)` is gone: layout derives the step.
`(steps-per-system N)` is gone too: it is a printing option, now
`:system-length` on a score.

Without a colotomy, positions are pulse numbers only, and `||` and
`pickup` are errors. With or without one, the timekeeper is implied:
one stroke per pulse, unless the colotomy gives it another pattern.

## Parts

```scheme
(part INSTRUMENT :key value ... TOKEN ...)
```

The instrument comes first. Most parts are the only part on their
instrument, so a part is named after its instrument:

```scheme
(part panyacah  o3 || (rep 2  a3 i3 u3 a3 o3 e3 i3 o3) ||)   ; part `panyacah`
```

When an instrument has several parts, each gets a name with
`:name NAME`:

```scheme
(part pemade :name polos    o3:1/4 - o3 - || ...)
(part pemade :name sangsih  -:1/4 e3 - e3 || ...)
```

Rules:
- Without `:name`, the part's name is the instrument's name.
- Two parts on one instrument without names are an error: "instrument
  `pemade` has two parts; give them names with `:name`".
- Part names are unique in the piece. Groups refer to parts by name.
- Options come before the first token (see "Options").

Rejected alternatives:
- Guessing: treat the first symbol as a name if it is not a valid note
  (`(part pemade polos o3 ...)`). A typo in the first note would
  silently become a name.
- Writing parts inside their group. Groups are display; parts are
  music.

### Tokens

| Token | Meaning |
|---|---|
| `e2`, `ding2` | Strike a note by name (degree or alias, then octave). |
| `5` | Strike key 5 of the instrument (1-based). |
| `e2:2`, `5:1/4` | Strike with a duration in pulses. The duration stays in force for the following tokens until another is written. |
| `_` | Hold: the previous note keeps sounding for one more duration. Gold's cipher dot. |
| `-`, `-:3` | Nothing is struck for one duration; the previous note is damped (see "Rests" below). |
| `(2 5)` | Chord: notes struck together. Takes the current duration. |
| `(rep N TOKEN ...)` | Repeat the tokens N times. Every repetition is identical: the body is read once, with the duration in force before the `rep`. After it, the duration is the body's last. |
| `\|` | Pulse check: must fall on a pulse boundary. Takes no time. |
| `\|\|` | Cycle check: must fall on a cycle boundary. Takes no time. |
| `@NAME` | Play the pattern NAME, which must be written for this part's instrument (see "Patterns"). |
| `(@ NAME :key value ...)` | Play the pattern NAME, changed by operators (see "Patterns"). |
| `(* M TOKEN ...)` **[later]** | Multiply the durations inside by M (like a tuplet). Gives a chord a duration: `(* 2 (2 5))`. |
| `(relative START TOKEN ...)` **[later]** | Bare degree names go to the octave nearest the previous note. |

Everything in the table is **[iteration 2]** except the two rows marked
**[later]**.

A part starts with a duration of 1 pulse, so its first note sets its
pace: `a1:2 o1 e1 i1` is four notes of two pulses.

### Rests

Gold's cipher dot means a beat on which nothing new is struck and the
previous note keeps sounding (pp. 36, 57). That is our `_`, not a rest.
So:

- `_` is the dot: the note sustains. `. 1 . 6 . 3 . 2` is
  `_ i2 _ a2 _ e2 _ o2`.
- `-` means nothing new is struck and the player damps. That is right
  for kotekan, where each player damps so the partner's note sounds
  (p. 59).
- Gongs are never damped (p. 41), so in a gong part `-` only means
  nothing new is struck. This needs an instrument option, e.g.
  `:damped no`, rather than a second rest token. **[later]**: it
  changes what sounds, not what is drawn.
- `·` (middle dot), a synonym of `-` in `01-notation.md`, is dropped: it
  would mislead anyone copying Gold's cipher, where the dot is a hold.

### Rules

- `_` at the start of a part or after `-` is an error.
- Every part, including the pickup, adds up to the same number of
  pulses. Generated parts (timekeeper, colotomy) fill that length.
- `|` and `||` report where a part drifted: "part `ugal`, cycle 2,
  pulse 4 1/2: `||` is not at the end of a cycle".

### The step

The piece stores times as exact rationals in pulses. Layout finds, for
each score, the largest duration that divides every start, every
duration and the pulse it prints: that is the step, one column of the
grid (`2026-11-21-internal-representation.md`). In both targets the
fastest notes are quarter pulses, so the step is 1/4 pulse.

## Patterns

Gamelan melodies are often built from repeated figures. A pattern is a
named list of tokens, written for one instrument, that parts on that
instrument can play, join and repeat.

### Defining a pattern

```scheme
(pattern NAME :instrument INSTRUMENT :short STRING :long STRING  TOKEN ...)
```

```scheme
(pattern polos-1 :instrument pemade :short "1" :long "Norot polos on pokok 1"
  o3:1/4 i3 i3 - | i3 - i3 -)
```

- NAME is the symbol that refers to the pattern. It must not start with
  `:` or `@`.
- `:instrument` says which instrument the pattern is written for. It is
  required. The pattern's notes, key numbers and strokes are checked
  against that instrument's keys where the pattern is defined, and the
  pattern can only be used on that instrument: in its parts, or inside
  other patterns for it.
- `:scale NAME` **[later]**, instead of `:instrument`: a pattern
  written for any instrument with that scale, for figures shared
  between instruments (the pemade and kantilan play the same kotekan an
  octave apart). It may hold note names only, not key numbers, which
  would mean different keys on different instruments; its notes are
  checked against the scale's degrees where it is defined, and against
  the instrument's range where it is used. Used with `:octave` to move
  the figure to another register.
- `:short` and `:long` are descriptive names. They are stored in the
  piece so that a score can print them; whether and how they are
  printed is a display decision. Defaults: `:short` is NAME, `:long` is
  `:short`.
- The body is ordinary part tokens: notes, key numbers, durations, `_`,
  `-`, chords, `rep`, `|`, `||` and other patterns.
- Patterns are defined in a piece or in a template.

### Using a pattern

`@NAME` plays the pattern wherever a token can go. Joining patterns is
writing them one after another; repeating them uses `rep`:

```scheme
(part pemade :name polos
  o3:1/4 - o3 - ||
  (rep 2  @polos-1 @polos-6 @polos-3 @polos-2)
  ||)
```

The prefix keeps patterns apart from notes: a pattern called `a1`
cannot be mistaken for the note `a1`, and a misspelt note is not looked
up as a pattern. Guile reads `@polos-1` as an ordinary symbol (checked
with Guile 3.0.9).

### Operators

The list form applies operators, written as options:

```scheme
(@ polos-1 :step 1)                 ; one scale degree higher
(@ polos-1 :step 1 :short "2")      ; ... named "2" at this use
(@ pokok :octave -1)                ; an octave lower          [later]
(@ pokok :drop-first 1)             ; without its first note   [later]
(@ pokok :drop-last 1)              ; without its last note    [later]
```

| Operator | Meaning |
|---|---|
| `:step N` | Move every note N degrees along the scale (i o e u a, then i in the next octave); key numbers move N keys. Gamelan transposition: the figure keeps its shape on the keys. |
| `:short S`, `:long L` | Names for this use, replacing the pattern's. A moved figure can be named after what it now plays. |
| `:octave N` **[later]** | The same as `:step 5N` on a five-tone scale. |
| `:drop-first N` **[later]** | Remove the first N notes, and everything before the next note kept. The pattern gets shorter by their time. |
| `:drop-last N` **[later]** | Remove the last N notes, from the first of them to the end. The pattern gets shorter by their time. |

- A note, for dropping, is a struck note or chord together with the `_`
  holds that follow it: dropping a note held for two pulses removes
  both pulses. Rests are not notes and are not counted.
- Transposing and dropping are independent, so their order does not
  matter.
- Operators apply only to patterns, not to `rep` blocks or parts.

In Jaya Semara, the polos figures on pokok tones 6 and 2 are the figure
on tone 1 moved one degree down and up, and the sangsih figure on 3 is
its figure on 1 moved two degrees up. Each moved figure is named after
its pokok tone:

```scheme
(pattern polos :instrument pemade
  @polos-1
  (@ polos-1 :step -1 :short "6")  @polos-3
  (@ polos-1 :step 1  :short "2"))
(pattern sangsih :instrument pemade
  @sangsih-1
  (@ sangsih-1 :step -1 :short "6")
  (@ sangsih-1 :step 2  :short "3")
  (@ sangsih-1 :step 1  :short "2"))
```

The whole example is built from patterns: see
`../targets/2026-11-21-jaya-semara-pangecet.nts`.

### Rules

- **A pattern belongs to its instrument.** Key numbers and stroke names
  mean different things on different instruments (key 3 is `a1` on the
  reyong but `u1` on the ugal; two drums may both have a `dag`), so a
  pattern that is not tied to an instrument could play the wrong music
  without an error. With `:instrument`, every pattern is checked where
  it is defined, including patterns that are never used, and a mistake
  is reported at the line where it is.
- **A pattern means the same everywhere.** Its durations start at 1
  pulse unless its first token sets one, and after the pattern the
  part's duration is what it was before.
- **A pattern is used on its own instrument**: in a part on that
  instrument, or inside another pattern for the same instrument. A
  moved figure (`:step`) is checked again where it is used, since the
  move may take it out of the instrument's range.
- **`_` may start a pattern.** It holds the note before the pattern
  where it is used (Gold's pokok starts with a dot).
- **Patterns may contain patterns**, but not themselves, directly or
  through others.
- **Checks are optional.** Most patterns are just notes and need not
  start or end on a pulse or a cycle. A `|` or `||` inside a pattern is
  checked where the pattern is used, against the piece's time, so it
  says where the pattern has to fall.
- **The piece records each use**: part, start, end, nesting level and
  the names in force at that use, so that a score can mark the span
  with its short or long name.

Errors, reported where the pattern is defined:
- no `:instrument`, or an unknown one
- a note, key number or stroke that the instrument does not have
- a pattern for another instrument used inside it

Errors, reported where the pattern is used:
- an unknown pattern; a pattern that contains itself
- a pattern used in a part on another instrument
- a moved note outside the instrument's range
- dropping more notes than the pattern has

## Scores

The top-level `group` form of `01-notation.md` is gone. Groups now live
inside a `score`, which says which parts are printed, in which groups,
with which labels and options. See `2026-11-21-score.md`.

The parts generated by the reader can be printed like any other: the
timekeeper is the part `kempli`, and each colotomy part has the name
its colotomy gives it (`gong`).

## Reading Gold's cipher in this notation

| Gold's cipher | This notation |
|---|---|
| 1 2 3 5 6 | i o e u a (degrees, not keys) |
| a dot under or over a digit (low or high octave) | the octave number of the instrument's key |
| a dot between digits (empty beat, note sustained) | `_` |
| the last note falls on the gong | it ends a cycle: put `\|\|` after it |
| read starting from the gong stroke | a one-pulse pickup on the gong |
| one cipher per beat | one pulse per note, the default pace |

Two traps: our bare numbers are keys, not cipher degrees (`3` is the
instrument's third key, not ndeng); and Gold's dot is a hold, not a
rest.

## Not covered

From Gold, music this notation cannot express yet:

- metrically free passages (gineman, p. 127)
- the pulse doubling within a section (p. 133)
- a change of colotomy between sections, irregular cycles (pp. 127,
  136)
- tempo and dynamics, cues and angsel (breaks)

## Open questions

Every question that was open here is settled for this iteration in
`2026-11-21-iteration-2.md` ("Decisions"), or marked later. In short:
durations carry over; `_` holds and `-` damps; `·` is dropped; every
repetition of a `rep` is identical; gong strokes are `G GL P T` on one
instrument; the timekeeper is the part `kempli`; `rep` and `@` are
reserved; a piece is a pickup (at most one cycle, in whole pulses) plus
whole cycles; positions read `cycle C, pulse P`; every pattern names
its instrument and is used only on it; a pattern's use may carry its
own names.

### Later

- Rests in gong parts (`:damped no`): matters for playback only.
- `relative` mode: syntax for octave jumps; key numbers inside it.
- Chord durations: `(* M (chord))` or inside the chord; reserving `*`
  and `relative` as list heads.
- Lines in long cycles (`:lines 8`): a third level of position, and a
  check for it.
- Departing from the colotomy (an extra kempur stroke, a kempli that
  stops), changing colotomies, sections.
- A pickup longer than a cycle.
- Longgor forms; checking omang and gabor longgor against a source.
- A timekeeper other than the kempli, or with its own pattern.
- Pattern operators `:octave`, `:drop-first`, `:drop-last`.
- Patterns with parameters (a generic norot figure taking the pokok
  tones): left out; it would make patterns into functions.
- Patterns written in degrees only and placed in an octave where they
  are used, like `relative`.
- Patterns written for a scale (`:scale`) and shared between
  instruments, with `:octave` to change register.
