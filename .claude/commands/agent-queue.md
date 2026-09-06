---
description: Work the Iosis GitHub issue queue — advance every open issue whose last word was the dev's, until human input is needed
---

You are working the **Iosis issue queue**. Your job is to advance each issue that is **your turn** one step, then hand back. Repo: `Phaazoid/Godoiosis` (gh is authed). Work from `C:\Iosis\Godoiosis`.

## 1. Pull the queue — whose turn is DERIVED, and a CLAIMED issue is not yours

**The last thing said on an issue tells you whose turn it is.** Every comment Claude posts leads with `🤖 Claude says:` (see `CLAUDE.md`), so:

- Newest comment starts with `🤖 Claude says:` → **Claude spoke last** → waiting on the dev → **skip**.
- Newest comment is the dev's → **your turn**.
- **No comments at all** → apply the same test to the issue **body** (a ticket Claude filed is waiting on the dev; one the dev wrote is yours).

```
gh issue list --repo Phaazoid/Godoiosis --state open --limit 400 \
  --json number,title,body,comments,labels,milestone,assignees --jq '
  .[] | (if (.comments|length) > 0 then (.comments|last|.body) else .body end) as $last
  | select((($last // "") | startswith("🤖 Claude says:")) | not)
  | select([.assignees[].login] | all(. == "Phaazoid"))
  | "\(.number)\t\([.labels[].name]|map(select(startswith("priority/")))|join(","))\t\(.title)"'
```

**A CLAIMED issue is not yours — the `assignees` clause is the codev check (`CLAUDE.md`, dev rule 2026-09-06).** `c3potheds` works this tracker too, and **nothing in a comment thread reveals that somebody is mid-build on a ticket** — their work leaves no trace on the issue until they push — so a claim is the only signal that exists. `all` is **vacuously true on an empty array**, which yields exactly the three cases wanted: **unassigned → free**, **assigned to you → yours**, **assigned to anyone else → skipped**. That last case includes an issue assigned to you *and* someone else, deliberately: a second name means somebody joined, and that is a conversation rather than a race. The clause was verified against live GitHub data rather than asserted — a tracker with zero assignees cannot exercise the non-empty case at all, so it was run over `cli/cli` with the login swapped: 60 issues became 59, the issue assigned to the chosen login survived, and the one assigned to somebody else was the only thing dropped.

**Work `priority/P1-soon` first** — that is the demo backlog, and it is the one tier the dev has said he intends to finish.

> **Why derived and not a label (2026-08-25).** This used to select on an `agent/claude` / `agent/human` label pair, retired that day. Those labels were invented for the pre-2026-08-05 contract, where *"Claude owns the next step"* meant *"Claude drafts a walkthrough the dev types in"* — a distinction that stopped existing when Claude began writing the code. By the end they carried almost no information (80 `agent/human` to 5 `agent/claude`) and, worse, **they were wrong 24 times out of 85**: five issues Claude had already answered still read as its turn, and **nineteen the dev had replied to were still marked as waiting on him, so this command could not see them at all.** The comment thread already held the answer; the label was a hand-maintained copy that drifted (Law #4 — one question, one answer). The prefix convention is therefore **load-bearing, not decoration**: drop `🤖 Claude says:` from a comment and this command will hand that issue back to you forever.

If `$ARGUMENTS` names specific issue numbers, work only those. Otherwise work the whole queue, highest priority first: `priority/P0-blocking` → `priority/P1-soon` → `priority/P2-someday`.

## 2. For each issue, figure out the next step — from the REAL code, not theory

Read the issue body (`gh issue view N`), every `docs/design/*.md` it links, AND the actual source files it names. CLAUDE.md is law: ground everything in the codebase — reading files beats theorizing (theorizing has wasted turns before). Then pick one path:

You write the code now (contract changed 2026-08-05 — CLAUDE.md's collaboration section is law). But a queue run is **asynchronous**: the dev isn't here to iterate a plan with you mid-run, so anything that owes him a plan gets the plan *posted as the comment* and hands back rather than being built.

- **A new feature, or an invasive change to core gameplay** (action queue, attack/resolution, turn flow, squad lifecycle, plan validation, movement/reach): **post the plan, build nothing.** Format:
  - **Summary** — one-line restatement of the change.
  - **The seam** — the question this answers, what already answers it, and what you grepped to be sure (Law #4). For a core change, also every caller/reader of what you're touching, **counted from the code**, and what breaks.
  - **Approach** — files touched and what each change is.
  - **Verification** — the gdUnit4 cases to add, and whether this needs the game actually launched.
  - **Riskiest assumption** — what would make this plan wrong.
  - **Provenance** — what surfaced it / what you read to confirm.
- **Small bugfix that touches neither, or `tests/` / `docs/` / `CLAUDE.md` work**: just do it. Post a comment with what changed, why, and how you verified it — including what you did *not* check.
- **Blocked on a human decision / design fork**: post a comment stating exactly the decision needed and the options. Posting it *is* the hand-back — no label to set.

**Claim it the moment you decide to act — BEFORE building, not after.**

```
gh issue edit N --repo Phaazoid/Godoiosis --add-assignee @me
```

Only for issues you are actually advancing this run — never one you merely read and skipped, and never as a reservation over an umbrella's children you are not building (dev ruling, 2026-09-06; that over-claiming is what left the old `agent/*` labels carrying no information). The claim then **stays** through plan → build → review → merge, and is released only if the work is abandoned, re-scoped, or parked on something nobody is chasing.

Keep each issue to **one reviewable diff**, and don't leave the tree holding several issues' worth of unreviewed edits.

Honor the design laws — no randomness; the action queue never lies (preview == execution; derived actions are computed, not stored); future AI uses the player's `SquadManager.queue_action` API. Don't bake anything still fluid (elemental specifics, runes, final weapon numbers) into a "fix."

## 3. Post the comment — provenance is mandatory

Author the comment body with the **Write tool** (correct UTF-8), then:

```
gh issue comment N --repo Phaazoid/Godoiosis --body-file <file>
```

NEVER pass non-ASCII via an inline `-b "..."` / PowerShell here-string — PS 5.1 mojibakes it before upload (see the encoding memo / `powershell-gh-nonascii-encoding` memory). Every comment:
- **leads with** `🤖 Claude says:`
- **ends with** `— Claude (Opus 4.8) · <today's date>`

## 4. Hand back — and leave the claim alone

After acting on an issue: **nothing.** The comment you just posted is the hand-back — the selector in step 1 will skip that issue on the next run because your comment is now the newest one. When the dev replies (including "this needs rework"), it becomes yours again automatically.

**The claim from step 2 does NOT come off here.** An assignment says *this side owns this thread*, not *hands on it right now* (dev ruling, 2026-09-06). Dropping it at hand-back would advertise the issue as free for exactly as long as his answer is pending — which is precisely the window in which codev would pick it up, and the collision this whole convention exists to prevent.

The one thing you must not do is post a comment **without** the `🤖 Claude says:` lead — that would leave the issue looking like the dev spoke last, and you would pick it straight back up next run.

## 5. Stop and report

When every issue that was your turn has been advanced — or the rest genuinely need human input — stop and summarize per issue: what you did and what it's now waiting on. Do **not** close issues yourself unless explicitly asked. Verify any non-ASCII you posted via `gh api` (capturing gh stdout on the PS console re-mojibakes the display), not by eyeballing the terminal.

**Report the claims too, every run:**

```
gh issue list --repo Phaazoid/Godoiosis --state open --assignee @me
gh issue list --repo Phaazoid/Godoiosis --state open --assignee c3potheds
```

Give the first as *what this side is holding* and the second as *what was skipped as codev's*. **A claim left on work nobody is doing is the one way this convention rots** — the same drift that killed the `agent/*` labels — so the run that can create a stale claim is the run that has to show it. Anything in the first list you do not recognize is a claim to drop.
