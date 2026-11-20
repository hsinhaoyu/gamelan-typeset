---
name: start-milestone
description: Start a milestone from the build order in doc/design/README.md - create the feature branch, write tests from the design doc before any code, and plan the implementation. Use when the user wants to start or work on a milestone such as feat/piece or feat/reader.
argument-hint: "[milestone, e.g. feat/piece]"
---

# Start a milestone

Argument: the milestone's branch name (e.g. `feat/piece`). If none is
given, take the first milestone in "Build order" in `doc/design/README.md`
whose design doc's `Status:` line doesn't say it's implemented, and confirm
it with the user.

## Steps

1. **Branch.** The working tree must be clean; if not, stop and ask. Then:

   ```
   git fetch --prune origin
   git switch dev && git pull --ff-only
   git switch -c <milestone>
   ```

2. **Read the spec.** Read the design doc(s) for the milestone (the
   table in `doc/design/README.md` maps modules to docs), the accepted ADRs
   in `doc/decisions/`, and the existing code the milestone builds on.
   List any open questions in those docs that block the work and ask the
   user to decide them before going further.

3. **Tests first.** Launch a subagent to write `tests/<module>.scm` from
   the design doc alone, without reading or writing the implementation,
   so the tests aren't shaped by the code. Give it:
   - the design doc path(s) and the ADRs that apply
   - the test conventions in CLAUDE.md ("Tests"), including the exit-code
     idiom from `tests/smoke.scm`
   - for the reader: a test for every error case listed in `03-reader.md`

   Review what it wrote against the doc. Run `make check` and confirm the
   new tests fail for the right reason (missing code), not because of
   mistakes in the tests.

4. **Plan.** Enter plan mode and propose the implementation: records,
   exported procedures, the order of work, and any design doc changes the
   work will need. Wait for approval.

5. **Implement** in small commits until `make check` passes. Follow
   "Scheme style" in CLAUDE.md.

6. **Finish.** Update the design doc's `Status:` line and its
   Implemented / Planned / Open questions sections. Run `/doc-audit` and fix
   any drift it finds in this milestone's area. Then tell the user the
   milestone is ready for `/ship`. Don't push or open a PR until they ask.
