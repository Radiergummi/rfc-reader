---
name: pr-review-fix
description: Review every open pull request of this repository (or the numbers given) with a subagent each - code-review at level high, then simplify, fix what is clearly right, verify, commit signed and push back to the PR's branch - and bring the maintainer one list of the decisions that have no obvious answer. Use when asked to "review the open PRs", "review and fix PR N", or "/pr-review-fix [N...]".
---

# Review and fix pull requests

You orchestrate; one subagent per pull request does the work. You never edit a PR's code yourself, apart from resolving a trivial conflict between stacked PRs (below).

## 1. List and order

```sh
gh pr list --state open --json number,title,headRefName,baseRefName,isDraft --limit 50
git worktree list
```

- Take the numbers you were given, or every open PR.
- **Stacked PRs:** a PR whose `baseRefName` is another PR's branch is reviewed *after* its base, never at the same time. The base's fixes change the files the stacked PR builds on, and both runs on this repo that ignored this ended in a conflict (#389 on #379, #400 on #399).
- Drafts are reviewed like the rest, but their subagent reports what looks unfinished instead of finishing the feature.
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
1. Read CLAUDE.md, `gh pr view N` and the linked issue.
2. `Skill(skill: "code-review", args: "N high")`. Never pass --comment; post nothing to GitHub.
3. `Skill(skill: "simplify")` on the PR's diff. Do its four angles yourself in one pass unless the diff is large; do not spawn agents for a small one.
4. Verify every finding yourself. Fix the real ones; a bug fix gets a failing test first where the test rules allow it.
5. `make check`. Add `make test-app` if RFCReaderKit or anything it depends on changed, and `make build-app CODE_SIGNING_ALLOWED=NO` (and `make ios-sim CODE_SIGNING_ALLOWED=NO`) for app code.
6. Commit in the repo's style, ending with the Co-Authored-By line. Sign it; if Secretive is locked, `git -c gpg.format=openpgp -c user.signingkey=8F4ED9558B0722C0 commit ...`. Never unsigned, never a config change.
7. `git status -sb` shows BRANCH, then `git push origin BRANCH`. No force-push.
8. If the PR description now says something untrue, fix it with `gh pr edit N --body-file`.

Do not decide on assumptions: product or UX behaviour, design tradeoffs, scope changes, anything contradicting the PR's or issue's intent, and anything touching a docs/ARCHITECTURE.md decision are left alone and reported as questions with the options and your recommendation.

Report: each finding as fixed / rejected with reason / question; what simplify changed; commits pushed; which make targets ran and their result; questions.
</prompt>

## 3. As each report arrives

- Append its questions to one scratchpad file, grouped by PR, with the commit pushed and the verification result. Relay a two- or three-sentence summary to the user; do not repeat the whole report.
- Spot-check anything that would break a repository rule if the agent were wrong, e.g. that a "new fixture" it switched a test to is already committed on `main` (`git ls-tree -r --name-only origin/main Packages/RFCKit/Tests/RFCKitTests/Fixtures`).
- After a base PR is pushed, check its stacked PR still merges: `git merge-tree --write-tree --name-only origin/BASE origin/BRANCH`. A conflict that is purely additive on both sides (two entries at one spot in `.gitignore`) you may resolve by merging the base into the stacked branch and keeping both. Anything else is a question.
- **A rate limit stops an agent mid-work** with its changes uncommitted in the worktree. Resume the same agent with `SendMessage` to its id rather than starting a new one: it keeps its context and its unfinished changes.

## 4. Hand over

When every PR has reported, give the user the whole question list at once, grouped by PR, each with the options and the agent's recommendation, and the blockers (conflicts, unverified behaviour, measurements still to take) first.
