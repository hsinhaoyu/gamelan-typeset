---
name: doc-audit
description: Compare the design documents in doc/design/ and the decision log in doc/decisions/ with the code, and list every discrepancy. Use at milestones or when the user asks whether the docs are up to date.
disable-model-invocation: true
---

# Audit design docs against the code

Find drift between the design documents and the code. Report it; don't fix
anything until the user says so.

## Steps

1. Read `doc/design/README.md`, every `doc/design/0*.md`, and every ADR in
   `doc/decisions/` whose status is `accepted`.

2. Read the code and its executable spec: `gamelan/*.scm`, `tests/*.scm`,
   `examples/`, `tests/golden/` (if present), `typst/` (if present) and the
   Makefile.

3. For each design document, compare it with the code:
   - Interfaces: exported procedures, records and fields, CLI commands.
   - Behaviour: notation tokens and rules, reader error cases, layout
     decisions, the JSON contract and its `version`, analyses.
   - Structure: the repository layout and module dependencies (ADR 0004:
     reader, layout and analysis depend only on `(gamelan piece)`; see ADR 0008).
   - Status labels: the `Status:` line and any Implemented / Planned /
     Open questions sections. Something marked planned that now exists,
     or marked implemented that doesn't, is drift.

4. Check that the code doesn't contradict an accepted ADR. A contradiction
   means either the code is wrong or a superseding ADR is missing.

5. Report a table with one row per discrepancy:
   - where in the docs (`file:line`)
   - where in the code (`file:line`), or "missing"
   - what differs, in one sentence
   - which side looks out of date: **doc**, **code**, or **unclear**
     (needs a decision; say what the decision is)

   Then list any open questions in the docs that the code has already
   answered. If nothing differs, say so plainly.

6. Offer to fix the doc-side items on a `doc/sync` branch from `dev`. Code
   fixes and unclear items need the user's decision first. Any fix that
   reverses a documented decision needs a new ADR (see
   `doc/decisions/README.md`).
