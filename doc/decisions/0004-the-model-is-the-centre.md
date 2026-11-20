# 0004 The model is the centre

Status: accepted (2026-11-19)

Context: Reader, layout and analysis could easily grow dependencies on each other (e.g. layout peeking at source text), which makes each harder to change and test.

Decision: The reader, layout and analysis depend only on `(gamelan model)`, never on each other. After reading, the model is the single source of truth.

Consequences: Each stage can be tested on hand-built model values. A second front end or output format only needs to talk to the model. All validation happens in the reader, so downstream stages can assume a valid model.
