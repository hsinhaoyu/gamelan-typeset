---
name: promote-design
description: Promote the current iteration's design notes into one design doc in doc/design/ and its ADRs - draft the changes, pause for review, open the PR. The Decide phase of an iteration (ADR 0023).
argument-hint: "[design doc, e.g. 01-notation.md]"
disable-model-invocation: true
---

# Promote design notes into one design doc

Argument: the design doc to promote, e.g. `01-notation.md`.

This is the only step that reads an iteration's notes (ADR 0023). It
changes `doc/design/`, `doc/decisions/` and the iteration's README, and
nothing else.

## Steps

1. **Check.** Find the current iteration: the latest
   `doc/iterations/NN-*/README.md`. Its status must be `deciding`; if
   not, stop. Check the order in its "Promotion" section (01; 02 and 03;
   04 and 05; 06 and the build order): if a doc this one depends on
   isn't promoted yet, stop and say which. The working tree must be
   clean.

2. **Branch.** From an up-to-date `dev`: `doc/promote-<doc>`, e.g.
   `doc/promote-01-notation`.

3. **Read** the iteration's README, every note in its `notes/` (where a
   note says another one wins, follow it), its `targets/`, the
   references it links to, the design doc, the accepted ADRs, and the
   ADRs that earlier promotion PRs added.

4. **Find the decisions** that change this doc. List them, each with the
   note and section it comes from. Anything a note leaves open or marks
   "later" isn't promoted: it goes to `doc/iterations/backlog.md`, with
   a link to its note, unless it is already there.

5. **Draft:**
   - **The ADRs that land with this doc:** those whose decisions change
     this doc first and haven't landed in an earlier promotion PR.
     - Use the next numbers.
     - Set the old ADRs' statuses to `superseded by NNNN`.
     - Add each new ADR to the index.
     - Where an earlier PR's ADR already covers a decision, refer to it
       instead of writing a new one.
   - **The doc's changes.**
     - Label new parts **Planned** (agreed, not built).
     - Make the `Status:` line say what is implemented and what is
       planned.
     - Describe the design, not the discussion: no "we considered", no
       links to the notes.

6. **Pause for review.** Show the list from step 4, the ADRs, and a
   summary of the doc changes. Wait for the user's go-ahead, and make
   the changes they ask for first.

7. **Finish.**
   - Record the doc as promoted in the iteration README's "Promotion"
     section.
   - If it was the last doc:
     - fill in the iteration's "Milestones": the milestones and their
       slices, with branch names;
     - set its `Status:` to `building`;
     - update "Build order" in `doc/design/README.md`.
   - Run `make check`.
   - Commit, and open the PR with `/ship`, only when the user asks.
     Tick "Promotes design notes (iteration N, design doc …)".

Never change code, tests or the manual here. They change when the
milestones are built.
