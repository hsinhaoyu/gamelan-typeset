# Design note: the internal representation

Status: agreed for iteration 2 (2026-11-21). Nothing here is
implemented. The goal of the iteration and every decision are in
`2026-11-21-iteration-2.md`, which wins where the two disagree.

What the reader should turn the notation into, now that the notation
has durations, colotomies, patterns and scores. The current design is
`doc/design/02-piece.md` and `notasi/piece.scm`; the notation is
`2026-11-21-notation-language.md` and `2026-11-21-score.md`.

## Considerations

### How LilyPond does it

LilyPond processes a file in clear stages:

1. **Parsing** turns the input into **music expressions**: a tree of
   sequential and simultaneous music, notes, repeats and the results of
   music functions. Every expression keeps its input location, for
   error messages.
2. **Music functions** (`\transpose`, `\relative`, `\unfoldRepeats`)
   transform the tree before anything is timed.
3. **Iteration** walks the tree and produces timed events. Time is a
   `Moment`: an exact rational, not a grid.
4. **Translation**: contexts (Score > StaffGroup > Staff > Voice)
   receive the events. Context properties are looked up through the
   parent contexts; that is how settings are inherited.
5. **Layout and spacing** produce the graphics. The spacing grid is
   decided here, not in the music.

Positions in the bar (`measurePosition`, `currentBarNumber`, and
`\partial` for pickups) are computed from time by the `Timing` context;
they are not stored in the music.

LilyPond fills in missing durations from the text that precedes them,
when it parses. So the body of `\repeat unfold` is parsed once, and
every repetition is identical.

### What has changed since 02

- Durations are fractions of a pulse, and the step is derived.
- Parts are built from patterns, repeats and operators, not written
  token by token.
- Some parts are generated (the timekeeper, the colotomy parts).
- Positions are cycles and pulses, with a pickup.
- Groups and printing options belong to scores, and a file may have
  several.
- `show-names` and `steps-per-system` have left the music.

## Proposal

### 1. Stages

```
read forms ─▶ resolve definitions ─▶ expand parts ─▶ piece (music)
                                                        │
                                       layout(piece, score) ─▶ JSON ─▶ Typst
```

- **Read forms**: Guile's `read`, with `r7rs-symbols` and `keywords`
  off; forms keep their source locations. As now.
- **Resolve definitions**: templates merged; scales, stroke sets,
  instruments, colotomies, patterns and scores indexed by name.
- **Expand parts**: everything between tokens and timed events. This
  is LilyPond's music functions and iteration together: durations,
  `rep`, patterns and their operators, `_` and `-`, the `|` and `||`
  checks, and the generated timekeeper and colotomy parts.
- **Piece**: the music only. No groups, no printing options.
- **Layout** takes a piece and a score, as LilyPond's contexts take the
  music.

Expansion is enough work to be its own stage, and it is its own
module: `(notasi expand)`.

### 2. Time: exact rationals in pulses

The duration note had the reader convert time to integer steps, so that
nothing downstream would change. But the step is a layout decision, as
spacing is in LilyPond:

- it can differ between scores: an excerpt without quarter-pulse notes
  could use a coarser grid than the whole piece;
- storing it puts display into the music.

So the piece stores `start` and `duration` as exact rationals in pulses
(Guile's rationals are exact and cheap). The step becomes a derived
function used by layout: the largest time dividing every start, every
duration and the pulse, over the parts and range a score prints.

This changes more than the duration note proposed: `02-piece.md`'s
principle "time is in integer steps" goes, ADR 0002 is narrowed further
(time is not a grid inside the piece; layout draws it on one), and
layout converts pulses to columns.

### 3. Expansion works on fragments

A pattern used with operators has to be built on its own, changed, and
then placed. So expansion produces **fragments**:

```
fragment
  items  : list of item, timed from 0
  length : rational (pulses)

item
  event       start, duration, notes
  check       time, kind (pulse | cycle)
  lead-hold   duration       a leading `_`: extend the event before
                             the fragment when it is placed
```

- **Tokens to a fragment**: one pass over the tokens, keeping the
  current duration and time. `_` extends the last event, or becomes a
  `lead-hold` if there is none yet; `-` advances time.
- **Patterns**: a pattern's notes are resolved against its own
  instrument where it is defined, so every pattern is checked even if
  it is never used. Its body is expanded into a fragment where it is
  used, starting at 1 pulse; a use in a part on another instrument is
  an error.
- **`:step N`** moves each event's notes N degrees (or N keys).
  LilyPond's `\transpose`, acting on pitches.
- **`:drop-first N`** removes the first N events, then everything
  before the next event kept, and shifts the rest back to 0. On an event
  list this "cut" rule, the one decided for dropping, is what happens
  naturally. Checks in the cut part go with it; a `lead-hold` goes too.
  (Dropping is designed but built later: neither target uses it.)
- **`:drop-last N`** removes from the N-th last event to the end.
- **`rep`**: see section 4.
- **Placing** a fragment in a part shifts its items by the current
  time, applies its `lead-hold` to the part's last event (an error if
  there is none), and checks each `check` against the piece's time:
  `|` on a whole pulse, `||` on a cycle boundary.

### 4. Repeats: every repetition identical

An earlier version of the language note had durations carry over
between repetitions, so `(rep 2 a1 o1:2)` would give `a1` its incoming
duration the first time and 2 pulses the second time. LilyPond does the
opposite: the body is read once, so every repetition is the same.

Decided: follow LilyPond. The body of `rep` is expanded once into a
fragment, with the duration in force before the `rep`, and copied N
times; after the `rep` the current duration is the body's last.
Every repetition is then identical, `rep` is simple to implement, and
it matches the rule that a pattern means the same everywhere. The Jaya
Semara example is the same under both rules.

### 5. Keeping some structure: spans and provenance

Flattening parts into events loses two things we need.

**Where patterns were used.** A score can mark pattern uses with their
names, so each part keeps a list of spans:

```
pattern-span   pattern, short, long, start, end, depth
                 (short and long: the names in force at the use, the
                 pattern's own unless the use gives others; depth: 0
                 for a pattern used in the part, 1 inside it, ...)
```

`rep` blocks could be kept as spans too, so that a score could later
print repeat signs instead of writing repetitions out (LilyPond's
`\repeat volta` against `unfold`). Not needed for Jaya Semara.

**Where an error came from.** Atoms carry no source position, so an
error inside a pattern is reported by its use chain, with the line of
each form:

```
jaya.nts:72: part `polos`, cycle 1, pulse 3 1/2, in pattern `polos-1`
  (line 74), used in pattern `polos` (line 82): note `u4` is not on
  instrument `pemade`
```

### 6. Positions are derived

As LilyPond's Timing context, positions are computed from time, not
stored:

- `(time->position piece t)` gives `(CYCLE PULSE)`, with PULSE a
  rational from 1; without a colotomy, a pulse number.
- `(position->time piece cycle pulse)` goes back.

They are used by error messages, by `:from` and `:to`, and by cycle and
pulse numbers in layout. With a pickup P and a cycle of N pulses, time
`t` is cycle `floor((t - P) / N) + 1`, pulse `(t - P) mod N + 1`;
the pickup is cycle 0.

### 7. Generated parts

The timekeeper and the colotomy parts are ordinary `part` records,
generated after the written parts are expanded (when the piece's length
is known). A part records its origin, so that errors and layout can
tell them apart: a generated part has no source line of its own, only
its colotomy's.

### 8. Scores

The reader checks scores (unknown parts, a part twice in a score,
mixed pitched instruments in a group, unknown or misplaced options) and
fills every group in completely: each group record carries its
effective settings (its own, else the score's, else the default). Layout
then reads plain values, which keeps layout tests simple.

The alternative, LilyPond's, is to keep options as written and look
them up through group, score and default when needed. It keeps the
records faithful to the source, at the cost of a lookup in layout.

### 9. Records

Changes to `02-piece.md`:

```
piece
  title       : string
  length      : rational            pulses, including the pickup
  pickup      : rational            0 without a colotomy
  colotomies  : list of (start . colotomy)   one segment, or '()
  scales      : list of scale
  instruments : list of instrument  show-names? removed
  patterns    : list of pattern
  parts       : list of part
  scores      : list of score       at least one (the default score)
  (steps-per-pulse, steps-per-system and groups removed)

part
  name, instrument, events, location   as now
  origin   : written | timekeeper | colotomy
  spans    : list of pattern-span

event
  start    : rational               pulses from the start of the piece
  duration : rational               > 0
  notes    : list of integer        as now

degree
  name, aliases, display, location   as now
  damped   : string | #f            the damped form (`:damped`), e.g.
                                    "na'"; #f: the display form is used

pattern
  name, short, long, location        the body is used up by expansion
  instrument : instrument            the instrument it is written for

pattern-span
  pattern, short, long, start, end, depth

colotomy
  name, length, timekeeper, parts, location

score
  name, title, subtitle, caption, from, to, system-length, breaks,
  cycle-numbers?, pulse-numbers?, numbering, pulse-label,
  font-size, cell-width, cell-height, groups, location

group                                effective settings, filled in
  label, short, subtitle, labels,
  rows        : notes | parts | single
  members     : list of (part . row-label)   row-label: string; the
                                             part's name when not given
  note-names?, fill, holds, pattern-names, pattern-level,
  scheme, palette, colors, lanes, location
```

Invariants change accordingly: event bounds are in pulses; every part
has the piece's length; the group invariants (a part in at most one
group, one pitched instrument per group, note names on for `:rows
parts`, `single` and `:fill none`) hold per score.

Both targets fit these records: Jaya Semara uses patterns with names
at their uses, a colotomy and pickup, rationals down to quarter pulses
and two scores; Baris adds damped forms on degrees and strokes, groups
with `parts` and `single` rows and row labels, `gong-first` numbering,
breaks, captions and four scores.

### 10. Further down

- **Layout** takes `(piece, score)`. It chooses the step, cuts the
  excerpt (`:from`, `:to`), splits systems by `:system-length`, and
  places labels, cycle and pulse numbers and pattern spans.
- **The JSON contract** gains short labels, cycle numbers, pattern spans
  and columns per pulse: probably a new version.
- **How a note ends**: 02's open question becomes real. `_` keeps a note
  sounding and `-` damps it, so an event may need a field saying how it
  ends. Not needed to draw Jaya Semara, but the records should be able
  to say it later without a redesign.

## Decisions

Settled for this iteration (`2026-11-21-iteration-2.md`):

1. Rationals in the piece; the step chosen by layout for each score.
2. Expansion is its own module, `(notasi expand)`.
3. Repeats: every repetition identical (LilyPond's way).
4. Pattern spans kept in the piece, with the names in force at each
   use; `rep` spans later.
5. Score settings filled in by the reader.
6. The default score is a stored `score` record, built by the reader.
7. Errors inside patterns name the whole chain of uses.

## Later

- An `ending` field on events (damped, ringing), for playback or
  `:damped no`. The open and damped name forms come from the grid
  meanwhile.
