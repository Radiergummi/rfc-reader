---
name: work-issue
description: Work one GitHub issue of this repository end to end, autonomously - pick it from the agent queue (or take the number given), ask on the issue when something is the maintainer's call, fix it test-first in its own worktree, and hand it over as a pull request marked ready for review. Use when asked to "work on issues", "take the next issue", or "/work-issue [N]"; run it under /loop to drain the queue.
---

# Work one issue

GitHub is the only state. Nothing about the queue is remembered between sessions: every run reads it from labels, comments and pull requests, and writes its result back there.

## Labels

| Label | Set by | Meaning |
|---|---|---|
| `agent-ready` | the maintainer | Queued for you. Never add it yourself. |
| `agent-blocked` | you | You asked on the issue and are waiting for an answer. |
| `agent-pr` | you | A pull request of yours closes it. |

## Comments

Your comments are posted from the maintainer's own account, so they cannot be told apart by author. Start every comment you post, on an issue or a pull request, with this exact first line:

```
<!-- work-issue --> 🤖 **Claude**
```

A comment without that marker is the maintainer's.

## 1. Pick the issue

If you were given a number, take that issue, whatever its labels. Otherwise go down this list and take the first match:

1. **A pull request of yours with unanswered review feedback.** Your pull requests are the open ones whose branch starts with `issue/`. A review or comment on one, newer than your last commit and your last marked comment, is feedback. Address it on that branch. Reply with the marker, then mark the pull request ready again if it went back to draft.
2. **An `agent-blocked` issue that has been answered.** It counts as answered when the newest comment has no marker, or when your newest marked comment has a 👍 reaction (`gh api repos/{owner}/{repo}/issues/comments/ID/reactions`). Remove `agent-blocked` and pick up where you asked.
3. **The oldest `agent-ready` issue** with neither `agent-blocked` nor `agent-pr`.

If nothing matches, say that the queue is empty and stop. Under `/loop`, end the loop too.

## 2. Understand it before touching code

Read the issue with its comments, and any issue or pull request it links. Read the sections of `docs/ARCHITECTURE.md`, `docs/DATA_PIPELINE.md` and `docs/VISION.md` for the code it touches, and the code itself. `CLAUDE.md`'s standing constraints apply in full.

**Ask whenever the answer is the maintainer's to give.** That means an issue that can be read two ways, a change to the document model or a standing constraint, a user-visible behaviour the issue doesn't specify, or an expected result you can't pin down. It applies at this step and at any later one. Don't proceed on an assumption. To ask:

1. Post a marked comment. Say what you found, then ask numbered questions, each with the option you would choose and why.
2. Add `agent-blocked`. If you already have a draft pull request, leave it as a draft, with your work pushed.
3. Stop working on this issue. Under `/loop`, go on to the next one.

**An `enhancement` always gets a design comment first**, even when it seems clear. The comment covers: the scope (and what is out of scope), the approach, the modules and files it touches, how it will be tested, and any open questions. Then add `agent-blocked` and stop. A 👍 reaction on that comment, or a reply, is the go-ahead. Build what was agreed.

A bug that is clear gets no comment. Go straight on.

## 3. Isolate

Make a worktree off the latest `origin/main` with `EnterWorktree` (name `issue-N`), then rename its branch to `issue/N-short-slug`. When resuming an issue that already has a branch, enter that branch's worktree instead, or check the branch out into a fresh one.

## 4. Test first, and open the draft right away

1. Write the test that shows the bug, or pins the new behaviour, and watch it fail for the right reason. Follow the testing rules in `CLAUDE.md`: prefer a guard-level test on hand-written lines, then a test through `parse` on a fixture already committed in `Fixtures`, then a `Corpus-backed:` test. Never commit RFC text, whether a new fixture, an excerpt of an existing one or an override snapshot.
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
- A wide legacy-parser change: `make corpus CORPUS_LIMIT=` before and after, then compare `corpus/report.json` between the two runs.

Then run `/code-review` on the branch's diff against `origin/main`, and fix what holds up.

## 7. Hand over

1. Push, and rewrite the pull request body in the repository's style (see recent merged pull requests): a `Why` section, a `What` section, and how it was verified, including what was *not* verified.
2. `gh pr ready`.
3. Leave the worktree with `ExitWorktree` using `keep`.
4. Report the pull request's URL, and any question left open.

## Never

- Merge a pull request, push to `main`, or force-push someone else's branch. The maintainer merges.
- Close an issue, or remove `agent-ready`. `Closes #N` closes the issue on merge.
- Commit unsigned. Every branch requires signed commits. If signing fails because Secretive is locked, sign that commit with the fallback key: `git -c gpg.format=openpgp -c user.signingkey=8F4ED9558B0722C0 commit …`.
- Widen the change beyond the issue. Anything else you notice goes in a marked comment, or in a new issue if it clearly deserves one.
