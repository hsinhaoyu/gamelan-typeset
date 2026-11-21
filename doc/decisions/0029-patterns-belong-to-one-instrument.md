# 0029 Patterns belong to one instrument

Status: accepted (2026-11-21)

Context: Gamelan parts are built from repeated figures: Jaya Semara's kotekan is four 2-pulse figures, three of them the same figure moved along the scale. Key numbers and stroke names mean different things on different instruments, so a figure that isn't tied to an instrument could play the wrong music without an error.

Decision: `(pattern NAME :instrument I :short S :long L TOKEN ...)` defines a named figure for one instrument. It is checked against that instrument where it is defined, and used only on it: as `@NAME`, or `(@ NAME :step N :short S :long L)` to move it along the scale and name it for that use. A pattern's durations start at 1 pulse and don't leak into the part. Patterns may contain patterns, but not themselves. The piece records each use, with the names in force, so a score can print them. `rep` and `@` are reserved list heads.

Consequences: Figures are written once and named, and a score can print their names over the notes. Sharing a figure between instruments (`:scale`), and the operators `:octave`, `:drop-first` and `:drop-last`, are later.
