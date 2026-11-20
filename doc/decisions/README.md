# Decision log

This folder records design decisions as short, numbered ADRs (Architecture
Decision Records). `doc/design/` describes the design as it is now; these
records explain why it is that way.

## When to write one

- You reverse or narrow a decision documented in `doc/design/`.
- You make a choice someone might later question or "fix".

Routine changes that follow the existing design don't need one.

## Rules

- Number ADRs in order: the next one is the highest number plus one.
- An accepted ADR is never edited, except its `Status:` line.
- To change a decision, write a new ADR that says what it supersedes, and
  set the old one's status to `superseded by NNNN`. Update `doc/design/`
  in the same PR.
- Add every new ADR to the index below.

`tests/decisions.scm` checks the numbering, status lines and index.

## Template

```markdown
# NNNN Short title

Status: proposed | accepted (YYYY-MM-DD) | superseded by NNNN | deprecated

Context: What problem or situation prompted this.

Decision: What was decided.

Consequences: What follows from it, good and bad.

Supersedes: NNNN (only if it replaces an earlier decision)
```

## Index

- [0001 Notation is s-expressions](0001-notation-is-s-expressions.md)
- [0002 Time is a grid of equal steps](0002-time-is-a-grid-of-equal-steps.md)
- [0003 Notes are symbolic](0003-notes-are-symbolic.md)
- [0004 The model is the centre](0004-the-model-is-the-centre.md)
- [0005 Guile decides, Typst draws](0005-guile-decides-typst-draws.md)
- [0006 The JSON file is the contract with Typst](0006-json-is-the-contract-with-typst.md)
- [0007 Guile 3.0, standard library first](0007-guile-3-standard-library-first.md)
- [0008 The piece is the centre](0008-the-piece-is-the-centre.md)
