# 0025 Time is measured in pulses, with durations

Status: accepted (2026-11-21)

Context: In v1 every token is one step, and a piece sets `(steps-per-pulse N)` (ADRs 0002, 0009). Gold's and Tenzer's music mixes densities: the jegogan plays every four pulses while the kotekan plays four notes a pulse. Writing every part on the finest grid means long runs of `_`, and the grid has to be chosen before the music is written.

Decision: Time is counted in pulses. A note's duration is written as a suffix in pulses, a whole number or a fraction (`e2:2`, `o3:1/4`), and stays in force until another is written; a part starts at 1 pulse. The piece stores times as exact rationals in pulses. There is no `steps-per-pulse`: layout derives the step for each score, the largest duration that divides every time it prints. A step is now a column of a printed grid, not a unit of the music.

Consequences: Parts are much shorter to write, and each part is written at its own density. Layout must convert rational times to integer columns; the JSON writer refuses rationals, so a time left unconverted fails loudly. Every v1 piece, example and manual page is rewritten when this is built. Supersedes 0002. Where ADR 0009 names the `(steps-per-pulse N)` option and record field, read them as removed; its name "pulse" stands.

Supersedes: 0002
