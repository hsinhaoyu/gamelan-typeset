# 05 — Typst backend and JSON contract

Status: partly implemented (draft v1): the JSON writer `(notasi json)`
and `write-figure` in `(notasi typst)` are implemented; the template,
the entry file and running Typst are planned (milestone 4). Modules: `(notasi json)`,
`(notasi typst)` (Guile), `typst/notasi.typ` (Typst template)

## Responsibility

- Guile side: serialise the layout `figure` to JSON, write a small `.typ`
  entry file, and optionally run `typst compile`.
- Typst side: draw exactly what the JSON says. No musical logic.

The same template draws scores inside Typst documents, where the figure
JSON arrives inside a side file instead (06, ADR 0016, proposed). So the template
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
- The command-line script `scripts/notasi` (ADR 0018), as
  `notasi render`, does:
  read → layout → write JSON + .typ → compile. Its other subcommands
  (`typst`, `update`, `watch`) are for documents (06).

## Version pinning

Typst is pre-1.0. Record the tested version in CLAUDE.md and the README;
the template needs positioned grid cells (Typst ≥ 0.11).
