# 03 — Reader and validation

Status: partly implemented: slices 1–3 of 4 (see "Slices"). Module:
`(notasi reader)`, tests in `tests/reader.scm`.

## Responsibility

Turn a `.gml` file into a valid `piece` record, or fail with clear error
messages. Nothing else in the system validates input.

## Public interface

**Implemented**, except finding templates (**Planned**, slice 4). The
`directory` keyword is accepted but not used yet.

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

Every step except 3 is **Implemented**, for definitions in a single
file. Step 3 (templates) is **Planned** (slice 4).

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

**Implemented** for the error cases of slices 1 to 3.

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
- Every reader error is a `&notasi-syntax-error`, a subtype of `&error`,
  exported from `(notasi reader)`:

  | Field | Accessor | Value |
  |---|---|---|
  | kind | `notasi-syntax-error-kind` | a symbol naming the error case (below) |
  | file | `notasi-syntax-error-file` | string, or `#f` when read from a string or port |
  | line | `notasi-syntax-error-line` | 1-based, or `#f` when no form is to blame (e.g. `missing-piece`) |
  | part | `notasi-syntax-error-part` | part name (symbol), or `#f` |
  | step | `notasi-syntax-error-step` | 0-based step, or `#f` |

  The predicate is `notasi-syntax-error?`. The condition also carries a
  `&message` with the readable text (`song.gml:3: duplicate piece
  form`). Tests check `kind` and the location fields, never the message.
- Checks run in this order, so a file with several problems always
  reports the same one:
  1. Read all forms (`read-error`).
  2. Each form, in file order, must be a proper list with a known head
     symbol (`improper-form`, `unknown-form`).
  3. The `piece` form: present, first and only once (`missing-piece`,
     `piece-not-first`, `duplicate-piece`).
  4. The `piece` form's title and options (`bad-title`, `bad-option`,
     `unknown-option`, `duplicate-option`).
  5. A `use` form (until slice 4): `not-implemented`. It comes before
     the definitions, so a file that uses a template isn't reported as
     having undefined scales.
  6. The shape of each `scale`, `strokes`, `instrument`, `part` and
     `group` form, in file order (`bad-form`).
  7. Duplicate definitions, in file order: the second definition of a
     name is the error (`duplicate-definition`). Scales and stroke sets
     share one set of names; instruments and parts each have their own.
  8. Each scale and stroke set, in file order, and within it each degree
     or stroke in order: its shape and options (`bad-degree`), then a
     name or alias ending in a digit (`degree-ends-in-digit`, scales
     only), then a name or alias already used in this set
     (`duplicate-degree`).
  9. Each instrument, in file order: its scale or stroke set
     (`undefined-scale`), then each note in order: whether it exists
     (`unknown-note`), then against the notes before it
     (`notes-not-ascending`, `duplicate-note`).
  10. Each part, in file order: its instrument (`undefined-instrument`),
     then its tokens left to right, each with its own error
     (`unknown-token`, `hold-without-note`, `note-out-of-range`,
     `unknown-note`, `bad-chord`).
  11. Equal length: the first part, in file order, whose step count
     differs from the first part's (`unequal-length`).
  12. Each group, in file order: its options (`bad-option`,
     `unknown-option`, `duplicate-option`), then each part name in order
     (`undefined-part`, `part-in-two-groups`), then its instruments
     (`mixed-pitched-group`).
  13. The other forms (`text`, v2), in later steps. Until a slice
     implements a form, it raises `not-implemented` at that form's line.
- Which line an error reports:
  - The line of the list to blame: the form, or for an option error the
    option itself, since an option is a list with its own line.
  - `piece-not-first`: the first form in the file.
  - An atom on its own at the top level (e.g. `foo`), which has no
    position: the line where reading it stopped, i.e. where it ends.
  - `read-error`: the line where Guile stopped reading.
- Report the first error and stop (v1). Collecting several errors is a
  possible later improvement.

## Error cases to cover (each needs a test)

The number in brackets is the slice (below) that implements the case.

Each case is followed by its `kind` symbol. Kinds for slice 4 are
chosen when that slice starts.

- [1] Missing or duplicate `piece` form: `missing-piece` (line `#f`),
  `duplicate-piece` (line of the second `piece` form)
- [1] `piece` not the first form: `piece-not-first` (line of the first
  form in the file)
- [1] `piece` title not a string: `bad-title`
- [1] An option that is not a proper `(SYMBOL VALUE)` list (e.g.
  `(steps-per-pulse . 4)`, `("steps-per-pulse" 4)`, `(tempo)`), or a
  `steps-per-pulse` or `steps-per-system` value that is not an exact
  positive integer (so `4.0` is rejected): `bad-option`. The shape is
  checked before the name.
- [1] A well-formed option with an unknown name, or an option given
  twice: `unknown-option`, `duplicate-option`
- [1] A form that is not a list, or whose head is not a known symbol:
  `unknown-form`
- [1] A known form that the reader does not handle yet (e.g. `text`,
  which is v2): `not-implemented`
- [2] An instrument naming a scale or stroke set that isn't defined:
  `undefined-scale` (instrument's line)
- [2] A `scale`, `strokes` or `instrument` form of the wrong shape: no
  name, a name that is not a symbol, no degrees or strokes, or an
  instrument with no notes, or an instrument whose scale or notes are
  not names (a string, a number): `bad-form` (the form's line). Later slices
  use the same kind for malformed `part` and `group` forms.
- [3] A part naming an instrument that isn't defined:
  `undefined-instrument` (part's line, part field set). A group naming a
  part that isn't defined: `undefined-part` (group's line, part field is
  the undefined name).
- [3] A `part` form with no name, a name or instrument that is not a
  symbol, or no tokens; a `group` form whose label is not a string, with
  no part names, a part name that is not a symbol, or a part name after
  an option: `bad-form` (the form's line)
- [2] Duplicate scale, stroke set or instrument definitions within one
  file: `duplicate-definition` (line of the second). Scales and stroke
  sets share one set of names; instruments have their own, so an
  instrument may share a name with a scale or stroke set.
- [3] Duplicate part definitions within one file: `duplicate-definition`
  (line of the second). Parts have their own names, so
  `(part ugal ugal ...)` is fine.
- [4] The same name from two templates used by one file
- [4] Template not found; a cycle of `use`s; a `use` argument that is not a
  name or a string
- [4] A template containing a form other than `scale`, `strokes`,
  `instrument` or `use`
- [4] `use` after a definition, part or group
- [2] Instrument note not in its scale or stroke set, or a pitched note
  without an octave number (`ding`): `unknown-note`; pitched notes not
  in strictly ascending order (so a repeated note too):
  `notes-not-ascending`; a stroke listed twice: `duplicate-note`. All at
  the instrument's line. Octave numbers are whole numbers of 0 or more,
  so `ding0` is a note below `ding1`. An octave number may not start
  with 0 unless it is 0 itself, so `ding02` is `unknown-note`.
- [2] Duplicate degree or stroke name or alias within a scale or stroke
  set, including an alias equal to its own degree's name:
  `duplicate-degree`
- [2] A scale and a stroke set with the same name: `duplicate-definition`
  (see above)
- [2] Degree name or alias ending in a digit (scales only):
  `degree-ends-in-digit`
- [2] A degree or stroke that is not `NAME` or `(NAME OPTION ...)`, an
  unknown degree option, `display` that is not a string, `(alias)` with
  no names or with a name that is not a symbol (`(alias "i")`), or an
  option given twice: `bad-degree`

For a degree error, the line is the degree's own line when it is written
as a list (even if the option at fault is on a later line), otherwise
the line of its scale or stroke set.

- [3] Token errors. All are at the part's line, with the part field set
  to the part's name and the step field to the token's 0-based step (`/`
  takes no step):
  - an exact integer outside 1 to the number of notes on the
    instrument: `note-out-of-range`
  - a note name that isn't on the instrument (resolved as in step 6):
    `unknown-note`
  - `_` at the start of a part or after a rest (`-` or `·`):
    `hold-without-note`
  - a chord with fewer than two notes, the same note twice, or a member
    that is not a number or note name (`_`, `-`, `·`, `/`, a list, a
    string, `#t`, `1.5`): `bad-chord`. The chord's shape is checked
    before its members, so `(9)` is `bad-chord`. A member out of range or not on the
    instrument gives `note-out-of-range` or `unknown-note`, as above.
  - anything else, e.g. a string, `#t` or `1.5`: `unknown-token`. (A
    list inside a chord is a bad chord member, above.)
- [1] A lone `.` in a part (an improper list): `improper-form`; Guile
  read errors such as unbalanced parentheses or `. .`: `read-error`,
  with file and the line where Guile stopped
- [3] Parts of unequal length: `unequal-length`, on the first part
  whose step count differs from the first part's (its line, part field
  set, step `#f`)
- [3] A part in more than one group, or listed twice in one group:
  `part-in-two-groups` (line of the group that names it again, part
  field set)
- [3] A group with parts on two different pitched instruments:
  `mixed-pitched-group` (group's line, part field set to the first part
  on a second pitched instrument). A group may mix stroke instruments,
  and a pitched instrument with stroke instruments (open question in
  02-piece.md).
- [3] Group options: only `(subtitle STRING)`, after the part names.
  The same kinds as piece options: `bad-option` (wrong shape, or a
  subtitle that is not a string), `unknown-option`, `duplicate-option`,
  at the option's line.

## Slices

The reader is built in four slices, each its own branch and PR
into `dev`, started with `/start-milestone <branch>`. After each one,
`make check` passes and the reader handles a larger subset of the
notation. Each slice covers the steps below and the error cases tagged
with its number.
Slices 1 to 3 are implemented; slice 4 is **Planned**.

1. **Implemented.** `feat/reader-forms`: the public interface; the condition type (decide
   its name, fields and accessors and record them under "Error
   reporting" before writing tests); step 1 (read forms, Guile read
   errors); step 2 (dispatch, improper lists); the `piece` form and its
   options. A file with only a `piece` form reads into a piece with no
   parts: length 0, empty scales, instruments, parts and groups, and the
   default options (`steps-per-pulse` 4, `steps-per-system` `#f`). Every
   other known form raises `not-implemented`. The `directory` keyword is
   accepted but unused until slice 4.
2. **Implemented.** `feat/reader-scales`: step 4 and the scale and instrument parts of
   steps 5 and 6, for definitions in a single file. A file with only
   `piece`, `scale`, `strokes` and `instrument` forms reads into a piece
   whose scales (scales and stroke sets together) and instruments are in
   file order, with length 0 and no parts or groups. `use`, `part`,
   `group` and `text` still raise `not-implemented`.
3. **Implemented.** `feat/reader-parts`: parts and groups in steps 5 and 6, steps 7 to 9.
   A piece with everything defined in one file reads correctly. What
   the piece holds:
   - `length`: the parts' step count (all equal), or 0 with no parts.
     A part of only `/` tokens is allowed and has 0 steps.
   - parts in file order. An event's notes are 0-based indices; a
     chord's are sorted ascending.
   - groups in the order of their first part in the file, whether
     written or default. With parts `ugal`, `polos`, `sangsih`, `gong`
     and `(group "Reyong" polos sangsih)`, the order is ugal, Reyong,
     gong. A group's parts are in the order the `group` form lists them.
   - a default group per part in no `group`: label the part's name as a
     string, subtitle `#f`, location `#f`.
   - invariants 1 to 3 hold by construction (events come from the
     tokens); 4 and 6 are checked as above.
   Only `text` still raises `not-implemented` (besides `use`, slice 4).
4. `feat/reader-templates`: step 3 and the template-finding rules under
   "Public interface". `examples/tenzer1.gml` reads end to end.

## Not the reader's job

- Deciding lanes, colours or systems (layout)
