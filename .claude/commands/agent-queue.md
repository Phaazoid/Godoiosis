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

- **Gameplay code** (`Classes/`, `Scenes/`, `game.gd`): *the user types it.* Draft a **walkthrough** — do NOT edit those files yourself. Format:
  - **Summary** — one-line restatement of the fix.
  - **Where** — file + line anchors for every touch point.
  - **Fix** — the complete change as a `gdscript` block (typed end-to-end; the user pastes/types it verbatim).
  - **Test coverage** — the gdUnit4 case to add under `tests/` once it lands.
  - **Provenance** — what surfaced it / what you read to confirm.
- **`tests/`, `docs/`, `CLAUDE.md`, other non-gameplay scaffolding** (standing exception — you MAY edit these directly): just do the work, then post a comment summarizing what landed + the commit SHA.
- **Blocked on a human decision / design fork**: post a comment stating exactly the decision needed and the options, then leave it for the human (it becomes `agent/human`).

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
