# 03 — Reader and validation

Status: planned, not implemented yet (draft v1). Module: `(notasi reader)`

## Responsibility

Turn a `.gml` file into a valid `piece` record, or fail with clear error
messages. Nothing else in the system validates input.

## Public interface

```
(read-piece-file path)   → piece       ; raises on error
(read-piece-port port #:key directory)   → piece
(read-piece-string str #:key directory)  → piece   ; convenient for tests
```

Finding templates:
- `(use "file.gml")` is relative to the folder of the file containing
  the `use`. For `read-piece-file` that is the piece file's folder; for
  a port or string there is no file, so `directory` is used instead
  (default: the current directory).
- `(use NAME)` searches Guile's `%load-path` for `templates/NAME.gml`.
  Running from the repo root with `-L .`, as the tests do, finds the
  repo's `templates/` folder; an installed package finds its own.

## Steps

1. **Read forms.** Call `read` repeatedly until EOF. Guile does the
   tokenising: numbers, symbols (`_`, `-`, `·`, `/`, `ding2`) and lists
   (chords, forms).
   Guile's own read errors (unbalanced parentheses, `. .`) are caught and
   re-raised as reader errors with the file and line.
2. **Dispatch** on the head symbol: `piece`, `use`, `scale`, `strokes`,
   `instrument`, `part`, `group`, `text`. Unknown heads are errors. A form
   that is an improper list (e.g. a part containing `1 . 2`) is an error
   that suggests `·` or `-` for a rest.
3. **Load templates.** For each `use`, read the template's forms
   (recursively for its own `use` forms, each file once) and merge its
   definitions:
   - Each definition remembers the file it came from.
   - A file's own definitions replace those from its templates.
   - Two templates of one file defining the same name is an error,
     unless both are the same definition from the same file, reached
     through two `use` paths.
   - A name defined twice in one file is an error.

   Errors in a template report the template's file and line.
4. **Build scales and stroke sets.** Each degree or stroke is a bare
   name or `(NAME OPTION ...)`. Fill in defaults (no aliases; `display`
   is the name as a string) and build a table from every name and alias
   to its degree.
5. **Resolve names** in order: scales and stroke sets → instruments →
   parts → groups. All files are merged by now, so a template's
   instrument uses the piece's scale if the piece replaced it.
6. **Resolve note names**, in instrument definitions and in part tokens:
   - Pitched scale: split the symbol into a degree and trailing octave
     digits (`i2` → `i`, `2`), look the degree up by name or alias, and
     check the instrument has that note.
   - Stroke set: match the whole symbol against stroke names and
     aliases, since stroke names may end in a digit.
   - Always store the canonical name (`ding2`, never `i2`).
7. **Convert part tokens to events** with a single left-to-right pass,
   keeping a "current event" and a step counter:
   - number / note name / chord → close the current event, open a new one
   - `_` → extend the current event (error if none)
   - `-` or `·` → close the current event, advance the step
   - `/` → skip, no step
8. **Create default groups** for parts not named in any `group`. They
   have no source location (`#f`).
9. **Check the piece invariants** (02-piece.md) and equal part lengths.

## Error reporting

Errors must say where and what, in musician terms:

```
example.gml:14: part `sangsih`, step 7: note 13 does not exist on
  instrument `reyong` (it has 12 notes)
```

- Guile can attach source line/column to list forms read from a port, so
  each top-level form has a line number, and so does each degree or
  stroke written as a list. A bare degree or stroke (`ding`) is a symbol
  with no position, so it uses its scale's location. Every location
  includes the file, since definitions can come from templates. Atoms such as numbers inside a
  part don't carry positions, so token errors are reported as part name
  plus step number (and pulse number), which is more meaningful to a
  musician anyway.
- Use a dedicated condition type, e.g. `&notasi-syntax-error`, with
  fields for file, line, part and step, so tests can check the error kind
  rather than string-matching messages.
- Report the first error and stop (v1). Collecting several errors is a
  possible later improvement.

## Error cases to cover (each needs a test)

- Missing or duplicate `piece` form
- Undefined scale / instrument / part name
- Duplicate definitions within one file, or the same name from two
  templates used by one file
- Template not found; a cycle of `use`s; a `use` argument that is not a
  name or a string
- A template containing a form other than `scale`, `strokes`,
  `instrument` or `use`
- `use` after a definition, part or group
- Instrument note not in its scale or stroke set, or pitched notes not
  ascending
- Duplicate degree or stroke name or alias within a scale or stroke set
- A scale and a stroke set with the same name
- Degree name or alias ending in a digit (scales only)
- Unknown degree option, or `display` that is not a string
- Note index out of range; unknown note name
- `_` at the start of a part or after a rest (`-` or `·`)
- Unknown token (e.g. a string or `#t` inside a part)
- A lone `.` in a part (an improper list); Guile read errors such as
  unbalanced parentheses, reported with file and line
- Parts of unequal length
- A part in more than one group
- A group with parts on two different pitched instruments

## Not the reader's job

- Deciding lanes, colours or systems (layout)
- Any interval computation (analysis)
