# Instruments

An instrument lists the notes it can play: the keys of a gangsa, the
pots of a reyong, or the strokes of a drum.

```scheme
{{#include examples/instruments.gml}}
```

Each `instrument` line gives:

1. the instrument's name: `ugal`
2. the scale or stroke set its notes come from: `selisir`
3. its notes

## Notes on a pitched instrument

Each note is a degree followed by its octave: `ding2` is ding in octave
2. You can use an alias instead, so `i2` is also ding2. Octave numbers
are your own choice and only need to be consistent within the piece:
start at 1 (or 0) for the lowest octave you need.

List the notes **from lowest to highest**. The ugal above has ten keys,
from dong1 up to ding3.

## Notes on a gong or drum

Each note is one stroke from the stroke set, in the order you want its
rows to appear in the score. The gong above plays `G` (gong) and `P`
(kempur).

## Showing note names

In the score, each note is a coloured block in its lane. By default the
block is empty: its lane and colour already say which note it is. To
write each note's name inside its block, add `(show-names yes)` after
the instrument's notes:

```scheme
{{#include examples/show-names.gml}}
```

This is most useful for gongs and drums, whose strokes are all drawn in
the same grey: with names shown, the gong's notes read `G` and `P`. The
`gong-kebyar` template does this for its kempli, gong and kendang (see
[Templates](templates.md)). Leave it out, or write `(show-names no)`,
to keep the blocks empty.

## Order in the file

Scales, stroke sets and instruments can come in any order after the
`piece` line: an instrument may come before its scale.

## What you get

notasi reads this file as a piece with a scale, a stroke set and two
instruments, ready for parts. Next, set the
[steps and pulses](steps-and-pulses.md) and write the
[notes](notes-rests-and-holds.md) each instrument plays.

Most pieces for one gamelan share the same scale and instruments. Put
them in a [template](templates.md) once instead of at the top of every
piece.

If something is wrong, see
[Error messages](errors.md#mistakes-in-scales-and-instruments).
