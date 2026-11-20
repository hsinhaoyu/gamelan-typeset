# 05 — Typst backend and JSON contract

Status: partly implemented (draft v1): the JSON writer `(notasi json)`
and `write-figure` in `(notasi typst)` are implemented, and the
template `typst/notasi.typ` (slice 1 of 3); the entry file and running
Typst are planned (see "Slices"). Modules: `(notasi json)`,
`(notasi typst)` (Guile), `typst/notasi.typ` (Typst template)

## Responsibility

- Guile side: serialise the layout `figure` to JSON, write a small `.typ`
  entry file, and optionally run `typst compile`.
- Typst side: draw exactly what the JSON says. No musical logic.

The same template draws scores inside Typst documents, where the figure
JSON arrives inside a side file instead (06, ADR 0016, proposed). So the template
must work in both places; see "Typst template design", points 6 and 7.

## JSON contract (version 1)

An excerpt of `tests/golden/kotekan.json`, the figure for
`examples/kotekan.gml` (one event of the first system shown):

```json
{
  "version": 1,
  "title": "Reyong kotekan",
  "steps_per_pulse": 4,
  "sizes": { "label_width": "10.5em", "lane_width": "3.6em",
             "step_width": "2.0em", "row_height": "2.0em" },
  "systems": [
    {
      "start": 0,
      "steps": 8,
      "groups": [
        {
          "label": "Reyong",
          "subtitle": "polos + sangsih",
          "lanes": ["neng1", "nong1", "ning1", "nang1"],
          "voices": [
            {
              "name": "polos",
              "events": [
                { "start": 0, "dur": 2, "lane": 3, "text": "nang",
                  "fill": "#1b9e77", "text_color": "#ffffff",
                  "continued": false }
              ]
            }
          ]
        }
      ]
    }
  ],
  "caption": null
}
```

Rules:
- `start` in events is relative to the system; `system.start` is absolute.
- `lane` is a 0-based index into `lanes` (top row = 0).
- A chord produces one event per note, same start and duration.
- `fill`, `text` and `text_color` come from layout's colour scheme
  (04, "Note style"). `text` is `null` when the note's instrument
  doesn't show names (ADR 0019); `fill` is `null` only from a custom
  scheme, for a note drawn as text alone.
- All lengths are Typst length strings.
- Any change to this format increments `version` and updates the
  template and the golden tests in the same PR.

## Writing the figure file

**Implemented** (layout slice 4, `feat/layout-golden`), in `(notasi typst)`,
tests in `tests/typst.scm`:

```
(write-figure figure path)
```

writes FIGURE (from `layout-piece`) to the file PATH as pretty JSON
(`write-json`), in UTF-8, ending with a newline, replacing any file
already there. The JSON is built before the file is opened, so a figure
that can't be written raises the writer's `&error` and leaves no file
behind (an existing file at PATH is left as it was). The rest of
`(notasi typst)` (the entry file, running Typst) is milestone 4.

## JSON writing

**Implemented** (layout slice 1, `feat/json`). A small JSON writer in
`(notasi json)` instead of depending on guile-json. It keeps CI to a
plain `apt install guile-3.0`, and its output order is deterministic,
which golden tests need. Its tests are in `tests/json.scm`.

```
(write-json value #:optional port #:key (pretty? #t))  ; port defaults to (current-output-port)
(json-string value #:key (pretty? #t)) → string
```

Scheme values map to JSON as guile-json does, so there is no
ambiguity between objects and arrays:

| Scheme | JSON |
|---|---|
| an alist, `((key . value) ...)`; `'()` | an object, keys in the given order; `{}` |
| a vector | an array |
| a string | a string |
| an exact integer, or a finite inexact real | a number (`number->string`) |
| `#t`, `#f` | `true`, `false` |
| the symbol `null` | `null` |

- Keys are symbols or strings, written as strings. A key given twice
  in one alist is an error; the symbol `a` and the string `"a"` are
  the same key.
- Strings are written as UTF-8. Only `"`, `\` and control characters
  (below U+0020) are escaped: `\n`, `\r`, `\t`, `\b`, `\f` by their
  short forms, others as `\u00XX` with lowercase hex.
- Anything else (another symbol, a rational such as `1/2`, an infinity
  or NaN, a pair that is not part of an alist, a procedure, a bad key)
  raises an `&error` whose irritants include the offending value.

Pretty output (the default, used for figure files and golden files):

- 2-space indent; each object member on its own line as `"key": value`.
- An array whose elements are all strings, numbers, booleans or `null`
  goes on one line, elements separated by `", "`: `["neng1", "nong1"]`.
  Any other array, including one that holds `{}` or `[]`, has one
  element per line.
- `{}` and `[]` for an empty object or array.
- `write-json` ends pretty output with a newline; `json-string` does
  not, and compact output never does.
- The caller chooses the port's encoding; `write-json` writes
  characters, not bytes.

Compact output (`#:pretty? #f`) has no spaces or newlines at all:
`{"a":1,"b":[1,2]}`.

## Typst template design

Lessons from the prototype (`doc/prototypes/score.typ`):

1. **Two layers.** A background grid draws the pulse lines; a
   transparent foreground grid draws labels, header and notes, placed on
   top with `place`. A single grid does not work: a note spanning
   several columns (`colspan`) would hide the lines it crosses even
   where it doesn't sound.
2. **Fixed column widths.** Both layers must align exactly, so the label
   column cannot be `auto`. Its width comes from the JSON `sizes`.
3. **Positioned cells.** Notes use `grid.cell(x:, y:, colspan:)`; empty
   cells are filled automatically, so rests need no handling.
4. **Notes as square blocks** filled with the event's `fill`, with
   bold text in its `text_color` when `text` isn't `null` (ADR 0019);
   an event whose `fill` is `null` is just its text, centred in the
   cell.
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

**Implemented** (slice 1, `feat/typst-template`): the template
`typst/notasi.typ` exports `score(data)`, where DATA is the figure
(05's contract, e.g. from `json("piece.json")`). It returns content:

- **Systems** are drawn in order, each as its own two-layer grid with
  its own header row and group labels, so each can be read alone,
  separated by a 1em gap. No systems: empty content.
- **Columns:** `label_width` (group label and subtitle), `lane_width`
  (lane labels), then `steps` columns of `step_width`. **Rows:** a
  header row, then one row per lane of each group, all `row_height`.
- **Header:** at each step whose absolute number (`system.start` + i)
  is a multiple of `steps_per_pulse`, the pulse number
  ((`start` + i) / `steps_per_pulse` + 1) in bold; at other steps a
  grey `·`. A system that doesn't start on a pulse starts with `·`.
- **Background:** always white, with no shading (ADR 0020). Pulse
  lines (background layer) follow the same absolute steps: a thin
  vertical line (`0.5pt`, `luma(170)`) runs down the left of every step
  that starts a pulse.
- **Groups:** a horizontal rule (`0.8pt`, `luma(120)`) above each group
  and below the last. The group label in bold, slightly larger
  (`1.1em`), with its subtitle under it in grey italics when not
  `null`, spanning the group's rows. Lane labels right-aligned, small
  (`0.85em`) and grey (`luma(140)`).
- **Notes** (ADRs 0019, 0020): a block filling its cells exactly, with
  no margin, in `fill`, with a thin white border (`0.5pt`) so that
  neighbouring notes stay apart (repeated strokes don't merge into what
  looks like one held note). The `text`, when not `null`, is centred in
  bold in `text_color`. When `continued` is true the block has no text:
  it is the same note carrying on from the previous system. When `fill`
  is `null`, no block: just the text, centred and bold, in
  `text_color`.
- Sizes relative to the text (`em`, `luma` greys), never absolute font
  sizes or fonts: the surrounding document or entry file sets those.

Tests (slice 1): `tests/template.scm` compiles every
`tests/golden/*.json` with `score` (from an entry file made in a
temporary folder) and fails if `typst compile` fails or prints a
warning. If `typst` isn't installed it says so and fails, since CI
always installs it. `make preview` renders each golden figure to
`build/preview/NAME.png` (not committed) for a person to compare with
the prototype; every PR touching the template is checked that way.

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
- The command-line script `scripts/notasi` (ADR 0018), as
  `notasi render`, does:
  read → layout → write JSON + .typ → compile. Its other subcommands
  (`typst`, `update`, `watch`) are for documents (06).

## Version pinning

Typst is pre-1.0. Record the tested version in CLAUDE.md and the README;
the template needs positioned grid cells (Typst ≥ 0.11). The tested
version is **0.15.1**. CI installs exactly that version, so every PR
compiles the examples with it; upgrading Typst is a deliberate change
to the pin, with the golden figures and template checked again.

## Slices

Milestone 4 (`feat/typst-backend` in the build order) is built in three
slices, each its own branch and PR into `dev`, started with
`/start-milestone <branch>`:

1. **Implemented.** `feat/typst-template`: `typst/notasi.typ` and its `score`, following
   "Typst template design"; CI installs Typst 0.15.1; tests compile the
   golden figures.
2. `feat/typst-render`: the rest of "Running Typst" on the Guile side:
   writing the entry file, `compile-typst`, and one procedure from a
   `.gml` file to a PDF.
3. `feat/notasi-command`: `scripts/notasi render PIECE.gml` (ADR 0018)
   and the manual page "Drawing a score".
