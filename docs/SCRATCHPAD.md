# Scratchpad — Idea Inbox

A low-friction place to **dump ideas the moment they strike** — gameplay, story, code, UI, balance, anything. Don't organize, don't polish, don't worry about where it belongs. Add a bullet under **Inbox** and move on. Claude sweeps this on request and files each idea where it actually belongs (a design doc, a GitHub issue, or the defer pile), then logs where it went.

## How to use it (you)

- Add ideas as bullets under **📥 Inbox** below. One thought per bullet; grouping is fine. Any format — a phrase, a paragraph, a question.
- Optional, never required — prefix a line to steer the sweep:
  - `[DECIDED]` — treat as a firm decision; integrate as canon, not just a captured musing.
  - `[Q]` — a question for Claude to answer/research, not a design change.
  - an area hint like `(weapons)` / `(story)` / `(code)` / `(elemental)` if you already know where it points.
- When you want a sweep, say **"sweep the scratchpad"** (or just point me here). I'll also offer if I notice the Inbox has entries while we're working on something else.

## How Claude processes this — sweep procedure

> **Instructions to self.** Run when the user asks, or offer when you notice the **Inbox** is non-empty during other work. Ground everything in the repo and the design laws, same as `/agent-queue`.

For each bullet in **Inbox**, in order:

1. **Understand it.** If filing it wrong would be worse than asking, **ask the user** — don't guess at intent.
2. **Decide its home:**
   - A **`docs/design/*.md`** section (most ideas) — match to the right doc: `weapons`, `terrain`, `elemental-system` / `elemental-interactions`, `will-and-death`, `progression`, `squad-system`, `alchemy-kit`, `resolution-pipeline`, `philosophy`. Cross-reference if it spans two.
   - A **GitHub issue** — if it's actionable work (bug / feature / debt). **Propose it and get a yes before creating one** (and use the `agent/*` labels + provenance footer per `CLAUDE.md`). Don't spam the tracker.
   - **Defer** — record it in the relevant doc's *deferred / open* section (or `wiki-triage.md`) with the reason.
3. **Apply it — honoring the contract & laws:**
   - Docs are yours to edit directly. Mark each idea as a **captured / unsorted idea (not a locked decision)** unless it's tagged `[DECIDED]` or the user says so — match the "Captured ideas" convention already in `progression.md` / `alchemy-kit.md`.
   - **Gameplay code stays user-typed.** A code idea becomes a walkthrough or an issue — never a direct edit to `Classes/`, `Scenes/`, `game.gd`.
   - Don't bake **fluid** systems (runes, weapon specifics, elemental tuning) as locked; respect the certainty map and the three Laws.
   - `[Q]` items: answer/research, record the answer where useful (or just reply), then file like anything else.
4. **Log it.** Move the bullet from **Inbox** to **🗂 Dispersed** as a one-liner: `- <gist> → <destination> (YYYY-MM-DD)`. **Never silently delete a user's idea** — the log is the audit trail.
5. Leave the **Inbox empty** after a sweep. Anything you couldn't file without the user stays in the Inbox under a `**needs you:**` note.

Then report a short per-idea summary: where each went, and anything that needs the user. Commit doc changes (this file + the docs you filed into) the way the other docs work is committed.

---

## 📥 Inbox (drop ideas here)

<!-- Empty — swept 2026-06-17. Drop new ideas as bullets here, then run /scratchpad-sweep. -->

## 🗂 Dispersed (log)

- Revved Chainsword chews through Cover terrain over a turn → weapons.md (Captured ideas) + terrain.md ("Attack the map") (2026-06-17)
- Range-dependent damage / sweet-spot patterns (carbine harder at range, shotgun up close, Springspear AoE center tile) → weapons.md (Captured ideas); relates to issue #25 (2026-06-17)
- Fixed stats may force weapon pairings → mutable scaling via weapon mods/variants or sub-varieties → weapons.md (Captured ideas) + progression.md (2026-06-17)
