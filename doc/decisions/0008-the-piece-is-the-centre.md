# 0008 The piece is the centre

Status: accepted (2026-11-20)

Context: ADR 0004 put a central "model" module at the centre of the pipeline. "Model" is a vague, technical word; the module's main record is already called `piece`, and the notation's top-level form is `(piece ...)`.

Decision: Rename the module `(gamelan model)` to `(gamelan piece)` (`gamelan/piece.scm`, design doc `02-piece.md`). The decision in 0004 is otherwise unchanged: the reader, layout and analysis depend only on `(gamelan piece)`, never on each other, and after reading a `piece` record is the single source of truth. Where ADRs 0001 and 0002 say "the model", read `(gamelan piece)`.

Consequences: The pipeline reads as notation → piece → figure. Code and docs say "piece" instead of "the model".

Supersedes: 0004
