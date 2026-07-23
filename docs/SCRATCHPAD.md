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

For weapon modifications - different weapon modification slots are different sized squares, similar to the navi customization system in megaman battle network 3, and different mods are like different shaped tetris blocks we can try and fit in

Transmutation strain could be something a unit is granted by an ability through a job (blood transmuation or something) rather than a universal transmuation feature

Each weapon should have at least one thing to make their archetype unique... Springspears already have the secondary attack/reload mechanic.  Chainswords should do something with revving.  Kinetic maces should do something with enemy unit displacement.  Drills should do something with creating cover/defensible terrain.  Prosthetics are already unique with stat replacement.  Perhaps carbines will need to reload as well, but for their main attack, and after a certain number of attacks rather than just one?  This will be something that can be changed up through mods, I imagine.  (oh yeah, in case this isn't part of the system yet, there are definitely going to be lots of weapon mods that will only work on specific weapon families)  And the chemical spitters... they still need some workshopping.  Perhaps the generic one can be filled with materia to output elemental aoe damage in a cone, but prototypes are more efficient with a specific element and can't use others.  We'll see.  This should all be one big issue.  

## 🗂 Dispersed (log)

- Revved Chainsword chews through Cover terrain over a turn → weapons.md (Captured ideas) + terrain.md ("Attack the map") (2026-06-17)
- Range-dependent damage / sweet-spot patterns (carbine harder at range, shotgun up close, Springspear AoE center tile) → weapons.md (Captured ideas); relates to issue #25 (2026-06-17)
- Fixed stats may force weapon pairings → mutable scaling via weapon mods/variants or sub-varieties → weapons.md (Captured ideas) + progression.md (2026-06-17)
- Volley attacks grouped into one expandable action-queue row → #49 Action Queue UX (graduated from #44) (2026-06-26)
- Highlighted units should flash (like the Execute button) rather than just glow → #44 (shares the flash-for-attention motif with #1) (2026-06-26)
- Hovering/selecting a counter in the queue shows the countering enemy's attack range → #44 (extends the on-hover enemy-range item) (2026-06-26)
- Click-drag to reorder attacks in the action queue → #49 Action Queue UX (2026-06-26)
- More action-queue info per row: damage on hit + target HP before→after (`ResolvedOutcome.target_hp_after` already threaded) → #49 Action Queue UX (2026-06-26)
- Will generation via aura/temperament; out-of-battle Will falls out of ordinary task-assignment (no dedicated Will-farm task) → will-and-death.md Generation (captured idea) + xref alchemy-kit.md / progression.md (2026-06-26)
- Playtest: persist every rendered board frame + give Claude inspect parity with the in-game player (stats, move range, squad, elemental state) → #46 Play API (2026-06-26)
- Real HP/Will bars (and later LDR) instead of text readouts → #44 (2026-06-26)
- CON as a 4th, defensive scaling stat (scales gear/weapon defensive bonuses) → stats.md "Cut: CON" reconsideration — **REOPENS a decided cut**, needs a stats-session/co-dev decision (2026-06-26)
- Action queue needs an outer scrollbox — the *list of action-type sections* can overflow, not just each section → #49 Action Queue UX (2026-06-26)
- Player-built transmutations (creation system) + the rune balance axes → **outdated on arrival** (dev: written pre-2026-07-04-grill; the sigil/flourish model already delivers it) — capture withdrawn; issue #52 **repurposed** → manual rune carving (players draw the carving themselves, dev + co-dev long-wanted) → transmutation-model-proposal.md (Far future) + grill-queue.md Parked 15 (2026-07-08)
- Hover an action-menu option → highlight its potential targets on the map → #44 comment (board-legibility umbrella) (2026-07-08)
- Rebecca reveal: flip the academy test order — hidden alkahest point zeroed by the raid's limb tax; the Isaac pre-training-maim seam flagged → story open-questions.md **Q9** + 🔴 flags in rebecca.md / isaac.md (2026-07-08)
