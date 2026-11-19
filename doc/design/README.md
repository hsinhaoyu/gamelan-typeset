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

1. **The notation is s-expressions.** Guile's `read` does the tokenising. A
   friendlier surface syntax can be added later as a second front end that
   produces the same model.
2. **Time is a grid of equal steps**, like a step sequencer. Every token in a
   part is exactly one step.
3. **Notes are symbolic.** A note is a name (`ding2`), not a frequency.
   Tuning, if ever needed, lives in separate tuning tables and is never
   stored on notes.
4. **The model is the centre.** The reader, layout and analysis depend only
   on the model, never on each other.
5. **Guile decides, Typst draws.** All musical decisions (system breaks,
   lanes, colours, grouping) are made in Guile. The Typst template only
   draws what the JSON says.
6. **The JSON file is a contract** between Guile and Typst, documented in
   05-typst-backend.md and covered by tests.
7. **Guile 3.0, standard library first.** SRFI-9 records, SRFI-64 tests,
   no external Guile dependencies in the first version.

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
