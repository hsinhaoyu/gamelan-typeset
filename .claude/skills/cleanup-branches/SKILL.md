---
name: cleanup-branches
description: Delete local and GitHub branches whose pull requests have been merged, including squash-merged ones. Use when the user asks to clean up merged branches or after PRs are merged on github.com.
disable-model-invocation: true
---

# Clean up merged branches

Delete branches whose PRs are merged, locally and on GitHub. Never delete
`main`, `dev`, or the branch that is currently checked out.

## Steps

1. Refresh remote state and drop tracking refs for branches already deleted
   on GitHub:

   ```
   git fetch --prune origin
   ```

2. List merged PRs and their head branches:

   ```
   gh pr list --state merged --limit 100 --json number,headRefName,headRefOid,baseRefName
   ```

   Use this, not `git branch --merged`: PRs here are squash-merged, so the
   branch commits never appear in the base branch's history.

3. For each local branch (`git for-each-ref refs/heads --format='%(refname:short)'`)
   that is the head of a merged PR, classify it:
   - **Safe**: the local tip equals the PR's `headRefOid`, or is an ancestor of it.
   - **Has unmerged work**: the local branch has commits not in the PR
     (`git log --oneline <headRefOid>..<branch>` is non-empty). Do not delete;
     report these commits to the user.

   Also find branches still on GitHub (`git branch -r`) whose PR is merged.
   These exist only if auto-delete on merge was off when the PR was merged.

4. Skip `main`, `dev`, and the current branch. If the current branch is a
   merged PR branch, tell the user and suggest `git switch dev` first.

5. Show the user the list: branch, PR number, local and/or GitHub, and any
   branches held back with the reason. Ask for confirmation before deleting.

6. On confirmation:
   - local: `git branch -D <branch>` (`-D` is needed because squash merges
     are not seen as merged by git; step 3 already checked safety)
   - GitHub: `git push origin --delete <branch>`

7. Report what was deleted and run `git branch -vv` to show what remains.
   Also mention if local `main` or `dev` is behind `origin`, so the user can
   update it with `git pull`.
