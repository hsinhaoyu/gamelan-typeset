# 0023 Work is organised in iterations

Status: accepted (2026-11-21)

Context: The first build order ran from the piece records to `notasi render` and is done. The next work (typesetting two published examples) began as long discussions written as design notes, which are not decisions. Without a rule for when notes become the design, someone could build from half-decided ideas, or from a design that is half updated. Development material (design docs, ADRs, notes, Claude Code files) also sat on every branch, including `main`, which is what users get.

Decision:
- Work is organised in iterations. An iteration is a goal plus an acceptance test, worked through in five phases: (1) explore: discussion, written as dated notes; (2) decide: the notes are promoted into `doc/design/` and ADRs; (3) build: milestones and slices, with `/start-milestone`; (4) verify: the acceptance test, and `/doc-audit`; (5) close: `/release`, and a version tag.
- An iteration's status is `deciding` (phases 1–2), `building` (3–4) or `done`. While it is `deciding`, no milestone starts.
- Promotion is one PR per design doc, in dependency order: 01; then 02 and 03; then 04 and 05; then 06 and the build order. Each ADR lands in the PR of the first design doc it changes, and later PRs refer to it. Promotion, done with `/promote-design` when the user asks, is the only step that reads notes; notes are never the design and nothing is built from them.
- Versions: one minor version per iteration (iteration N is v0.N.0), with v0.N.x for fixes. Iteration 1 was released as v0.1.x.
- There is no retrospective section.
- Folders: `doc/iterations/NN-name/` holds the iteration's `README.md` (goal, acceptance test, status, milestones), `notes/` (thinking only) and `targets/` (the pieces of the acceptance test); `doc/iterations/backlog.md` holds everything deferred, each item with a link to its note; `doc/references/` holds reference material useful beyond one iteration.
- `main` holds only what users need. `.claude/`, `CLAUDE.md`, `doc/design/`, `doc/decisions/`, `doc/iterations/`, `doc/references/`, `doc/prototypes/`, `tests/decisions.scm` and `tests/iterations.scm` exist only on `dev`. A release is not a merge: `/release` builds one commit on a `release/v0.N.0` branch from `main`, with `dev`'s files minus those paths, and it is squash-merged into `main`. Version tags go on `main`; v0.1.0 and v0.1.1, made before this decision, stay on `dev`.

Consequences: The design changes only through promotion or building, so `doc/design/` is never half updated while milestones are built from it. Iteration 2 can't start a milestone until all its design docs are promoted, which delays building but keeps each promotion PR reviewable. Milestone 5 (scores in Typst documents) moves to the backlog. `main` and `dev` no longer share history after the first release, so nothing is ever merged between them; fixes are made on `dev` and released as a `.PATCH`. Code comments that point to `doc/design/` are for developers, who work on `dev`.
