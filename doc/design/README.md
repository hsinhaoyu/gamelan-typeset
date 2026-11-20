# Design overview

This project notates Balinese (and other) gamelan music in a small text
language, reads it into an internal model with Guile, renders it as a
coloured, piano-roll-style grid via Typst, and analyses intervals and
interlocking patterns.

## Pipeline

```
piece.gml ──reader──▶ model ──layout──▶ figure.json ──Typst template──▶ PDF / PNG / SVG
                        │
                        └──analysis──▶ report (text / CSV / JSON)
```

| Stage | Module | Document |
|---|---|---|
| Notation language | — | [01-notation.md](01-notation.md) |
| Internal model | `(gamelan model)` | [02-model.md](02-model.md) |
| Reader + validation | `(gamelan reader)` | [03-reader.md](03-reader.md) |
| Layout | `(gamelan layout)` | [04-layout.md](04-layout.md) |
| Typst backend | `(gamelan typst)`, `typst/gamelan.typ` | [05-typst-backend.md](05-typst-backend.md) |
| Analysis | `(gamelan analysis)` | [06-analysis.md](06-analysis.md) |
| Testing and workflow | `tests/`, CI | [07-testing-and-workflow.md](07-testing-and-workflow.md) |

## Core decisions

Each decision's context and consequences are in its record in
[`../decisions/`](../decisions/README.md).

1. The notation is s-expressions: [0001](../decisions/0001-notation-is-s-expressions.md)
2. Time is a grid of equal steps: [0002](../decisions/0002-time-is-a-grid-of-equal-steps.md)
3. Notes are symbolic: [0003](../decisions/0003-notes-are-symbolic.md)
4. The model is the centre: [0004](../decisions/0004-the-model-is-the-centre.md)
5. Guile decides, Typst draws: [0005](../decisions/0005-guile-decides-typst-draws.md)
6. The JSON file is the contract with Typst: [0006](../decisions/0006-json-is-the-contract-with-typst.md)
7. Guile 3.0, standard library first: [0007](../decisions/0007-guile-3-standard-library-first.md)

## Maintaining these documents

- These documents always describe the current design. When it changes,
  edit the text in place; git history keeps the old versions.
- Each document has a `Status:` line under its title, and content is
  labelled **Implemented** (what the code does now), **Planned** (agreed,
  not built) or **Open questions** (undecided). Move items between these
  as they happen.
- Any change to behaviour, notation, the model or the JSON contract
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
| beat | A fixed number of steps (`steps-per-beat`) |
| system | One horizontal block of the figure, e.g. one gong cycle |
| scale | Ordered set of degree names, e.g. `ding dong deng dung dang` |
| instrument | Ordered list of the notes (keys/pots) an instrument has |
| part | A line of music played on one instrument |
| group | Parts drawn together in one block of rows, e.g. polos + sangsih |
| lane | One row inside a group, one per note (pitch) or stroke type |
| polos / sangsih | The two interlocking parts of a kotekan |
| colotomic | Gong, kempur, kempli etc., which mark the structure of the cycle |

## Prototype

`../prototypes/score.typ` and `../prototypes/piece.json` are a hand-made mockup of
the target output, transcribed from a textbook excerpt (reyong kotekan, ugal,
calung, kempli, gong, kendang). The Typst backend should produce visually
equivalent output for the same music.
