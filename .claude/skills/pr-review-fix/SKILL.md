---
name: pr-review-fix
description: Review every open pull request of this repository (or the numbers given) with a subagent each - code-review at level high, then simplify, fix what is clearly right, verify as CI does, commit signed and push back to the PR's branch, have a second agent re-review those fixes - and bring the maintainer a verdict per PR (merge, hand check, re-review, blocked, question) and one list of the decisions that have no obvious answer. A `gh stack` stack gets one subagent that works it bottom-up and rebases each fix up the stack. Use when asked to "review the open PRs", "review and fix PR N", or "/pr-review-fix [N...]".
---

# Review and fix pull requests

You orchestrate; one subagent per pull request does the work. You never edit a PR's code yourself, apart from resolving a trivial conflict between stacked PRs (below).

The point of the run is a verdict the maintainer can act on without reading the code: which PRs can be merged without a second thought, and which need something more. A clean local `make check` and a fixer who left no question are not that verdict. Two things on this repository proved it (October 2026): two PRs whose fixers reported every check green failed CI (iOS-only test code, and a float tolerance on the Simulator), and the fixes in about half the PRs were real logic that only their author had read.

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
0. If the PR is ready for review, turn it into a draft before you change anything: `gh pr ready N --undo`. That tells other sessions it is being worked on. A PR that was already a draft stays one, and you never mark it ready. If the command is denied, say so in the report and carry on.
1. Read CLAUDE.md, `gh pr view N` and the linked issue. Note the head commit now (`git rev-parse HEAD`): it is BEFORE in the report.
2. `Skill(skill: "code-review", args: "N high")`. Never pass --comment; post nothing to GitHub. The skill may reuse the level last typed instead of the one passed; say which level it ran at.
3. `Skill(skill: "simplify")` on the PR's diff. Do its four angles yourself in one pass unless the diff is large; do not spawn agents for a small one.
4. Verify every finding yourself. Fix the real ones; a bug fix gets a failing test first where the test rules allow it.
5. Verify as CI does (`.github/workflows/ci-macos.yml`), not less: `make check`; for RFCReaderKit or anything it depends on, also `make test-app-ios CODE_SIGNING_ALLOWED=NO IOS_SIMULATOR="iPhone 18 Pro"`, which runs the tests on the iOS Simulator where `make test-app` cannot see code behind `#if canImport(UIKit)` or the Simulator's float results; for app code, `make build-app CODE_SIGNING_ALLOWED=NO`, `make ios-sim CODE_SIGNING_ALLOWED=NO` and, if a user-visible string changed, `make strings-check`.
6. Commit in the repo's style, ending with the Co-Authored-By line. Sign it; if Secretive is locked, `git -c gpg.format=openpgp -c user.signingkey=8F4ED9558B0722C0 commit ...`. Never unsigned, never a config change.
7. `git status -sb` shows BRANCH, then `git push origin BRANCH`. No force-push.
8. If the PR description now says something untrue, fix it with `gh pr edit N --body-file`.
9. Unless you leave a question for the maintainer, mark the PR ready (`gh pr ready N`): `ci-macos.yml` skips its jobs, the app builds and the iOS Simulator tests among them, on a draft, so a draft has no CI to wait for. Then wait for CI on the head you pushed (or on the current head, if you pushed nothing), polling `gh pr checks N` until nothing is pending; a single `--watch` can outlast a tool's timeout. A failing check is fixed like any finding, or reported; it is never dismissed as unrelated without the log line that shows it.
10. A PR you leave a question on stays a draft, and says so in the report: its CI has not run.

Do not decide on assumptions: product or UX behaviour, design tradeoffs, scope changes, anything contradicting the PR's or issue's intent, and anything touching a decision in docs/ARCHITECTURE.md or docs/decisions/ are left alone and reported as questions with the options and your recommendation.

Report: BEFORE and the final head; each finding as fixed / rejected with reason / question; what simplify changed; commits pushed; which make targets ran and their result; the CI result on the final head; what was never run in the app or on a device; questions. Then a size for your own fixes: **none**, **trivial** (comments, renames, a moved line, a test only) or **logic** (anything that changes what the code does).
</prompt>

## 3. As each report arrives

- Append its questions to one scratchpad file, grouped by PR, with the commit pushed and the verification result. Relay a two- or three-sentence summary to the user; do not repeat the whole report.
- Check CI yourself rather than trusting the report: `gh pr checks N`. A failure goes back to the same agent with the failing log line (`gh run view --job ID --log-failed | grep -E '✘|error:'`).
- If its fixes are **logic**, start a [re-review](#re-review) of BEFORE..head once CI is green. Its fixes are not reviewed until then.
- Give the PR its [verdict](#verdicts) and set its state from it.
- Spot-check anything that would break a repository rule if the agent were wrong, e.g. that a "new fixture" it switched a test to is already committed on `main` (`git ls-tree -r --name-only origin/main Packages/RFCKit/Tests/RFCKitTests/Fixtures`).
- After a base PR is pushed, check its stacked PR still merges (a `gh stack` stack needs none of this: its subagent rebases it): `git merge-tree --write-tree --name-only origin/BASE origin/BRANCH`. A conflict that is purely additive on both sides (two entries at one spot in `.gitignore`) you may resolve by merging the base into the stacked branch and keeping both. Anything else is a question.
- **A rate limit stops an agent mid-work** with its changes uncommitted in the worktree. Resume the same agent with `SendMessage` to its id rather than starting a new one: it keeps its context and its unfinished changes.

## Re-review

The agent that wrote a fix is the worst judge of it. A fresh agent (`general-purpose`, no `name:`, counted against the five) reviews only BEFORE..head, in the same worktree, with this prompt. It never re-reviews its own work: a re-reviewer that makes a logic fix itself returns **re-review**, and the next round goes to another fresh agent. Answering a maintainer's question with code is a logic fix too, and gets the same.

<re-review-prompt>
Independently re-review the fix commits on pull request #N (branch `BRANCH`). Another agent reviewed this PR and pushed fixes; nobody but that agent has read them. Do not trust its reports or commit messages: read the code.

Scope: `git diff BEFORE..origin/BRANCH`. Look hardest at FOCUS (the fixes the report calls logic). Read the rest of the PR only as context.

Work only in WORKTREE, clean and at or fast-forwardable to `origin/BRANCH`; otherwise stop and report. Review for correctness bugs, regressions the fixes introduced, broken repository rules (CLAUDE.md), and tests that pass without testing what they claim; `Skill(skill: "code-review")` may help, posting nothing to GitHub. Verify every finding yourself.

Fix only a clear, local bug, test first where the rules allow, verified as CI does (the main prompt's step 5), committed signed and pushed after checking the PR is still open. Anything larger, and any design or product question, is reported. Then poll `gh pr checks N` on the final head until nothing is pending. Leave the PR ready: it is ready while it is re-reviewed, since the macOS CI jobs skip a draft.

End with exactly one verdict, as defined in the skill's Verdicts section, with one sentence of reasoning, and for **hand check** the exact steps. Report each finding (fixed / not fixed and why), commits pushed and the CI result.
</re-review-prompt>

## Verdicts

Every PR ends the run with exactly one, from the last report on it. Ready or draft only says whether CI can run (`ci-macos.yml` skips a draft) and whether the maintainer owes an answer; the verdict is what says merge:

| Verdict | When | PR state |
|---|---|---|
| **merge** | CI green on the final head; the fixes were none or trivial, or a re-review passed them; nothing unverified that could hide a user-visible regression | ready |
| **hand check** | the code holds up, but only the running app or a device can confirm a behavior that would be a user-visible regression if wrong; the steps are named | ready, with the steps in the hand-over |
| **re-review** | logic fixes nobody else has read, or logic the reviewer could not convince itself of | ready, so CI runs; the hand-over says not to merge it yet |
| **blocked** | CI fails, an unfixed bug, or a conflict | ready while an agent fixes it and CI must run; draft if it waits on the maintainer |
| **question** | a decision only the maintainer can make | draft, with the question in the hand-over |

A small PR in tooling, docs or benchmarks, with CI green, is **merge** even with unverified behavior, since nothing ships. Size alone never makes a verdict: a 50-line change to the build lifecycle can need a re-review where 800 lines of view copy do not.

## Stacks

A stack made with `gh stack` is reviewed by one subagent, in one worktree, bottom PR first. It is the same review as above, repeated per PR, with `gh stack` doing the cascading rebase that `git merge-tree` and a hand merge did before. Give it the prompt above with these changes to it:

<prompt-changes>
Workspace
- The stack's worktree is `.claude/worktrees/stack-TOP`. Make it with `git worktree add --detach`, then run `gh stack checkout TOP` there to get every branch of the stack with its local tracking. TOP is the top PR's number.
- Replace "Do not merge or rebase the base into the branch" and "No force-push" with the rules below. They apply to this stack's branches only.

For each PR, bottom first
1. `git switch BRANCH`, then steps 0–10 above. `code-review` on the PR number already reviews only the PR's own diff against the branch below it.
2. When you pushed a fix, carry it up: `gh stack rebase --upstack`, then check `git log --format='%G? %h %s' origin/main..` from the top branch (no commit may show `N`), then `gh stack push`. That push is a force-with-lease of the stack's own branches, and it is allowed. If Secretive is locked, give the fallback key to the rebase through the environment: `GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=gpg.format GIT_CONFIG_VALUE_0=openpgp GIT_CONFIG_KEY_1=user.signingkey GIT_CONFIG_VALUE_1=8F4ED9558B0722C0 gh stack rebase --upstack`.
3. A rebase conflict that is purely additive on both sides may be resolved, keeping both: resolve it, `git add`, then `gh stack rebase --continue`. Anything else: `gh stack rebase --abort`, stop, and report it as a question.

Never
- Use GitHub's "Rebase stack" button, or leave a rebase to GitHub. Commits made by a server-side rebase are unsigned, and this repository requires signed commits.
- `gh stack merge`, `gh stack unstack`, or `gh stack sync` when it reports that the stack on GitHub diverged from yours. Report the divergence instead.

Report per PR, bottom first, and say which rebases and pushes carried which fix up the stack.
</prompt-changes>

**A stack whose bottom PR merged while it waited.** GitHub rebases the next PR onto `main` itself when the one below merges, and those commits may be unsigned. Run `gh stack sync --prune` first, then the `%G?` check. If a commit shows `N`, re-sign from the new bottom: `git switch` to its branch, `git rebase --force-rebase origin/main`, then `gh stack rebase --upstack` and `gh stack push`.

## 4. Hand over

When every PR has a verdict, lead with them, grouped: **merge** first (the PRs the maintainer can merge without reading), then **hand check** with each one's steps, then **re-review**, **blocked** and **question** with the reason in one line. A ready PR is not a merge verdict; only this list is. Then the whole question list at once, grouped by PR, each with the options and the agent's recommendation.

When the maintainer answers, resume that PR's agent with `SendMessage` to apply the answer, verify as in step 5, push and wait for CI. An answer applied as code is a logic fix: it goes to a re-review before the PR can be **merge**.
