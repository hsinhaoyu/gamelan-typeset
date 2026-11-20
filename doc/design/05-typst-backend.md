# 05 — Typst backend and JSON contract

Status: planned, not implemented yet (draft v1). Modules: `(gamelan typst)` (Guile), `typst/gamelan.typ`
(Typst template)

## Responsibility

- Guile side: serialise the layout `figure` to JSON, write a small `.typ`
  entry file, and optionally run `typst compile`.
- Typst side: draw exactly what the JSON says. No musical logic.

## JSON contract (version 1)

```json
{
  "version": 1,
  "title": "Reyong kotekan",
  "steps_per_pulse": 4,
  "sizes": { "label_width": "10.5em", "lane_width": "3.6em",
             "step_width": "2.6em", "row_height": "1.5em" },
  "systems": [
    {
      "start": 0,
      "steps": 12,
      "groups": [
        {
          "label": "Reyong",
          "subtitle": "polos + sangsih",
          "lanes": ["neng1", "nong1", "ning1", "nang1"],
          "voices": [
            {
              "name": "polos",
              "color": "#2a9d8f",
              "events": [
                { "start": 0, "dur": 2, "lane": 3, "text": "nang",
                  "continued": false }
              ]
            }
          ]
        }
      ]
    }
  ],
  "caption": "Reyong kotekan with gong."
}
```

Rules:
- `start` in events is relative to the system; `system.start` is absolute.
- `lane` is a 0-based index into `lanes` (top row = 0).
- A chord produces one event per note, same start and duration.
- All lengths are Typst length strings.
- Any change to this format increments `version` and updates the
  template and the golden tests in the same PR.

## JSON writing

Write a small JSON serialiser in `(gamelan json)` (strings, numbers,
booleans, lists → arrays, alists → objects) instead of depending on
guile-json. It is ~40 lines, keeps CI to a plain `apt install guile-3.0`,
and output order is deterministic, which golden tests need.

## Typst template design

Lessons from the prototype (`doc/prototypes/score.typ`):

1. **Two layers.** A background grid draws pulse shading and pulse lines;
   a transparent foreground grid draws labels, header and notes, placed on
   top with `place`. A single grid does not work: a note spanning several
   columns (`colspan`) covers the pulse lines and shading underneath it.
2. **Fixed column widths.** Both layers must align exactly, so the label
   column cannot be `auto`. Its width comes from the JSON `sizes`.
3. **Positioned cells.** Notes use `grid.cell(x:, y:, colspan:)`; empty
   cells are filled automatically, so rests need no handling.
4. **Notes as rounded blocks** with white bold text, filled with the voice
   colour.
5. **Header row** with bold pulse numbers and `·` for other steps, numbered
   from `system.start`.
6. **One `figure` per piece** with the caption; systems stacked inside it
   (or one figure per system — template option).

Entry point produced by Guile:

```typst
#import "gamelan.typ": score
#score(json("piece.json"))
```

## Running Typst

- `(compile-typst typ-path #:format 'pdf)` calls `typst compile` with
  `system*` and raises a clear error if `typst` is not installed or fails.
- The command-line script `scripts/gamelan-render` does:
  read → layout → write JSON + .typ → compile.

## Version pinning

Typst is pre-1.0. Record the tested version in CLAUDE.md and the README;
the template needs positioned grid cells (Typst ≥ 0.11).
