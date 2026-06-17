---
description: Sweep the Iosis idea inbox — read docs/SCRATCHPAD.md, file each Inbox idea where it belongs (a design doc, a proposed issue, or the defer pile), log it, and leave the Inbox empty
---

You are **sweeping the scratchpad** — the user's raw idea inbox at `docs/SCRATCHPAD.md`. Work from `C:\Iosis\Godoiosis`.

## 1. Read the inbox and the procedure

Read **`docs/SCRATCHPAD.md`** in full. It contains both the current **📥 Inbox** entries and the authoritative **sweep procedure** (the numbered steps under "How Claude processes this"). That doc is the source of truth — follow its steps exactly; the rest of this file just restates the guardrails so they aren't missed.

If the Inbox is empty, say so and stop — nothing to sweep.

If `$ARGUMENTS` is given, treat it as a scope hint (a specific idea, or an area like `weapons` / `story`) and sweep only matching entries; otherwise sweep the whole Inbox, top to bottom.

## 2. For each idea, file it — grounded in the repo, not theory

Same rigor as `/agent-queue`: read the design docs and real source an idea touches before deciding where it goes. For each bullet:

1. **Understand it.** If filing it wrong would be worse than asking, **ask the user** — don't guess at intent.
2. **Pick its home:** a `docs/design/*.md` section (most ideas), a **proposed** GitHub issue (actionable work — propose and get a yes *before* creating; never spam the tracker), or the **defer pile** (record in the relevant doc's open/deferred section or `wiki-triage.md` with the reason).
3. **Apply it, honoring the contract & laws:**
   - Docs are yours to edit directly. Mark each idea as a **captured idea, not a locked decision** — match the "Captured ideas" convention in `progression.md` / `alchemy-kit.md` — *unless* it's tagged `[DECIDED]` or the user says otherwise.
   - **Gameplay code stays user-typed.** A code idea becomes a walkthrough or an issue — never a direct edit to `Classes/`, `Scenes/`, `game.gd`.
   - Don't bake **fluid** systems (runes, weapon specifics, elemental tuning) as locked; respect the certainty map and the three Laws (no randomness; queue never lies; AI uses the player API).
   - `[Q]` items: answer/research, record the answer where useful, then file like anything else.
4. **Log it.** Move the bullet from **📥 Inbox** to **🗂 Dispersed** as `- <gist> → <destination> (YYYY-MM-DD)`. **Never silently delete a user's idea** — the log is the audit trail.

Leave the **Inbox empty** when done. Anything you genuinely can't file without the user stays in the Inbox under a `**needs you:**` note.

## 3. Provenance (only if you create or comment on an issue)

If an idea becomes a GitHub issue or a comment, follow the `/agent-queue` rules: author the body with the **Write tool** (UTF-8), post via `gh ... --body-file` (never an inline non-ASCII arg — PS 5.1 mojibakes it), lead with `🤖 Claude says:`, end with `— Claude (Opus 4.8) · <today's date>`, and set the `agent/*` labels. Editing `docs/` needs none of this.

## 4. Commit and report

Commit the touched docs (this file plus any design docs you filed into) the way the repo's other docs are committed — branch off `main`, push, open a PR for the user to merge; don't commit straight to `main`. Then report a short **per-idea** summary: where each idea went, and anything still waiting on the user.
