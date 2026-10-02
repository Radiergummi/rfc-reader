---
name: work-issue
description: Work one GitHub issue of this repository end to end, autonomously - pick it from the agent queue (or take the number given), claim it at once with a draft pull request so no other session takes it, ask on the issue when something is the maintainer's call, fix it test-first in its own worktree, and mark the pull request ready for review only when it is done. An issue labeled `epic` is worked as a whole, one stacked pull request per sub-issue, with `gh stack`. Use when asked to "work on issues", "take the next issue", "work epic N", or "/work-issue [N | label]" (a label such as `bug` narrows the queue to issues that carry it); run it under /loop to drain the queue.
---

# Work one issue

GitHub is the only state. Nothing about the queue is remembered between sessions: every run reads it from labels, comments and pull requests, and writes its result back there.

## Labels

| Label | Set by | Meaning |
|---|---|---|
| `agent-ready` | the maintainer | Queued for you. Never add it yourself. |
| `agent-blocked` | you | You asked on the issue and are waiting for an answer. |
| `agent-pr` | you | A pull request of yours closes it, draft or ready. Added when you claim the issue (step 2). |
| `epic` | the maintainer | Its sub-issues are one deliverable, worked as one stack. See [Epics](#epics). An unlabeled parent, such as #117–#121 or #173, is only a bucket: its children are worked one by one. |

## Comments

Your comments are posted from the maintainer's own account, so they cannot be told apart by author. Start every comment you post, on an issue or a pull request, with this exact first line:

```
<!-- work-issue --> 🤖 **Claude**
```

A comment without that marker is the maintainer's.

## Pull request status

The pull request's status says where the issue stands, so that the next session, and the maintainer, can read it without asking:

| Where the issue stands | Pull request | Issue labels |
|---|---|---|
| Claimed, being worked on | draft | `agent-pr` |
| Waiting for the maintainer | draft | `agent-pr`, `agent-blocked` |
| Done | ready for review | `agent-pr` |

**Ready for review means done**: every question you asked has been answered, everything the issue asks for is built (nothing is left for a follow-up), and step 6 passed. Anything short of that stays a draft. A draft therefore always means that a session is working on it or that it waits for an answer. Going back to work on a ready pull request, turn it into a draft first (`gh pr ready N --undo`), and mark it ready again only when it is done again.

## 1. Pick the issue

If you were given a number, take that issue, whatever its labels. If you were given a label instead, such as `/work-issue bug`, it narrows every item in the list below to issues that carry it: in item 1, a pull request counts only when the issue it closes has the label, and an epic counts when the epic itself has it. Otherwise go down this list and take the first match:

1. **A ready pull request of yours with unanswered review feedback.** Your pull requests are the open ones whose branch starts with `issue/` or `epic/`. A review or comment on one, newer than your last commit and your last marked comment, is feedback. Turn the pull request into a draft, address the feedback on that branch (in a stack, see [Epics](#epics)), reply with the marker, and mark it ready again once it is done.
2. **An `agent-blocked` issue that has been answered.** It counts as answered when the newest comment has no marker, or when your newest marked comment has a 👍 reaction (`gh api repos/{owner}/{repo}/issues/comments/ID/reactions`). Remove `agent-blocked` and pick up where you asked. When it is a sub-issue of an `epic`, or the epic itself, remove the label from both and resume the epic.
3. **The oldest `agent-ready` issue** with neither `agent-blocked` nor `agent-pr`. An `agent-ready` epic counts while one of its open sub-issues has no pull request and none of them has a draft. A sub-issue of an `agent-ready` epic is never taken alone: it is worked in its epic's stack.

**Skip any issue someone is already on**, in 2 and 3 alike. An issue that an open pull request closes is taken, whatever its labels and whichever session or branch the pull request came from. A draft is being worked on right now, or waits for an answer (item 2 resumes those). A ready one is done and waits for review (item 1 resumes those). A draft whose last commit and last comment are both more than a day old, on an issue without `agent-blocked`, may be abandoned, or may wait for an answer given outside GitHub (`pr-review-fix` leaves a draft that way). Don't resume it; name it in your report so the maintainer decides. This lists the open pull requests with the issues they close:

```sh
gh pr list --state open --limit 100 --json number,isDraft,headRefName,closingIssuesReferences \
  --jq '.[] | "#\(.number) draft=\(.isDraft) \(.headRefName) closes \([.closingIssuesReferences[].number] | join(","))"'
```

**Skip any issue that is blocked by an open issue**, in 2 and 3 alike: GitHub's blocked-by relationship, not the prose. An epic counts as blocked when the next sub-issue it would work is blocked by an open issue outside the epic. It becomes pickable when its last blocker closes, with no label change. This lists the `agent-ready` issues that are still blocked:

```sh
gh api graphql -F owner='{owner}' -F name='{repo}' -f query='query($owner:String!,$name:String!){repository(owner:$owner,name:$name){issues(states:OPEN,labels:["agent-ready"],first:100){nodes{number blockedBy(first:20){nodes{number state}}}}}}' \
  --jq '.data.repository.issues.nodes[] | select(any(.blockedBy.nodes[]; .state=="OPEN")) | .number'
```

If nothing matches, say that the queue is empty (naming the label, if you were given one) and stop. Under `/loop`, end the loop too.

## 2. Claim it with a draft

Claim the issue before you read any further, so no other session takes it while you work:

1. Make a worktree off the latest `origin/main` with `EnterWorktree` (name `issue-N`), then rename its branch to `issue/N-short-slug`. When resuming an issue that already has a branch, enter that branch's worktree instead, or check the branch out into a fresh one, and skip the rest of this step: its draft is already open.
2. Make an empty commit, signed like every other (`git commit --allow-empty -m "Start on #N"`), push the branch, and open a **draft** pull request: `gh pr create --draft`. Its title is the issue's, and its body says `Closes #N`, with a line that the work has started and the plan follows. Add `agent-pr` to the issue.
3. List the open pull requests that close the issue again (the command in step 1). If an older one appeared while you claimed it, another session got there first: close yours with `gh pr close --delete-branch`, leave the labels alone, and go back to step 1.

## 3. Understand it before touching code

Read the issue with its comments, and any issue or pull request it links. Read the sections of `docs/ARCHITECTURE.md`, `docs/DATA_PIPELINE.md` and `docs/VISION.md` for the code it touches, and the code itself. `CLAUDE.md`'s standing constraints apply in full.

**Ask whenever the answer is the maintainer's to give.** That means an issue that can be read two ways, a change to the document model or a standing constraint, a user-visible behavior the issue doesn't specify, or an expected result you can't pin down. It applies at this step and at any later one. Don't proceed on an assumption. To ask:

1. Post a marked comment. Say what you found, then ask numbered questions, each with the option you would choose and why.
2. Add `agent-blocked`. Push what you have; the pull request stays a draft.
3. Stop working on this issue. Under `/loop`, go on to the next one.

When the answer is that the issue waits for another one, record it as a relationship, not only in the comment: `addBlockedBy` (with `issueId` and `blockingIssueId`, the issues' node IDs) through `gh api graphql`. Then the pick above skips the issue until the blocker closes.

**An `enhancement` always gets a design comment first**, even when it seems clear. The comment covers: the scope (and what is out of scope), the approach, the modules and files it touches, how it will be tested, and any open questions. Then add `agent-blocked` and stop. A 👍 reaction on that comment, or a reply, is the go-ahead. Build what was agreed.

A bug that is clear gets no comment. Go straight on.

## 4. Test first

1. Write the test that shows the bug, or pins the new behavior, and watch it fail for the right reason. Follow the testing rules in `CLAUDE.md`: prefer a guard-level test on hand-written lines, then a test through `parse` on a fixture already committed in `Fixtures`, then a `Corpus-backed:` test. Never commit RFC text, whether a new fixture, an excerpt of an existing one or an override snapshot.
2. Commit it, push, and write the plan as you understand it into the draft's body, under `Closes #N`.

## 5. Fix

Make the smallest change that makes the test pass and follows the architecture. Commit in steps that each make sense alone. Legacy-parser heuristics follow the workflow in `CLAUDE.md`: a class of documents is fixed in the heuristic; a correction to a single document waits for #197, so no new override is committed.

## 6. Verify

Run all of these, and read their output rather than assuming it:

- `make fmt`, then `make check`. It must be clean, including `--strict` lint.
- `make test-app`, when anything under `Packages/RFCReaderKit` changed.
- `make xcodeproj build-app`, when anything under `App/` or `project.yml` changed.
- **A user-visible change in the app:** `make run`, look at it (the `run` skill), and describe what you saw in the pull request. If you couldn't check it visually, say so plainly.
- A wide legacy-parser change: `make corpus CORPUS_LIMIT=` before and after, then compare `corpus/report.json` between the two runs.

Then run `/code-review` on the branch's diff against `origin/main`, and fix what holds up.

## 7. Hand over

Hand over only when the pull request is done (see [Pull request status](#pull-request-status)): every question you asked is answered, everything the issue asks for is built, and step 6 passed. If something is still open, it is a question (step 3), and the pull request stays a draft.

1. Push, and rewrite the pull request body in the repository's style (see recent merged pull requests): a `Why` section, a `What` section, and how it was verified, including what was *not* verified.
2. `gh pr ready`.
3. Leave the worktree with `ExitWorktree` using `keep`.
4. Report the pull request's URL, and any question left open.

## Epics

An issue labeled `epic` is one deliverable, and its open sub-issues are the steps. Work them as one stack of pull requests, one per sub-issue, each based on the one below, with `gh stack`. Everything above applies to each sub-issue; this section says only what differs.

**The order is the epic's sub-issue order**, bottom of the stack first (`subIssues` in GraphQL returns them in order). A blocked-by relationship between two sub-issues must agree with it. If one doesn't, reorder with `reprioritizeSubIssue` and say so in the design comment. A sub-issue that is closed is done. One that already has its own pull request off `main` stays out of the stack. If a later sub-issue needs its change, that is a question.

**Claim the epic first**, as in step 2: isolate it (below) and open the bottom sub-issue's draft (step 1 under "Each sub-issue"). Then the pick in other sessions skips it.

**One design comment, on the epic.** Before any code, post a marked comment on the epic covering the whole stack. Give the order, then for each sub-issue one or two lines: its scope and approach, or "bug, clear" where no design is needed. Link a design already agreed on a sub-issue instead of repeating it. End with numbered questions, as in step 3. Add `agent-blocked` to the epic and stop. A 👍 or a reply is the go-ahead for every sub-issue in it. A question that only comes up later, while working one sub-issue, is asked on that sub-issue.

**Isolate the whole epic in one worktree.** `EnterWorktree` with the name `epic-N`. Then `gh stack init --base main epic/N-slug/M-slug` makes the branch for the bottom sub-issue M. It starts from the local `main`, which may be behind, so run `gh stack rebase` straight after to put it on `origin/main`. `gh stack add epic/N-slug/M-slug` makes each next one, from the top of the stack. Resuming an epic, enter its worktree, or check the stack out into a fresh one with `gh stack checkout <branch>`, and continue with the lowest sub-issue whose pull request is still a draft, or that has none.

**Each sub-issue, in turn:**

1. Claim it when its turn comes: on its branch, make the empty signed commit of step 2, then `gh stack submit --auto`, which pushes every branch and creates each missing pull request as a draft on the branch below. Edit the new pull request's body: `Closes #M`, `Part of #N`, and its place in the stack ("2 of 5"). Add `agent-pr` to the sub-issue, but never to the epic.
2. Steps 4–6 on its branch.
3. Run `/code-review` on the branch's diff against the branch below it, not against `origin/main`.
4. When the sub-issue is done, as step 7 defines it, rewrite its pull request body as step 7 says, and `gh pr ready` that pull request. It can then be reviewed while you work on the next one.

**A question stops the epic.** Ask on the sub-issue as in step 3, push what there is with `gh stack submit --auto`, add `agent-blocked` to the sub-issue and to the epic, and stop. The pull requests below it stay ready and can merge. Nothing above it gets built until the answer comes.

**A change lower in the stack** (review feedback, or `main` moving on) is committed on its own branch. Then `gh stack rebase` carries it up the stack and `gh stack push` publishes it. Use `gh stack sync`, which does both, when `main` has moved or a pull request at the bottom has merged (`--prune` drops the merged branch). Rebasing rewrites your commits, and they must stay signed. If Secretive is locked, run the command with the fallback key passed to git through the environment: `GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=gpg.format GIT_CONFIG_VALUE_0=openpgp GIT_CONFIG_KEY_1=user.signingkey GIT_CONFIG_VALUE_1=8F4ED9558B0722C0 gh stack rebase`. Afterwards check `git log --format='%G? %h %s' origin/main..` from the top branch: no commit may show `N`.

Never leave a rebase to GitHub, and never use its "Rebase stack" button: commits made by a server-side rebase are unsigned. GitHub does rebase the next pull request itself when the one below it merges, though. So after `sync`, a commit showing `N` is re-signed from the new bottom: `git rebase --force-rebase origin/main` on that branch, then `gh stack rebase --upstack` and `gh stack push`.

If `sync` reports that the stack on GitHub has diverged from yours, don't resolve it by choosing a side. Stop, and ask on the epic.

**Handing over the epic.** When every sub-issue has a ready pull request, run step 6 once more on the top branch, which holds the whole stack. Post a marked comment on the epic listing the stack's pull requests, bottom first, with any question left open. The maintainer merges the stack and closes the epic.

## Never

- Merge a pull request, push to `main`, or force-push someone else's branch. The maintainer merges. That includes `gh stack merge`, and `gh stack unstack`. The force-with-lease pushes `gh stack rebase`, `sync` and `submit` make to your own `epic/` branches are the exception.
- Close an issue, or remove `agent-ready`. `Closes #N` closes the issue on merge.
- Commit unsigned. Every branch requires signed commits. If signing fails because Secretive is locked, sign that commit with the fallback key: `git -c gpg.format=openpgp -c user.signingkey=8F4ED9558B0722C0 commit …`.
- Widen the change beyond the issue. Anything else you notice goes in a marked comment on the pull request or its issue. It becomes a new issue only if it clearly deserves one and is true of `main` without your pull request: an issue describes `main`, never an unmerged branch, so a limit, follow-up or gap of your own change stays on the pull request.
