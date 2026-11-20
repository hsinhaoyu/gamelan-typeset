# 0007 Guile 3.0, standard library first

Status: accepted (2026-11-19)

Context: External Guile libraries are not always packaged, which makes installing and running CI harder.

Decision: Target Guile 3.0 and use its standard library: SRFI-9 records, SRFI-64 tests, `(ice-9 match)`. No external Guile dependencies in the first version; small needs such as JSON writing are implemented in the project.

Consequences: CI needs only Guile itself. Some small utilities (e.g. `(gamelan json)`) are written and tested here instead of imported.
