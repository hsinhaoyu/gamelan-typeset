# 03 — Reader and validation

Status: draft v1. Module: `(gamelan reader)`

## Responsibility

Turn a `.gml` file into a valid `piece` record, or fail with clear error
messages. Nothing else in the system validates input.

## Public interface

```
(read-piece-file path)   → piece       ; raises on error
(read-piece-port port)   → piece
(read-piece-string str)  → piece       ; convenient for tests
```

## Steps

1. **Read forms.** Call `read` repeatedly until EOF. Guile does the
   tokenising: numbers, symbols (`_`, `-`, `/`, `ding2`) and lists
   (chords, forms).
2. **Dispatch** on the head symbol: `piece`, `scale`, `instrument`,
   `part`, `group`, `text`. Unknown heads are errors.
3. **Resolve names** in order: scales → instruments → parts → groups.
   Undefined or duplicate names are errors.
4. **Convert part tokens to events** with a single left-to-right pass,
   keeping a "current event" and a step counter:
   - number / note name / chord → close the current event, open a new one
   - `_` → extend the current event (error if none)
   - `-` → close the current event, advance the step
   - `/` → skip, no step
5. **Create default groups** for parts not named in any `group`.
6. **Check the model invariants** (02-model.md) and equal part lengths.

## Error reporting

Errors must say where and what, in musician terms:

```
example.gml:14: part `sangsih`, step 7: note 13 does not exist on
  instrument `reyong` (it has 12 notes)
```

- Guile can attach source line/column to list forms read from a port, so
  each top-level form has a line number. Atoms such as numbers inside a
  part don't carry positions, so token errors are reported as part name
  plus step number (and beat number), which is more meaningful to a
  musician anyway.
- Use a dedicated condition type, e.g. `&gamelan-syntax-error`, with
  fields for file, line, part and step, so tests can check the error kind
  rather than string-matching messages.
- Report the first error and stop (v1). Collecting several errors is a
  possible later improvement.

## Error cases to cover (each needs a test)

- Missing or duplicate `piece` form
- Undefined scale / instrument / part name
- Duplicate definitions
- Instrument note not in its scale, or notes not ascending
- Note index out of range; unknown note name
- `_` at the start of a part or after `-`
- Unknown token (e.g. a string or `#t` inside a part)
- Parts of unequal length
- A part in more than one group

## Not the reader's job

- Deciding lanes, colours or systems (layout)
- Any interval computation (analysis)
