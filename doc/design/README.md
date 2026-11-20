# Design overview

This project notates Balinese (and other) gamelan music in a small text
language, reads it into a `piece` record with Guile, renders it as a
coloured, piano-roll-style grid via Typst. It does not analyse pieces
(ADR 0015).

## Pipeline

```
piece.gml ──reader──▶ piece ──layout──▶ figure.json ──Typst template──▶ PDF / PNG / SVG
```

Scores can also live inside a Typst document (06). `notasi` finds them
with a Typst query (`typst eval --in`), runs the same pipeline on each, and writes the
figures to a side file that the document loads:

```
book.typ ──typst eval──▶ snippets ──reader, layout──▶ book.notasi.json
book.typ + book.notasi.json ──typst compile──▶ PDF
```

| Stage | Module | Document |
|---|---|---|
| Notation language | — | [01-notation.md](01-notation.md) |
| Piece (internal data) | `(notasi piece)` | [02-piece.md](02-piece.md) |
| Reader + validation | `(notasi reader)` | [03-reader.md](03-reader.md) |
| Layout, note style | `(notasi layout)`, `(notasi style)` | [04-layout.md](04-layout.md) |
| Typst backend | `(notasi typst)`, `typst/notasi.typ` | [05-typst-backend.md](05-typst-backend.md) |
| Scores in Typst documents | `scripts/notasi`, `typst/` package | [06-documents.md](06-documents.md) |
| Environment, installation, testing (open questions) | — | [07-environment.md](07-environment.md) |

## Build order

Each milestone is one feature branch with tests, or, when its design
doc has a "Slices" section, one branch per slice (see CLAUDE.md for the
workflow).

1. `feat/piece`: records and derived functions
2. `feat/reader`: notation → piece, all error cases; built in four
   slices (`feat/reader-forms` … `feat/reader-templates`), see
   [03-reader.md](03-reader.md#slices)
3. `feat/json` + `feat/layout`: piece → figure JSON, golden tests;
   built in four slices, see [04-layout.md](04-layout.md#slices)
4. `feat/typst-backend`: the Typst template, entry file and `notasi
   render`; built in
   three slices, see [05-typst-backend.md](05-typst-backend.md#slices)
5. `feat/documents`: scores in Typst documents; built in three slices,
   see [06-documents.md](06-documents.md#slices)
6. v2 features: repeats, looping parts, sections, syllables

## Core decisions

Each decision's context and consequences are in its record in
[`../decisions/`](../decisions/README.md).

1. The notation is s-expressions: [0001](../decisions/0001-notation-is-s-expressions.md)
2. Time is a grid of equal steps: [0002](../decisions/0002-time-is-a-grid-of-equal-steps.md)
3. Notes are symbolic: [0003](../decisions/0003-notes-are-symbolic.md)
4. The piece is the centre: [0008](../decisions/0008-the-piece-is-the-centre.md)
5. Guile decides, Typst draws: [0005](../decisions/0005-guile-decides-typst-draws.md)
6. The JSON file is the contract with Typst: [0006](../decisions/0006-json-is-the-contract-with-typst.md)
7. Guile 3.0, standard library first: [0007](../decisions/0007-guile-3-standard-library-first.md)
8. One pitched instrument per group: [0011](../decisions/0011-one-pitched-instrument-per-group.md)
9. No analysis: [0015](../decisions/0015-no-analysis.md)
10. Notes are coloured by pitch: [0017](../decisions/0017-notes-are-coloured-by-pitch.md)
11. One `notasi` command with subcommands: [0018](../decisions/0018-one-notasi-command.md)
12. Notes are square blocks; note names are optional: [0019](../decisions/0019-square-notes-optional-names.md)
13. A plain white grid; notes fill their cells: [0020](../decisions/0020-plain-grid-notes-fill-cells.md)

Proposed, not yet agreed:

- Typst documents load scores from a side file: [0016](../decisions/0016-documents-load-scores-from-a-side-file.md)
  (06 and the "Scores in Typst documents" milestone depend on it)

## Maintaining these documents

- These documents always describe the current design. When it changes,
  edit the text in place; git history keeps the old versions.
- Each document has a `Status:` line under its title, and content is
  labelled **Implemented** (what the code does now), **Planned** (agreed,
  not built) or **Open questions** (undecided). Move items between these
  as they happen.
- Any change to behaviour, notation, the piece records or the JSON contract
  updates these documents in the same PR.
- Reversing or narrowing a core decision, or anything else documented
  here, needs a new record in `../decisions/` (see its README).
- Exact behaviour (e.g. every reader error case) belongs in tests and
  examples; documents can point to them instead of repeating them.
- Run `/doc-audit` in Claude Code at each milestone to find drift
  between these documents and the code.

## Glossary

| Term | Meaning |
|---|---|
| step | The smallest time unit; one token in a part |
| pulse | The steady stroke of the kempli/kajar; a fixed number of steps (`steps-per-pulse`) |
| system | One horizontal block of the figure, e.g. one gong cycle |
| scale | Ordered set of degree names, e.g. `ding dong deng dung dang` |
| stroke set | Named set of unpitched strokes, e.g. kendang `dag dug du` |
| instrument | Ordered list of the notes (keys/pots) an instrument has |
| part | A line of music played on one instrument |
| group | Parts drawn together in one block of rows, e.g. polos + sangsih |
| lane | One row inside a group, one per note (pitch) or stroke type |
| polos / sangsih | The two interlocking parts of a kotekan |
| colotomic | Gong, kempur, kempli etc., which mark the structure of the cycle |

## Prototype

`../prototypes/score.typ` and `../prototypes/piece.json` are a hand-made mockup,
transcribed from a textbook excerpt (reyong kotekan, ugal, calung,
kempli, gong, kendang), from before the template existed. The template
keeps its structure (groups of lanes, a step grid, pulse numbers and
lines) but no longer its look. notasi colours each pitch rather than
each part (ADR 0017); draws square notes that fill their cells, with
names only where an instrument asks for them, and strokes as grey boxes
(ADRs 0019, 0020); and leaves the background white. The two examples'
drawings (`make preview`) are the reference now.
