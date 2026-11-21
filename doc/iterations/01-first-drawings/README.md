# Iteration 1: first drawings

Status: done

**Goal** (in hindsight): draw `examples/tenzer1.nts` as a coloured grid.

**Acceptance test.** `scripts/notasi render examples/tenzer1.nts` draws
it; the golden and template tests check it from then on.

Released as v0.1.x: v0.1.0 is the first end-to-end pipeline (notation
to PDF), v0.1.1 renames notation files to `.nts` (ADR 0022).

This iteration came before iterations were defined (ADR 0023), so it has
no notes: the design went straight into `doc/design/`.

## Milestones

All done.

1. `feat/piece`: records and derived functions (02)
2. `feat/reader`: notation → piece, all error cases; four slices, see
   [03-reader.md](../../design/03-reader.md#slices)
3. `feat/json` + `feat/layout`: piece → figure JSON, golden tests; four
   slices, see [04-layout.md](../../design/04-layout.md#slices)
4. `feat/typst-backend`: the Typst template, entry file and
   `notasi render`; three slices, see
   [05-typst-backend.md](../../design/05-typst-backend.md#slices)

Milestone 5 of the old build order, scores in Typst documents (06), is
deferred: see the [backlog](../backlog.md).
