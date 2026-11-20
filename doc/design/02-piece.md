# 02 — Piece

Status: v1 implemented (records and derived values). Module: `(notasi piece)`,
tests in `tests/piece.scm`.

A `piece` record is the single source of truth after reading. Layout and
analysis consume it; nothing downstream looks at the source text.

## Principles

- Plain immutable SRFI-9 records. No mutation after construction.
- Time is in integer steps, starting at 0.
- Notes are referred to by their index within their instrument (0-based
  internally; the notation is 1-based, and the reader converts).
- No pitch or tuning data on notes.
- Every definition keeps a source location (file and line), for error
  messages: scales, degrees, instruments, parts and groups. The file
  matters because definitions can come from templates. `note` and
  `event` have none: they come from atoms, which carry no position (see
  03-reader.md), so token errors are reported by part and step instead.
  `piece` has none either: errors about the piece form are found while
  reading, before the record exists.
- The piece holds the definitions after templates are merged: a
  definition the piece replaced is gone, and template definitions the
  piece never uses (e.g. an instrument no part plays) are kept. They are
  harmless, because layout only draws parts.

## Records

**Implemented.** Each record has the usual SRFI-9 interface: a constructor
`make-<record>` that takes the fields positionally in the order listed
below, a predicate `<record>?`, and an accessor `<record>-<field>` for
each field (e.g. `make-event`, `event?`, `event-start`).

```
source-location
  file     : string | #f               #f when read from a string or port
  line     : integer                   1-based

piece
  title            : string
  steps-per-pulse  : integer
  steps-per-system : integer | #f      (#f = whole piece in one system)
  length           : integer           total steps
  scales           : list of scale     includes stroke sets
  instruments      : list of instrument
  parts            : list of part
  groups           : list of group     (every part is in exactly one group)

scale                                  also used for stroke sets
  name     : symbol
  degrees  : list of degree            scale: ascending, one octave;
                                       stroke set: the strokes, unordered
  pitched? : boolean                   #f for a stroke set (`strokes` form)
  location : source location

degree
  name     : symbol                    e.g. ding
  aliases  : list of symbol            e.g. (i); may be empty
  display  : string                    short form for the grid, e.g. "i"
  location : source location

instrument
  name     : symbol
  scale    : scale                     a scale or a stroke set
  notes    : vector of note            pitched: ascending pitch order;
                                       strokes: the order the instrument lists
  location : source location

note
  name   : symbol                      e.g. ding2, dag (never an alias)
  degree : integer                     index into the scale's degrees (or strokes)
  octave : integer | #f                #f for strokes

part
  name       : symbol
  instrument : instrument
  events     : list of event           sorted by start
  location   : source location

event
  start    : integer                   step, 0-based
  duration : integer                   >= 1
  notes    : list of integer           note indices; length > 1 means chord

group
  label    : string
  subtitle : string | #f
  parts    : list of part
  location : source location | #f      #f for a default group (no `group` form)
```

Rests are not stored. They are the gaps between events. This keeps
layout and analysis simple: they only ever iterate over sounding events.

## Derived values (functions, not stored)

**Implemented.**

- `(note-pitch-index instrument note)`: `octave × scale-size + degree`,
  a total order across all pitched instruments sharing a scale. Basis for
  intervals. It takes the instrument because a note does not know its
  scale. For a stroke, which has no pitch, raises an `&error` whose
  irritants are the note name and instrument name.
- `(note-display instrument note)`: the degree's display form, e.g. `"i"`
  for `ding2`. Used for the text in note cells.
- `(note-label instrument note)`: the display form plus the octave, e.g.
  `"i2"`; for a stroke, just its display form. Used for lane labels.
- `(group-lanes group)`: the notes actually used by the parts in a
  group, as a list of note records, each once. Determines the rows
  drawn. Pitched notes all come from one instrument (invariant 6) and are
  sorted highest first. Strokes follow the instrument's order. With
  several instruments, each instrument's lanes come as a block, in the
  order its first part appears in the group.
- `(part-steps part)`: the end of the last event (`start + duration`),
  or 0 for a part with no events. The reader uses it to check invariant 1
  (`part-steps` ≤ `piece-length`). It is not a part's written length:
  trailing rests are not events, so the reader checks that parts have
  equal length from their token counts instead.
- `(events-at piece step)`: everything sounding at a step, for analysis:
  a list of `(part . event)` pairs, one for each event with
  `start ≤ step < start + duration`, in the piece's part order. An event
  sounds for its whole duration, including the `_` holds after its start.

## Invariants (checked by the reader, assumed by everyone else)

**Planned:** the reader checks these. The records do not.

1. Every event lies within `[0, piece-length)`.
2. Events in one part do not overlap.
3. Every note index is valid for the part's instrument.
4. Every part belongs to exactly one group.
5. Notes of a pitched instrument are in ascending pitch order.
6. All pitched parts in a group play the same instrument. Different
   pitched instruments are never grouped together; parts on different
   stroke instruments may be (ADR 0011).

## Open questions

- Can a group mix a pitched instrument with stroke instruments (e.g. ugal
  with kempli)? Invariant 6 does not forbid it, but `group-lanes` does
  not yet say where stroke lanes go relative to pitched lanes. The code
  currently treats it like several stroke instruments: one block per
  instrument, in part order.
- Two stroke instruments in one group may have strokes with the same
  name (e.g. two kendang both playing `dag`). Do they share a lane or
  get one each? The prototype's kendang group draws one lane per drum,
  and the code currently gives each instrument its own lanes.
- Is a chord one event with several notes (current choice) or several
  simultaneous events? One event is simpler for layout; analysis may want
  to split it.
- How a note ends: rests are not stored, so the piece cannot tell a note
  damped at a rest from one left to ring. That is fine while `-` and `·`
  mean the same thing, but if they get different meanings (open question
  2 in 01-notation.md), or for playback, `event` will need a field saying
  how the note ends.
- Sections (v2) would add a level between piece and part. Keep `piece`
  fields minimal so this is easy to insert later.
