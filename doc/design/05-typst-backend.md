# 05 — Typst backend and JSON contract

Status: planned, not implemented yet (draft v1). Modules: `(notasi typst)` (Guile), `typst/notasi.typ`
(Typst template)

## Responsibility

- Guile side: serialise the layout `figure` to JSON, write a small `.typ`
  entry file, and optionally run `typst compile`.
- Typst side: draw exactly what the JSON says. No musical logic.

The same template draws scores inside Typst documents, where the figure
JSON arrives inside a side file instead (06, ADR 0016). So the template
must work in both places; see "Typst template design", points 6 and 7.

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
              "events": [
                { "start": 0, "dur": 2, "lane": 3, "text": "a",
                  "fill": "#66a61e", "text_color": "#ffffff",
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
- `fill`, `text` and `text_color` come from layout's colour scheme
  (04, "Note style"). `fill` is `null` for a note drawn as text only,
  such as a stroke.
- All lengths are Typst length strings.
- Any change to this format increments `version` and updates the
  template and the golden tests in the same PR.

## JSON writing

Write a small JSON serialiser in `(notasi json)` (strings, numbers,
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
4. **Notes as rounded blocks** filled with the event's `fill`, with
   bold text in its `text_color`; an event whose `fill` is `null` is
   just its text, centred in the cell.
5. **Header row** with bold pulse numbers and `·` for other steps, numbered
   from `system.start`.
6. **`score` returns plain content**, systems stacked. It does not make
   a `figure`: in a document, the caption, numbering and label are the
   author's (06). For a standalone figure, the entry file wraps the
   score in a `figure` with the JSON `caption`; a document ignores
   `title` and `caption`.
7. **No page or font settings in the template.** In a document the
   score uses the document's font and text size. Only the standalone
   entry file sets the page (`width: auto, height: auto`) and font.

Entry point produced by Guile for a standalone figure:

```typst
#import "notasi.typ": score
#set page(width: auto, height: auto, margin: 14pt)
#let data = json("piece.json")
#figure(score(data), caption: data.caption)
```

## Running Typst

- `(compile-typst typ-path #:format 'pdf)` calls `typst compile` with
  `system*` and raises a clear error if `typst` is not installed or fails.
- The command-line script `scripts/notasi`, as `notasi render`, does:
  read → layout → write JSON + .typ → compile. Its other subcommands
  (`typst`, `update`, `watch`) are for documents (06).

## Version pinning

Typst is pre-1.0. Record the tested version in CLAUDE.md and the README;
the template needs positioned grid cells (Typst ≥ 0.11).
