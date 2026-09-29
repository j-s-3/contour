---
name: ship
description: Take one change in this repo from request to merged PR - isolated worktree, implement, local CI gates, open PR, babysit CI and conflicts, squash-merge when green, remove the worktree. Use for any code change to Contour unless the user says to work directly on the current branch or not to merge.
argument-hint: <what to change, or an issue number>
---

# Ship a change end to end

Task: $ARGUMENTS

Run every step below without asking for confirmation, except where a step says to stop.
If `$ARGUMENTS` is an issue number, read it with `gh issue view <n>` and reference it in the PR.

## 1. Isolated worktree

- `git fetch origin main`.
- Enter a fresh worktree with the `EnterWorktree` tool (load it via ToolSearch if deferred),
  named after a short kebab-case slug of the task. Base it on `origin/main`, not local `main`.
- Branch name: `<type>/<slug>` where type is `feat`, `fix`, `refactor`, `test`, `docs` or `chore`
  (or `coverage/<issue>-<slug>` for coverage work, matching existing branches).
- Do all remaining work inside the worktree. Never commit on `main` in the primary checkout.

## 2. Implement

Follow the root `CLAUDE.md` in full: no code comments, logic in testable types, Swift Testing
for new suites, 90%+ coverage on every file added or changed, security invariants untouched.

## 3. Local gates (mirror CI before every push)

Run in this order and fix anything that fails before moving on:

```sh
swift format --in-place --recursive --parallel Sources Tests Package.swift
swift format lint --strict --recursive --parallel Sources Tests Package.swift
swiftlint lint --strict
swift build
swift test --enable-code-coverage
scripts/periphery.sh
```

Then run the coverage report from `CLAUDE.md` and check each touched file is at 90%+.
Commit formatter changes. Skip Address Sanitizer locally unless the change touches concurrency
or unsafe code; CI runs it.

## 4. Open the PR

- Commit with a message that carries the rationale (the code has no comments, so the commit does).
- `git push -u origin HEAD`, then `gh pr create` with a summary, a test plan, `Closes #<n>` when
  there is an issue, and the attribution footer.

## 5. Babysit until mergeable

Loop until the PR is green and mergeable:

1. Wait for CI: run `gh pr checks <pr> --watch --interval 30` in the background and wait for
   the completion notification rather than polling.
2. On a failed check: `gh run view <run-id> --log-failed`, diagnose (use
   superpowers:systematic-debugging), fix in the worktree, rerun the local gates, push a new
   commit. Do not re-run a job hoping a real failure goes away; re-run once only if the log
   shows an infrastructure flake (runner lost, network, Xcode download).
3. Conflicts / out of date: check `gh pr view <pr> --json mergeable,mergeStateStatus`.
   If `DIRTY` or `BEHIND`: `git fetch origin main && git rebase origin/main`, resolve
   conflicts preserving both sides' intent, rerun the local gates, `git push --force-with-lease`.
4. Review comments from anyone other than the user: handle them per the user's global PR-review
   instructions (fix, commit separately, draft replies locally) and **stop before merging** so
   the user can review the drafts.

Stop and report instead of looping forever if the same check fails three times after
attempted fixes, or if a conflict requires a product decision.

## 6. Merge

Only when all checks pass, `mergeStateStatus` is `CLEAN`, and there are no unaddressed review
comments from others:

```sh
gh pr merge <pr> --squash --delete-branch
```

`main` has no branch protection, so do not use `--auto` (it would merge before checks finish).

## 7. Clean up

- `ExitWorktree` with removal of the worktree.
- In the primary checkout: `git checkout main && git pull --ff-only`, `git branch -D <branch>`
  if it still exists locally, `git worktree prune`.

## 8. Report

One short summary: PR link, merged commit, what changed, anything that needed a judgment call.
