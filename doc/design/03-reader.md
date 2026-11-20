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

The number in brackets is the slice (below) that implements the case.

- [1] Missing or duplicate `piece` form
- [2] Undefined scale name
- [3] Undefined instrument or part name
- [2] Duplicate scale, stroke set or instrument definitions within one file
- [3] Duplicate part definitions within one file
- [4] The same name from two templates used by one file
- [4] Template not found; a cycle of `use`s; a `use` argument that is not a
  name or a string
- [4] A template containing a form other than `scale`, `strokes`,
  `instrument` or `use`
- [4] `use` after a definition, part or group
- [2] Instrument note not in its scale or stroke set, or pitched notes not
  ascending
- [2] Duplicate degree or stroke name or alias within a scale or stroke set
- [2] A scale and a stroke set with the same name
- [2] Degree name or alias ending in a digit (scales only)
- [2] Unknown degree option, or `display` that is not a string
- [3] Note index out of range; unknown note name
- [3] `_` at the start of a part or after a rest (`-` or `·`)
- [3] Unknown token (e.g. a string or `#t` inside a part)
- [1] A lone `.` in a part (an improper list); Guile read errors such as
  unbalanced parentheses, reported with file and line
- [3] Parts of unequal length
- [3] A part in more than one group
- [3] A group with parts on two different pitched instruments

## Slices

Planned. The reader is built in four slices, each its own branch and PR
into `dev`, started with `/start-milestone <branch>`. After each one,
`make check` passes and the reader handles a larger subset of the
notation. Each slice covers the steps below and the error cases tagged
with its number.

1. `feat/reader-forms`: the public interface; the condition type (decide
   its name, fields and accessors and record them under "Error
   reporting" before writing tests); step 1 (read forms, Guile read
   errors); step 2 (dispatch, improper lists); the `piece` form and its
   options. A file with only a `piece` form reads into a piece with no
   parts.
2. `feat/reader-scales`: step 4 and the scale and instrument parts of
   steps 5 and 6, for definitions in a single file.
3. `feat/reader-parts`: parts and groups in steps 5 and 6, steps 7 to 9.
   A piece with everything defined in one file reads correctly.
4. `feat/reader-templates`: step 3 and the template-finding rules under
   "Public interface". `examples/tenzer1.gml` reads end to end.

## Not the reader's job

- Deciding lanes, colours or systems (layout)
- Any interval computation (analysis)
