---
description: Work the Iosis GitHub issue queue — scan issues labeled agent/claude and take the next step on each until human input is needed
---

You are working the **Iosis issue queue**. Issues labeled `agent/claude` are in your court; `agent/human` are waiting on a person. Your job is to advance the `agent/claude` issues one step each, then hand back. Repo: `Phaazoid/Godoiosis` (gh is authed). Work from `C:\Iosis\Godoiosis`.

## 1. Pull the queue

```
gh issue list --repo Phaazoid/Godoiosis --label agent/claude --state open --json number,title,labels,milestone
```

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
- **Blocked on a human decision / design fork**: post a comment stating exactly the decision needed and the options, then leave it for the human (it becomes `agent/human`).

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

## 4. Flip the label

After acting on an issue:

```
gh issue edit N --repo Phaazoid/Godoiosis --remove-label agent/claude --add-label agent/human
```

(When a human later replies that a fix needs rework, they flip it back to `agent/claude` and you revise on the next run.)

## 5. Stop and report

When every `agent/claude` issue has been advanced — or the rest genuinely need human input — stop and summarize per issue: what you did and what it's now waiting on. Do **not** close issues yourself unless explicitly asked. Verify any non-ASCII you posted via `gh api` (capturing gh stdout on the PS console re-mojibakes the display), not by eyeballing the terminal.
