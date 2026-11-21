# 0035 Expansion is its own module

Status: accepted (2026-11-21)

Context: ADR 0008 says the reader and layout depend only on `(notasi piece)`. Turning tokens into timed events now involves durations that carry over, `rep`, patterns with operators, checks against the piece's time and generated parts: enough work for its own stage, testable without files or forms. The reader must also report an unknown palette in a score at its line, and the palette names are in `(notasi style)`.

Decision: Expansion is a module of its own, `(notasi expand)`, between the reader and the piece. It turns tokens into events and pattern spans, and depends only on `(notasi piece)`. Its errors carry a time and the chain of pattern uses; the reader adds the file and line and raises a `&notasi-syntax-error`. The reader depends on `(notasi expand)`, `(notasi piece)` and `(notasi style)`, which holds only data (palettes and schemes) and depends on neither. Layout still depends only on `(notasi piece)` and `(notasi style)`. Where ADR 0008 says the reader depends only on `(notasi piece)`, read this list.

Consequences: Expansion can be tested on tokens alone, and the reader keeps files, forms, templates and scores. Every mistake in a file, scores included, is reported with its file and line. `(notasi style)` must stay free of dependencies on the reader and layout.
