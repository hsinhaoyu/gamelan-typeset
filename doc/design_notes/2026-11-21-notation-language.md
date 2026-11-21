# Design note: the notation language, revised after Gold (2005)

Status: discussion (2026-11-21). A description of the notation as it
stands after the duration and colotomy notes, checked against Gold,
*Music in Bali* (2005). Nothing here is implemented. When it is agreed,
it replaces `doc/design/01-notation.md`, with ADRs for the decisions it
changes.

Related: `2026-11-21-note-durations.md`, `2026-11-21-colotomy.md`,
`2026-11-21-reference-gold-2005.md`. A complete example:
`2026-11-21-jaya-semara-pangecet.nts`.

Marked **(proposed)** are choices made here that the earlier notes left
open. They are listed again at the end.

## Scope: enough to notate Jaya Semara

Balinese music has much more than this notation can express (see "Not
covered"). For now the goal is a notation powerful enough for one
non-trivial piece: the pangecet of "Jaya Semara" as Gold notates it
(one 16-pulse gong cycle with jegogan, jublag, panyacah, ugal, gangsa
norot kotekan, gongs and kempli). The rest of the piece appears in the
book only as a listening guide, and its kebyar sections are not
metrically regular, so they are out of scope.

The acceptance test: `2026-11-21-jaya-semara-pangecet.nts` reads
without errors and `notasi render` draws it.

Every feature below is marked:

- **[Jaya Semara]**: needed for the target piece; build it.
- **[later]**: designed so it fits, but not built until a piece needs
  it.

| Feature | Scope |
|---|---|
| Durations in pulses, carried over (`e2:2`, `o3:1/4`) | Jaya Semara |
| Hold `_` and rest `-` | Jaya Semara |
| Step derived by the reader (no `steps-per-pulse`) | Jaya Semara |
| Pulse check `\|`, cycle check `\|\|` | Jaya Semara |
| Repeats `(rep N ...)` | Jaya Semara |
| `(part INSTRUMENT ...)` with optional `:name NAME` | Jaya Semara |
| Options written `:key value` (Common Lisp style) | Jaya Semara |
| Colotomy with generated gong part; `:colotomy NAME`, `:pickup P` | Jaya Semara |
| Implied kempli, one stroke per pulse | Jaya Semara |
| Positions as cycle and pulse in error messages | Jaya Semara |
| Strokes G (gong), P (kempur), T (klentong) | Jaya Semara |
| Strokes GL (gong lanang), n (kelenang) | later |
| `:timekeeper INSTRUMENT`, e.g. the kajar | later |
| `:lines N`: lines inside long cycles | later |
| `(relative ...)` octaves | later |
| Duration scaling `(* M ...)` and chord durations | later |
| Gongs never damped (`:damped no`) | later (matters for playback, not drawing) |
| Departing from the colotomy, changing colotomies, sections | later |
| Longgor forms, other meters from figure 5.11 | later |
| Patterns: `pattern`, `@NAME`, `(@ NAME ...)` with `:step`, `:octave`, `:drop-first`, `:drop-last` | Jaya Semara |
| Display forms (full and short names) | later, with the display issue |

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
| step | The smallest unit of time the piece uses, derived by the reader. The piece is a grid of steps inside the program. |
| part | One line of music on one instrument. |
| pace | A part's current duration: the duration a note gets when none is written. |
| colotomy | A named cycle: a length in pulses and the gong patterns that mark it (Gold's colotomic meter). |
| cycle | One repetition of the colotomy. Cycle 1 is the first complete one. |
| position | A place in time: cycle and pulse ("cycle 2, pulse 4"), or a pulse number without a colotomy. |
| pickup | Pulses before the first complete cycle, when a piece opens on the gong. |

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
(group ...) ...                        ; how parts are grouped
```

Scales, stroke sets, instruments and colotomies usually come from a
template, so a piece often contains only `piece`, `use`, parts and
groups.

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

A degree or stroke may also have `:display STRING`, the short form
drawn in the grid, as in `01-notation.md`. Full and short forms are left
to the display issue.

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
`01-notation.md`, assumed yes). Note that `templates/gong-kebyar.nts`
has the reyong at e1 … u3, an octave below figure 2.7.

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

The Jaya Semara meter (activity 2.4, p. 43) **[Jaya Semara]**:

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
| `:steps-per-system N` | whole piece | Where the figure breaks into systems, as in `01-notation.md`. |

`(steps-per-pulse N)` is gone: the reader derives the step.

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
| `-`, `-:3` | Nothing is struck for one duration; the previous note is damped (proposed: see "Rests" below). |
| `(2 5)` | Chord: notes struck together. Takes the current duration. |
| `(rep N TOKEN ...)` | Repeat the tokens N times. Durations carry over between repetitions. |
| `\|` | Pulse check: must fall on a pulse boundary. Takes no time. |
| `\|\|` | Cycle check: must fall on a cycle boundary. Takes no time. |
| `@NAME` | Play the pattern NAME (see "Patterns"). |
| `(@ NAME :key value ...)` | Play the pattern NAME, changed by operators (see "Patterns"). |
| `(* M TOKEN ...)` **[later]** | Multiply the durations inside by M (like a tuplet). Gives a chord a duration: `(* 2 (2 5))`. |
| `(relative START TOKEN ...)` **[later]** | Bare degree names go to the octave nearest the previous note. |

Everything in the table is **[Jaya Semara]** except the two rows marked
**[later]**.

A part starts with a duration of 1 pulse, so its first note sets its
pace: `a1:2 o1 e1 i1` is four notes of two pulses.

### Rests (proposed)

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
- `·` (middle dot), now a synonym of `-`, would mislead anyone copying
  Gold's cipher. Either drop it or make it a synonym of `_`.

### Rules

- `_` at the start of a part or after `-` is an error.
- Every part, including the pickup, adds up to the same number of
  pulses. Generated parts (timekeeper, colotomy) fill that length.
- `|` and `||` report where a part drifted: "part `ugal`, cycle 2,
  pulse 4 1/2: `||` is not at the end of a cycle".

### The step

The reader finds the largest duration that divides every start, every
duration and the pulse. That is the step; the piece is stored as a grid
of steps (ADR 0002, narrowed). In the Jaya Semara example the kotekan
moves in quarter pulses, so the step is 1/4 pulse.

## Patterns

Gamelan melodies are often built from repeated figures. A pattern is a
named list of tokens that parts can play, join and repeat.

### Defining a pattern

```scheme
(pattern NAME :short STRING :long STRING  TOKEN ...)
```

```scheme
(pattern polos-1 :short "1" :long "Norot polos on pokok 1"
  o3:1/4 i3 i3 - | i3 - i3 -)
```

- NAME is the symbol that refers to the pattern. It must not start with
  `:` or `@`.
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
(@ pokok :octave -1)                ; an octave lower
(@ polos-1 :step 1)                 ; one scale degree higher
(@ pokok :drop-first 1)             ; without its first note
(@ pokok :drop-last 1)              ; without its last note
(@ pokok :octave -1 :drop-last 1)   ; both
```

| Operator | Meaning |
|---|---|
| `:step N` | Move every note N degrees along the scale (i o e u a, then i in the next octave); key numbers move N keys. Gamelan transposition: the figure keeps its shape on the keys. |
| `:octave N` | The same as `:step 5N` on a five-tone scale. |
| `:drop-first N` | Remove the first N notes. The pattern gets shorter by their time. |
| `:drop-last N` | Remove the last N notes. The pattern gets shorter by their time. |

- A note, for dropping, is a struck note or chord together with the `_`
  holds that follow it: dropping a note held for two pulses removes
  both pulses. Rests are not notes and are not counted.
- Transposing and dropping are independent, so their order does not
  matter.
- Operators apply only to patterns, not to `rep` blocks or parts.

In Jaya Semara, the polos figures on pokok tones 6 and 2 are the figure
on tone 1 moved one degree down and up, and the sangsih figure on 3 is
its figure on 1 moved two degrees up:

```scheme
(pattern polos   @polos-1  (@ polos-1 :step -1)  @polos-3  (@ polos-1 :step 1))
(pattern sangsih @sangsih-1  (@ sangsih-1 :step -1)
                 (@ sangsih-1 :step 2)  (@ sangsih-1 :step 1))
```

The whole example is built from patterns: see
`2026-11-21-jaya-semara-pangecet.nts`.

### Rules

- **A pattern means the same everywhere.** Its durations start at 1
  pulse unless its first token sets one, and after the pattern the
  part's duration is what it was before.
- **Notes are resolved where the pattern is used**, against that
  part's instrument. A pattern of key numbers can be shared between
  instruments; a pattern of note names works on instruments that have
  those keys.
- **`_` may start a pattern.** It holds the note before the pattern
  where it is used (Gold's pokok starts with a dot).
- **Patterns may contain patterns**, but not themselves, directly or
  through others.
- **Checks are optional.** Most patterns are just notes and need not
  start or end on a pulse or a cycle. A `|` or `||` inside a pattern is
  checked where the pattern is used, against the piece's time, so it
  says where the pattern has to fall.
- **The piece records each use**: pattern, part, start and end, so that
  a score can mark the span with the pattern's short or long name.

Errors, reported where the pattern is used:
- an unknown pattern; a pattern that contains itself
- a transposed note outside the instrument's range
- dropping more notes than the pattern has

## Groups

As in `01-notation.md`, with options in the new style:
`(group LABEL :subtitle STRING PART ...)`. One pitched instrument per
group (ADR 0011). Generated parts (timekeeper, colotomy) get default
groups.

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

### To decide for Jaya Semara

1. **Carry-over durations**: proposed yes.
2. **`·`**: drop it, or make it a synonym of `_` (Gold's dot). Today it
   is a synonym of `-`.
3. **The name of the meter**: Gold calls it bapang (p. 140), but its
   16-pulse layout is the one figure 5.11 gives for gegaboran. The
   example uses `pangecet-16` for now.
4. **Gong strokes**: Jaya Semara needs G (gong), P (kempur) and T
   (klentong). Are they strokes of one `gong` instrument (proposed), or
   separate instruments?
5. **Generated parts**: what are the generated colotomy and kempli
   parts called, and can a `group` name them (to place the gongs and
   the kempli in one group, for example)?
6. **Reserved list heads**: `rep` starts a repeat and `@` a pattern
   with operators, so no degree or stroke may be called `rep` or `@`, or
   a chord `(rep ...)` would be read as a repeat.
7. **Length**: proposed that a piece is its pickup plus whole cycles;
   an incomplete last cycle is an error for now.
8. **Error positions**: the format, e.g. "cycle 2, pulse 4 1/2".
9. **Dropping and rests**: when notes are dropped, what happens to the
   rests among and around them? Dropping the first 3 notes of
   `e3 o3 o3 - | o3 - o3 -` could keep the rest after them
   (`- o3 - o3 -`, 5/4 pulses) or cut up to the next note kept
   (`o3 - o3 -`, 1 pulse). Proposed: `:drop-first N` cuts everything
   before the next note kept, and `:drop-last N` cuts from the first
   dropped note to the end.

### Later

10. Rests in gong parts (`:damped no`): matters for playback only.
11. `relative` mode: syntax for octave jumps; key numbers inside it.
12. Chord durations: `(* M (chord))` or inside the chord; reserving
    `*` and `relative` as list heads.
13. Lines in long cycles (`:lines 8`): a third level of position, and
    a check for it.
14. Departing from the colotomy (an extra kempur stroke, a kempli that
    stops), changing colotomies, sections.
15. A pickup longer than a cycle.
16. Longgor forms; checking omang and gabor longgor against a source.
17. A timekeeper other than the kempli, or with its own pattern.
18. Patterns with parameters (a generic norot figure taking the pokok
    tones): left out; it would make patterns into functions.
19. Patterns written in degrees only and placed in an octave where they
    are used, like `relative`.
