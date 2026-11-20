# 06 — Analysis

Status: planned, not implemented yet (draft v1). Module: `(notasi analysis)`

## Responsibility

Compute facts about a piece: intervals, distributions and
interlocking behaviour. Output is plain data, so it can be printed as a
text report, written as CSV/JSON, or later fed into Typst tables.

## Interval basis

Notes are symbolic, so intervals are measured in **scale steps**, not
cents:

```
pitch-index(note) = octave × scale-size + degree
interval(a, b)    = pitch-index(b) − pitch-index(a)
```

In a 5-tone scale, an interval of 5 is an octave. This works across
instruments that share a scale and octave numbering (see the open
question in 01-notation.md).

Intervals between strokes (unpitched instruments) are undefined and
skipped.

## v1 analyses

### Melodic intervals within a part

- Sequence of intervals between consecutive struck notes, ignoring rests.
- Histogram of interval sizes (signed and absolute).
- Contour: up / down / repeat counts.
- Range: lowest and highest note used.

### Note distribution

- How often each note is struck, and how many steps it sounds (weighted
  by duration), per part and per group.

### Vertical intervals

- At each step, the intervals between all notes sounding at once, e.g.
  between the ugal and calung, or within a reyong chord.
- Histogram per pair of parts.

### Interlocking (kotekan)

For a group of two parts (polos + sangsih):
- **Coverage**: the fraction of steps where at least one part strikes.
  A good kotekan approaches 100%.
- **Overlap**: steps where both strike.
- **Composite line**: the merged sequence of struck notes, which is the
  melody the listener hears; its intervals can then be analysed like any
  part.

## Output

```
(analyse-piece piece) → report        ; nested alist
(report->text report) → string
(report->csv report section) → string
```

Command line: `scripts/notasi-analyse piece.gml`.

## Later (v2+)

- **Tuning tables** per gamelan set, in cents per note, in a separate file:
  `(tuning "Gamelan X" (ding2 0) (dong2 120) ...)`. Interval analysis can
  then report cents as well as scale steps. Notes still never store
  tuning; the table is looked up by note name.
- **Paired tuning (ombak)**: Balinese instruments come in pairs tuned
  slightly apart (pengumbang/pengisep); tuning tables could hold both.
- Statistics across a corpus of pieces.
- Visualising analysis results in Typst (histograms, interval matrices).
