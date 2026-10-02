---
name: pr-review-fix
description: Review every open pull request of this repository (or the numbers given) with a subagent each - code-review at level high, then simplify, fix what is clearly right, verify, commit signed and push back to the PR's branch - and bring the maintainer one list of the decisions that have no obvious answer. A `gh stack` stack gets one subagent that works it bottom-up and rebases each fix up the stack. Use when asked to "review the open PRs", "review and fix PR N", or "/pr-review-fix [N...]".
---

# Review and fix pull requests

You orchestrate; one subagent per pull request does the work. You never edit a PR's code yourself, apart from resolving a trivial conflict between stacked PRs (below).

## 1. List and order

```sh
gh pr list --state open --json number,title,headRefName,baseRefName,isDraft --limit 50
git worktree list
```

- Take the numbers you were given, or every open PR that is ready for review.
- **Stacked PRs:** a PR whose `baseRefName` is another PR's branch is reviewed *after* its base, never at the same time. The base's fixes change the files the stacked PR builds on, and both runs on this repo that ignored this ended in a conflict (#389 on #379, #400 on #399).
- **A `gh stack` stack** (branches `epic/…`, made by `work-issue` for an epic) goes to **one subagent for the whole stack**, which works it bottom-up and carries each fix up the stack itself. See [Stacks](#stacks). A chain of PRs that isn't a `gh stack` stack keeps the rule above, with one subagent per PR.
- **A draft is skipped unless you were given its number.** A draft means a session is working on it or it waits for the maintainer (`work-issue`'s "Pull request status"), so reviewing it would overlap. A draft given by number is reviewed like the rest, but its subagent reports what looks unfinished instead of finishing the feature, and leaves it a draft.
- Map each branch to its existing worktree under `.claude/worktrees/`. A PR without one gets `git worktree add .claude/worktrees/pr-N <branch>` from its subagent.

## 2. One subagent per PR, at most five at a time

Write the prompt below to the scratchpad once per PR and start each agent with `subagent_type: general-purpose`, **no `name:`**, pointing at its file. Start the next queued PR as each one reports.

<prompt>
Review, simplify and fix pull request #N ("TITLE", branch `BRANCH`, base `BASE`). Commit the fixes and push them back to that branch.

Workspace
- Work only in the PR's worktree (WORKTREE), never in /Users/moritz/Projects/rfc-reader: other sessions share that checkout and switch its branch.
- `git fetch origin`; the branch must be at or fast-forwardable to `origin/BRANCH`. If the worktree has uncommitted changes or unpushed commits you did not make, stop and report that.
- Do not merge or rebase the base into the branch. Report a conflict instead.
- If the base is not `main`, review only the commits that are not on the base.

Steps
0. If the PR is ready for review, turn it into a draft before you change anything: `gh pr ready N --undo`. That tells other sessions it is being worked on. A PR that was already a draft stays one, and you never mark it ready.
1. Read CLAUDE.md, `gh pr view N` and the linked issue.
2. `Skill(skill: "code-review", args: "N high")`. Never pass --comment; post nothing to GitHub.
3. `Skill(skill: "simplify")` on the PR's diff. Do its four angles yourself in one pass unless the diff is large; do not spawn agents for a small one.
4. Verify every finding yourself. Fix the real ones; a bug fix gets a failing test first where the test rules allow it.
5. `make check`. Add `make test-app` if RFCReaderKit or anything it depends on changed, and `make build-app CODE_SIGNING_ALLOWED=NO` (and `make ios-sim CODE_SIGNING_ALLOWED=NO`) for app code.
6. Commit in the repo's style, ending with the Co-Authored-By line. Sign it; if Secretive is locked, `git -c gpg.format=openpgp -c user.signingkey=8F4ED9558B0722C0 commit ...`. Never unsigned, never a config change.
7. `git status -sb` shows BRANCH, then `git push origin BRANCH`. No force-push.
8. If the PR description now says something untrue, fix it with `gh pr edit N --body-file`.
9. If you turned the PR into a draft in step 0 and leave no question, mark it ready again: `gh pr ready N`. If you leave a question, or stopped on a conflict, it stays a draft until the maintainer has answered.

Do not decide on assumptions: product or UX behaviour, design tradeoffs, scope changes, anything contradicting the PR's or issue's intent, and anything touching a docs/ARCHITECTURE.md decision are left alone and reported as questions with the options and your recommendation.

Report: each finding as fixed / rejected with reason / question; what simplify changed; commits pushed; which make targets ran and their result; whether the PR ended ready or a draft; questions.
</prompt>

## 3. As each report arrives

- Append its questions to one scratchpad file, grouped by PR, with the commit pushed and the verification result. Relay a two- or three-sentence summary to the user; do not repeat the whole report.
- Check the PR's status matches the report: `gh pr view N --json isDraft`. Ready only when the report leaves no question.
- Spot-check anything that would break a repository rule if the agent were wrong, e.g. that a "new fixture" it switched a test to is already committed on `main` (`git ls-tree -r --name-only origin/main Packages/RFCKit/Tests/RFCKitTests/Fixtures`).
- After a base PR is pushed, check its stacked PR still merges (a `gh stack` stack needs none of this: its subagent rebases it): `git merge-tree --write-tree --name-only origin/BASE origin/BRANCH`. A conflict that is purely additive on both sides (two entries at one spot in `.gitignore`) you may resolve by merging the base into the stacked branch and keeping both. Anything else is a question.
- **A rate limit stops an agent mid-work** with its changes uncommitted in the worktree. Resume the same agent with `SendMessage` to its id rather than starting a new one: it keeps its context and its unfinished changes.

## Stacks

A stack made with `gh stack` is reviewed by one subagent, in one worktree, bottom PR first. It is the same review as above, repeated per PR, with `gh stack` doing the cascading rebase that `git merge-tree` and a hand merge did before. Give it the prompt above with these changes to it:

<prompt-changes>
Workspace
- The stack's worktree is `.claude/worktrees/stack-TOP`. Make it with `git worktree add --detach`, then run `gh stack checkout TOP` there to get every branch of the stack with its local tracking. TOP is the top PR's number.
- Replace "Do not merge or rebase the base into the branch" and "No force-push" with the rules below. They apply to this stack's branches only.

For each PR, bottom first
1. `git switch BRANCH`, then steps 0–9 above. `code-review` on the PR number already reviews only the PR's own diff against the branch below it.
2. When you pushed a fix, carry it up: `gh stack rebase --upstack`, then check `git log --format='%G? %h %s' origin/main..` from the top branch (no commit may show `N`), then `gh stack push`. That push is a force-with-lease of the stack's own branches, and it is allowed. If Secretive is locked, give the fallback key to the rebase through the environment: `GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=gpg.format GIT_CONFIG_VALUE_0=openpgp GIT_CONFIG_KEY_1=user.signingkey GIT_CONFIG_VALUE_1=8F4ED9558B0722C0 gh stack rebase --upstack`.
3. A rebase conflict that is purely additive on both sides may be resolved, keeping both: resolve it, `git add`, then `gh stack rebase --continue`. Anything else: `gh stack rebase --abort`, stop, and report it as a question.

Never
- Use GitHub's "Rebase stack" button, or leave a rebase to GitHub. Commits made by a server-side rebase are unsigned, and this repository requires signed commits.
- `gh stack merge`, `gh stack unstack`, or `gh stack sync` when it reports that the stack on GitHub diverged from yours. Report the divergence instead.

Report per PR, bottom first, and say which rebases and pushes carried which fix up the stack.
</prompt-changes>

**A stack whose bottom PR merged while it waited.** GitHub rebases the next PR onto `main` itself when the one below merges, and those commits may be unsigned. Run `gh stack sync --prune` first, then the `%G?` check. If a commit shows `N`, re-sign from the new bottom: `git switch` to its branch, `git rebase --force-rebase origin/main`, then `gh stack rebase --upstack` and `gh stack push`.

## 4. Hand over

When every PR has reported, give the user the whole question list at once, grouped by PR, each with the options and the agent's recommendation, and the blockers (conflicts, unverified behaviour, measurements still to take) first. Say which PRs are ready and which stay drafts for a question.

When the maintainer answers, resume that PR's agent with `SendMessage` to apply the answer, verify, push, and mark the PR ready (step 9).
