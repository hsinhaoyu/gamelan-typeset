---
name: release
description: Open a merge-commit PR from dev into main at a milestone.
disable-model-invocation: true
---

# Release dev to main

`main` only receives merge-commit PRs from `dev` at milestones (see "Git
workflow" in CLAUDE.md).

## Steps

1. `git fetch --prune origin`. List what's new:
   `git log --oneline origin/main..origin/dev`. If nothing, say so and stop.

2. Check `origin/dev`'s CI status (`gh run list --branch dev --limit 1`).
   If it isn't green, stop and say so.

3. Ask the user which milestone this release completes, unless they said.
   Suggest running `/doc-audit` first if it hasn't been run since the last
   milestone PR.

4. Open the PR from `dev` itself, without a new branch:

   ```
   gh pr create --base main --head dev --title "Release: <milestone>"
   ```

   The body lists the PRs since the last release (from the log in step 1)
   and the Docs checkbox from the PR template.

5. Tell the user to merge it with **"Create a merge commit"**, not squash,
   so `main`'s history keeps each PR from `dev`. Don't merge it yourself.
   `dev` survives the merge: it is the repo's default branch and is
   protected, so GitHub's delete-branch-on-merge doesn't remove it, and
   `/cleanup-branches` skips it. Never delete `dev`.
