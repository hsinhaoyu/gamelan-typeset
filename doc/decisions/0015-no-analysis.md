# 0015 notasi does not analyse pieces

Status: accepted (2026-11-20)

Context: The design planned a `(notasi analysis)` module (draft in `doc/design/06-analysis.md`, milestone 5 of the build order). It would report melodic and vertical intervals, note distributions and kotekan coverage, with a `scripts/notasi-analyse` command. Nothing had been built beyond an empty stub module. Notating and drawing pieces is the purpose of the package, and analysis would widen its scope, its interface and its maintenance.

Decision: notasi has no analysis feature. The `(notasi analysis)` stub, `06-analysis.md`, the `feat/analysis` milestone and the planned `scripts/notasi-analyse` command are removed. The package reads pieces and draws them. Where earlier ADRs (0002, 0003, 0004, 0008, 0010) mention analysis or `notasi-analyse`, read them without it: the reader and layout depend only on `(notasi piece)`, and the piece is still the single source of truth.

Consequences: The pipeline is reader → piece → layout → Typst. The piece keeps derived values that layout or users need, such as `note-pitch-index` and `events-at`, but none are added only for analysis. Golden tests compare JSON only. Tuning tables, previously planned under analysis, are not planned anywhere; they would come back with playback, if ever. Someone who wants analysis can build it outside the package on `(notasi piece)`, since the piece records are public.
