# 0024 An iteration's notes are called design ideas

Status: accepted (2026-11-21)

Context: ADR 0023 put each iteration's thinking in a folder called `notes/`. "Notes" is ambiguous in this project, where a note is also a musical note, and the name doesn't say what the files are: ideas for the design, not yet decided.

Decision: The folder is `doc/iterations/NN-name/design_ideas/`, and its files are called design ideas. Nothing else in ADR 0023 changes. Where ADR 0023 says `notes/` or notes, read `design_ideas/` or design ideas.

Consequences: Iteration 2's folder is renamed, with its history kept, and the paths in its targets, its README and the backlog are updated, along with CLAUDE.md, `/promote-design` and the PR template. ADR 0023 stays accepted.
