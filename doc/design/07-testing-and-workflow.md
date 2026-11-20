# 07 — Testing and workflow

Status: planned, not implemented yet (draft v1)

## Repository layout

```
gamelan/            Guile modules: piece, reader, layout, json, typst, analysis
typst/gamelan.typ   Typst template
scripts/            command-line entry points (gamelan-render, gamelan-analyse)
examples/           real pieces (.gml), used as test fixtures
tests/              SRFI-64 test files, one per module
tests/golden/       expected outputs (JSON, analysis reports)
doc/prototypes/     hand-made mockup (score.typ, piece.json)
doc/design/         these documents (current design)
doc/decisions/      decision log (ADRs)
CLAUDE.md
Makefile
```

## Tests

- **Framework**: SRFI-64, one file per module (`tests/reader.scm` …).
- **Runner**: `make check` runs every test file and exits non-zero if any
  test fails. CI and local runs use the same command.
- **Unit tests**: reader token handling, every error case listed in
  03-reader.md, piece derived functions, layout decisions (lanes, system
  splitting, colours), JSON serialiser escaping.
- **Golden tests**: for each file in `examples/`, the generated JSON and
  analysis report are compared with `tests/golden/`. When an output change
  is intended, regenerate with `make golden` and review the diff in the PR.
- **Typst smoke test** (optional in CI): compile one example with Typst
  and check that it succeeds.

## Git workflow

- `main`: stable; only receives merge-commit PRs from `dev` at milestones.
- `dev`: integration; receives squash-merged PRs from feature branches.
- Branches: `feat/…`, `fix/…`, `chore/…`, `doc/…`.
- Every PR: CI green, Claude review comments resolved.
- A design change goes into `doc/design/` in the same PR as the code
  change. Reversing a documented decision also adds an ADR in
  `doc/decisions/`.
- The PR template has a checkbox for this.

## Milestones

1. `feat/piece` — records and derived functions, with tests
2. `feat/reader` — notation → piece, all error cases
3. `feat/json` + `feat/layout` — piece → figure JSON, golden tests
4. `feat/typst-backend` — template matching the prototype
5. `feat/analysis` — v1 analyses
6. v2 features: repeats, looping parts, sections, syllables

## Working with Claude Code

- CLAUDE.md points to `doc/design/README.md` and states: Guile 3.0, run
  `make check`, never commit to `main`/`dev`, update design docs with
  design changes.
- Use plan mode for each milestone; the relevant design doc is the spec.
- Hook: after edits to `.scm` files, run `guild compile -L . FILE` to
  catch unbalanced parentheses and unbound variables immediately.
- `/doc-audit` compares the design documents with the code and lists
  drift; run it at each milestone.
- `/cleanup-branches` deletes branches whose PRs have been merged.
- Ask a subagent to write tests from the design doc before the
  implementation exists, so tests are not shaped by the code.
