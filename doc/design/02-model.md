# 02 — Internal model

Status: planned, not implemented yet (draft v1). Module: `(gamelan model)`

The model is the single source of truth after reading. Layout and
analysis consume it; nothing downstream looks at the source text.

## Principles

- Plain immutable SRFI-9 records. No mutation after construction.
- Time is in integer steps, starting at 0.
- Notes are referred to by their index within their instrument (0-based
  internally; the notation is 1-based, and the reader converts).
- No pitch or tuning data on notes.
- Every record that came from the source keeps a source location, for
  error messages.

## Records

```
piece
  title            : string
  steps-per-beat   : integer
  steps-per-system : integer | #f      (#f = whole piece in one system)
  length           : integer           total steps
  scales           : list of scale
  instruments      : list of instrument
  parts            : list of part
  groups           : list of group     (every part is in exactly one group)

scale
  name     : symbol
  degrees  : list of symbol            ascending, one octave
  pitched? : boolean                   #f for the built-in `strokes`

instrument
  name   : symbol
  scale  : scale
  notes  : vector of note              ascending pitch order

note
  name   : symbol                      e.g. ding2, dag
  degree : integer | #f                index into scale degrees; #f for strokes
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
```

Rests are not stored. They are the gaps between events. This keeps
layout and analysis simple: they only ever iterate over sounding events.

## Derived values (functions, not stored)

- `(note-pitch-index note)`: `octave × scale-size + degree`, a total order
  across all pitched instruments sharing a scale. Basis for intervals.
- `(group-lanes group)`: the sorted set of notes actually used by the
  parts in a group, highest first. Determines the rows drawn.
- `(part-steps part)`: the end of the last event, used for validation.
- `(events-at piece step)`: everything sounding at a step, for analysis.

## Invariants (checked by the reader, assumed by everyone else)

1. Every event lies within `[0, piece-length)`.
2. Events in one part do not overlap.
3. Every note index is valid for the part's instrument.
4. Every part belongs to exactly one group.
5. Instrument notes are in ascending pitch order.

## Open questions

- Is a chord one event with several notes (current choice) or several
  simultaneous events? One event is simpler for layout; analysis may want
  to split it.
- Sections (v2) would add a level between piece and part. Keep `piece`
  fields minimal so this is easy to insert later.
