---
name: work-issue
description: Work one GitHub issue of this repository end to end, autonomously - pick it from the agent queue (or take the number given), ask on the issue when something is the maintainer's call, fix it test-first in its own worktree, and hand it over as a pull request marked ready for review. An issue labeled `epic` is worked as a whole, one stacked pull request per sub-issue, with `gh stack`. Use when asked to "work on issues", "take the next issue", "work epic N", or "/work-issue [N | label]" (a label such as `bug` narrows the queue to issues that carry it); run it under /loop to drain the queue.
---

# Work one issue

GitHub is the only state. Nothing about the queue is remembered between sessions: every run reads it from labels, comments and pull requests, and writes its result back there.

## Labels

| Label | Set by | Meaning |
|---|---|---|
| `agent-ready` | the maintainer | Queued for you. Never add it yourself. |
| `agent-blocked` | you | You asked on the issue and are waiting for an answer. |
| `agent-pr` | you | A pull request of yours closes it. |
| `epic` | the maintainer | Its sub-issues are one deliverable, worked as one stack. See [Epics](#epics). An unlabeled parent, such as #117–#121 or #173, is only a bucket: its children are worked one by one. |

## Comments

Your comments are posted from the maintainer's own account, so they cannot be told apart by author. Start every comment you post, on an issue or a pull request, with this exact first line:

```
<!-- work-issue --> 🤖 **Claude**
```

A comment without that marker is the maintainer's.

## 1. Pick the issue

If you were given a number, take that issue, whatever its labels. If you were given a label instead, such as `/work-issue bug`, it narrows every item in the list below to issues that carry it: in item 1, a pull request counts only when the issue it closes has the label, and an epic counts when the epic itself has it. Otherwise go down this list and take the first match:

1. **A pull request of yours with unanswered review feedback.** Your pull requests are the open ones whose branch starts with `issue/` or `epic/`. A review or comment on one, newer than your last commit and your last marked comment, is feedback. Address it on that branch (in a stack, see [Epics](#epics)). Reply with the marker, then mark the pull request ready again if it went back to draft.
2. **An `agent-blocked` issue that has been answered.** It counts as answered when the newest comment has no marker, or when your newest marked comment has a 👍 reaction (`gh api repos/{owner}/{repo}/issues/comments/ID/reactions`). Remove `agent-blocked` and pick up where you asked. When it is a sub-issue of an `epic`, or the epic itself, remove the label from both and resume the epic.
3. **The oldest `agent-ready` issue** with neither `agent-blocked` nor `agent-pr`. An `agent-ready` epic counts while one of its open sub-issues has no pull request. A sub-issue of an `agent-ready` epic is never taken alone: it is worked in its epic's stack.

**Skip any issue that is blocked by an open issue**, in 2 and 3 alike: GitHub's blocked-by relationship, not the prose. An epic counts as blocked when the next sub-issue it would work is blocked by an open issue outside the epic. It becomes pickable when its last blocker closes, with no label change. This lists the `agent-ready` issues that are still blocked:

```sh
gh api graphql -F owner='{owner}' -F name='{repo}' -f query='query($owner:String!,$name:String!){repository(owner:$owner,name:$name){issues(states:OPEN,labels:["agent-ready"],first:100){nodes{number blockedBy(first:20){nodes{number state}}}}}}' \
  --jq '.data.repository.issues.nodes[] | select(any(.blockedBy.nodes[]; .state=="OPEN")) | .number'
```

If nothing matches, say that the queue is empty (naming the label, if you were given one) and stop. Under `/loop`, end the loop too.

## 2. Understand it before touching code

Read the issue with its comments, and any issue or pull request it links. Read the sections of `docs/ARCHITECTURE.md`, `docs/DATA_PIPELINE.md` and `docs/VISION.md` for the code it touches, and the code itself. `CLAUDE.md`'s standing constraints apply in full.

**Ask whenever the answer is the maintainer's to give.** That means an issue that can be read two ways, a change to the document model or a standing constraint, a user-visible behavior the issue doesn't specify, or an expected result you can't pin down. It applies at this step and at any later one. Don't proceed on an assumption. To ask:

1. Post a marked comment. Say what you found, then ask numbered questions, each with the option you would choose and why.
2. Add `agent-blocked`. If you already have a draft pull request, leave it as a draft, with your work pushed.
3. Stop working on this issue. Under `/loop`, go on to the next one.

When the answer is that the issue waits for another one, record it as a relationship, not only in the comment: `addBlockedBy` (with `issueId` and `blockingIssueId`, the issues' node IDs) through `gh api graphql`. Then the pick above skips the issue until the blocker closes.

**An `enhancement` always gets a design comment first**, even when it seems clear. The comment covers: the scope (and what is out of scope), the approach, the modules and files it touches, how it will be tested, and any open questions. Then add `agent-blocked` and stop. A 👍 reaction on that comment, or a reply, is the go-ahead. Build what was agreed.

A bug that is clear gets no comment. Go straight on.

## 3. Isolate

Make a worktree off the latest `origin/main` with `EnterWorktree` (name `issue-N`), then rename its branch to `issue/N-short-slug`. When resuming an issue that already has a branch, enter that branch's worktree instead, or check the branch out into a fresh one.

## 4. Test first, and open the draft right away

1. Write the test that shows the bug, or pins the new behavior, and watch it fail for the right reason. Follow the testing rules in `CLAUDE.md`: prefer a guard-level test on hand-written lines, then a test through `parse` on a fixture already committed in `Fixtures`, then a `Corpus-backed:` test. Never commit RFC text, whether a new fixture, an excerpt of an existing one or an override snapshot.
2. Commit it, push, and open a **draft** pull request at once: `gh pr create --draft`. Its body says `Closes #N`, and the plan as you understand it. Add `agent-pr` to the issue.
3. Keep the pull request a draft for as long as you are working on it.

## 5. Fix

Make the smallest change that makes the test pass and follows the architecture. Commit in steps that each make sense alone. Legacy-parser heuristics follow the workflow in `CLAUDE.md`: a class of documents is fixed in the heuristic; a correction to a single document waits for #197, so no new override is committed.

## 6. Verify

Run all of these, and read their output rather than assuming it:

- `make fmt`, then `make check`. It must be clean, including `--strict` lint.
- `make test-app`, when anything under `Packages/RFCReaderKit` changed.
- `make xcodeproj build-app`, when anything under `App/` or `project.yml` changed.
- **A user-visible change in the app:** `make run`, look at it (the `run` skill), and describe what you saw in the pull request. If you couldn't check it visually, say so plainly.
- **A user-visible change on iOS:** `make run-sim CODE_SIGNING_ALLOWED=NO`, then look at a screenshot (`xcrun simctl io booted screenshot`). The Simulator runs headless and nothing can tap in it: `xcrun simctl openurl` stops at an "Open in RFC Reader?" prompt. So what launch doesn't show needs the iPhone (`devicectl … --payload-url` opens a link without asking) or the maintainer. Use the iPhone also for what the Simulator can't show, such as TextKit's layout or timing on real hardware.
- A wide legacy-parser change: `make corpus CORPUS_LIMIT=` before and after, then compare `corpus/report.json` between the two runs.

Then run `/code-review` on the branch's diff against `origin/main`, and fix what holds up.

## 7. Hand over

1. Push, and rewrite the pull request body in the repository's style (see recent merged pull requests): a `Why` section, a `What` section, and how it was verified, including what was *not* verified.
2. `gh pr ready`.
3. Leave the worktree with `ExitWorktree` using `keep`.
4. Report the pull request's URL, and any question left open.

## Epics

An issue labeled `epic` is one deliverable, and its open sub-issues are the steps. Work them as one stack of pull requests, one per sub-issue, each based on the one below, with `gh stack`. Everything above applies to each sub-issue; this section says only what differs.

**The order is the epic's sub-issue order**, bottom of the stack first (`subIssues` in GraphQL returns them in order). A blocked-by relationship between two sub-issues must agree with it. If one doesn't, reorder with `reprioritizeSubIssue` and say so in the design comment. A sub-issue that is closed is done. One that already has its own pull request off `main` stays out of the stack. If a later sub-issue needs its change, that is a question.

**One design comment, on the epic.** Before any code, post a marked comment on the epic covering the whole stack. Give the order, then for each sub-issue one or two lines: its scope and approach, or "bug, clear" where no design is needed. Link a design already agreed on a sub-issue instead of repeating it. End with numbered questions, as in step 2. Add `agent-blocked` to the epic and stop. A 👍 or a reply is the go-ahead for every sub-issue in it. A question that only comes up later, while working one sub-issue, is asked on that sub-issue.

**Isolate the whole epic in one worktree.** `EnterWorktree` with the name `epic-N`. Then `gh stack init --base main epic/N-slug/M-slug` makes the branch for the bottom sub-issue M. It starts from the local `main`, which may be behind, so run `gh stack rebase` straight after to put it on `origin/main`. `gh stack add epic/N-slug/M-slug` makes each next one, from the top of the stack. Resuming an epic, enter its worktree, or check the stack out into a fresh one with `gh stack checkout <branch>`, and continue with the lowest sub-issue that has no pull request.

**Each sub-issue, in turn:**

1. Steps 4–6 on its own branch. The draft is opened with `gh stack submit --auto`, which pushes every branch and creates each missing pull request as a draft on the branch below. Then edit the new pull request's body: `Closes #M`, `Part of #N`, and its place in the stack ("2 of 5"). Add `agent-pr` to the sub-issue, but never to the epic.
2. Run `/code-review` on the branch's diff against the branch below it, not against `origin/main`.
3. When the sub-issue is done, rewrite its pull request body as in step 7, and `gh pr ready` that pull request. It can then be reviewed while you work on the next one.

**A question stops the epic.** Ask on the sub-issue as in step 2, push what there is with `gh stack submit --auto`, add `agent-blocked` to the sub-issue and to the epic, and stop. The pull requests below it stay ready and can merge. Nothing above it gets built until the answer comes.

**A change lower in the stack** (review feedback, or `main` moving on) is committed on its own branch. Then `gh stack rebase` carries it up the stack and `gh stack push` publishes it. Use `gh stack sync`, which does both, when `main` has moved or a pull request at the bottom has merged (`--prune` drops the merged branch). Rebasing rewrites your commits, and they must stay signed. If Secretive is locked, run the command with the fallback key passed to git through the environment: `GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=gpg.format GIT_CONFIG_VALUE_0=openpgp GIT_CONFIG_KEY_1=user.signingkey GIT_CONFIG_VALUE_1=8F4ED9558B0722C0 gh stack rebase`. Afterwards check `git log --format='%G? %h %s' origin/main..` from the top branch: no commit may show `N`.

Never leave a rebase to GitHub, and never use its "Rebase stack" button: commits made by a server-side rebase are unsigned. GitHub does rebase the next pull request itself when the one below it merges, though. So after `sync`, a commit showing `N` is re-signed from the new bottom: `git rebase --force-rebase origin/main` on that branch, then `gh stack rebase --upstack` and `gh stack push`.

If `sync` reports that the stack on GitHub has diverged from yours, don't resolve it by choosing a side. Stop, and ask on the epic.

**Handing over the epic.** When every sub-issue has a ready pull request, run step 6 once more on the top branch, which holds the whole stack. Post a marked comment on the epic listing the stack's pull requests, bottom first, with any question left open. The maintainer merges the stack and closes the epic.

## Never

- Merge a pull request, push to `main`, or force-push someone else's branch. The maintainer merges. That includes `gh stack merge`, and `gh stack unstack`. The force-with-lease pushes `gh stack rebase`, `sync` and `submit` make to your own `epic/` branches are the exception.
- Close an issue, or remove `agent-ready`. `Closes #N` closes the issue on merge.
- Commit unsigned. Every branch requires signed commits. If signing fails because Secretive is locked, sign that commit with the fallback key: `git -c gpg.format=openpgp -c user.signingkey=8F4ED9558B0722C0 commit …`.
- Widen the change beyond the issue. Anything else you notice goes in a marked comment on the pull request or its issue. It becomes a new issue only if it clearly deserves one and is true of `main` without your pull request: an issue describes `main`, never an unmerged branch, so a limit, follow-up or gap of your own change stays on the pull request.
