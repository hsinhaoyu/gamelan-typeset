# 0009 Count in pulses, not beats

Status: accepted (2026-11-20)

Context: The figure groups step columns into blocks of N steps for header numbers, shading and lines, and the reader uses the same grouping in error messages. The draft called this a "beat" (`steps-per-beat`), a Western term that means little in gamelan.

Decision: Call the grouping a pulse, after the steady stroke of the kempli or kajar. The `piece` option is `(steps-per-pulse N)`, the record field is `steps-per-pulse` and the JSON key is `steps_per_pulse`.

Consequences: Header numbers and error messages count pulses. Don't reintroduce "beat" in code or docs. The JSON contract stays at version 1, because no code had used the old key.
