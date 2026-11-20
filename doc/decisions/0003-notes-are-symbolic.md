# 0003 Notes are symbolic

Status: accepted (2026-11-19)

Context: Gamelan tunings differ between ensembles, and the notation and analysis are about scale degrees, not frequencies.

Decision: A note is a name (e.g. `ding2`), not a frequency. Tuning, if ever needed, lives in separate tuning tables and is never stored on notes.

Consequences: The same piece can be read for any ensemble. Analysis measures intervals in scale steps, not cents. Pitch-based features need a tuning table first.
