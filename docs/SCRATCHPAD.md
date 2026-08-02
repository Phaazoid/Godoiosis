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

## 🗂 Dispersed (log)

- AI won't move when a downed unit blocks the closer attack position → **issue [#127](https://github.com/Phaazoid/Godoiosis/issues/127)** (filed as reported, deliberately un-investigated at your call; cross-refs #122 as unconfirmed overlap) (2026-08-02)
- Report-a-bug hotkey: dump the game state in-game for Claude to analyze → **issue [#128](https://github.com/Phaazoid/Godoiosis/issues/128)** (filed as requested; the what-goes-in-the-dump design is the open half) (2026-08-02)
- Make an attack's target kind legible (colour the pick-list text and/or the glowing tiles by unit/cell/both) → **[#44](https://github.com/Phaazoid/Godoiosis/issues/44) comment** (visual clarity umbrella; presentation on top of the existing `AttackData.targets` fork, colours unpicked) (2026-08-02)

- Downed enemy units should not block movement → **issue [#122](https://github.com/Phaazoid/Godoiosis/issues/122)** (measured the asymmetry: a downed *ally* is already walk-through-able since #103's ejection wire, a downed *enemy* is not, because `movement_cost` refuses on faction alone; "step over, don't stand on" falls out free from the `reachable` filter, and the shove question is left unpicked) + terrain.md occupancy doctrine (2026-07-31)
- Heal should be able to target self — Manhattan range 0, plus a target-self tag → **issue [#123](https://github.com/Phaazoid/Godoiosis/issues/123)** (`Heal.tres` *already* authors `min_range = 0`, so the cell is already selectable and already queueable — the only blocker is `RulesService.is_attack_victim` refusing `unit == attacker` before it reads the attack; `hits_self` extends the `hits_allies` axis rather than adding a seam) + squad-system.md victim rule (2026-07-31)
- An ability to act after counters, so a healer can heal a friendly who just took damage → jobs.md *Captured idea — reactive healing* (**one seam with the entry below**, deliberately written up together) + resolution-pipeline.md Deferred (a reaction stage past counters; R7 doesn't forbid it, and the heal branch already writes through the shared hypo) (2026-07-31)
- A defending squad's healer should heal teammates when you attack into it → jobs.md *Captured idea — reactive healing* (the **derived** half: same derive→show→replay shape as a counter) + squad-system.md C7 (flags the fork it owes: extend C1–C7, or be one of the separate named systems C7 reserves) (2026-07-31)
- Rescue an ally who goes down in the same pass (queue the attack and the pickup together) → **issue [#124](https://github.com/Phaazoid/Godoiosis/issues/124)** (execution already supports it — side channels run after counters, before ejection; all three blockers are plan-time, and `ResolvedOutcome.lethality` is the prediction it should read rather than a new one) + will-and-death.md rescue section (2026-07-31)

- *(logged retroactively 2026-07-31 — these two were cleared from the Inbox by the session that fixed them, before reaching this log)* Targeting allies is broken with the action queue, found via the heal action → tiered attack overlay (`OverlayManager.show_tiered_overlay` + `RulesService.cells_with_targets`: reach fill, with a distinct marker on cells that actually hold a victim) (2026-07-31)
- *(logged retroactively 2026-07-31)* A queued heal on a squadmate who then moves isn't cancelled — it sits in the queue targeting nothing → `SquadPlanValidator._revalidate_unit_attacks` + the re-validate-after-resolve hop in `game.refresh_action_queue`; recorded in squad-system.md *Known gaps* as the closing half of the AoE re-resolution entry (2026-07-31)

- Non-blunt elemental damage (fire, shock) ignores DEF; thrown earth/ice still blocked → elemental-system.md (Deferred layers — **captured, fork deliberately unpicked** at your call: per-element / elemental-damage-only / per-attack flag, plus the note that damage is one number with no physical-elemental split) + stats.md DEF cross-ref (2026-07-29)
- AI turns resolve too fast to follow — a pause between each action → **issue [#118](https://github.com/Phaazoid/Godoiosis/issues/118)** (sub-issue of #44; grounded in `OrderExecutor._execute_action_sequence`, with the test-suite constraint that the beat must be a zeroable tunable) + visual-clarity.md (2026-07-29)
- Battle log adapted from the action queue, scroll back through past turns → **issue [#119](https://github.com/Phaazoid/Godoiosis/issues/119)** (sub-issue of #44; carries the *share the widget, never the data source* rule + the two things a log must show that no queue row ever did — post-BREAK reality and the non-order events) + visual-clarity.md (2026-07-29)
- Shove into water: shallow (high move cost) vs deep (drown clock with a rescue window) → **[#116](https://github.com/Phaazoid/Godoiosis/issues/116) comment** (the fork it had parked, now with a candidate) + terrain.md *Water — shallow vs deep* (captured; flags that `Unit.downed_turns_remaining` + `RescueAction` may already BE the drown clock) (2026-07-29)
- Weight means something: push tiers gate what a shove can move, weight sets knockback distance, heavy-slow vs light-shovable → **issue [#120](https://github.com/Phaazoid/Godoiosis/issues/120)** (the first concrete answer to CLAUDE.md's wire-it-or-cut-it) + stats.md Weight & Open forks (incl. the STR-anchors-shoves collision) + CLAUDE.md debt entry (2026-07-29)

- Scenario dev tab: Save As / Update / Load as three separated verbs (no retyping a saved scenario's name to overwrite it) → **issue #99** (spec + full walkthrough; Update targets the dropdown selection, not `last_loaded_path`) (2026-07-28)
- Kinetic Mace: using Blowback disables main attacks → **issue #102** (root-caused: `can_fire_default_attack()` reads the live `active_attack`, not the default — a fired Blowback leaves a stale unfireable pick that removes Attack *and* Weapon Action for the rest of the battle) (2026-07-28)
- Castle Assault played itself into a broken state (both player squads AI/Rushdown, enemy AI/Hold, one enemy left) → **issue #103** (root-caused: `execute_orders`'s invalid-plan guard is a player-only affordance — it returns before clearing the queue, the projection ghosts and `has_acted`, and the AI can't see the red flash, so the turn loops forever) (2026-07-28)
- Limb-loss selection by facing / angle of attack and by physical damage type (bludgeoning vs stabbing vs slicing) → **[#77](https://github.com/Phaazoid/Godoiosis/issues/77) comment** (added to the selector roster) + will-and-death.md limb-slot model (captured idea; facing is cheap and reuses the backstrike seam, damage type needs a new content axis first) (2026-07-28)

- MMBN3 NaviCust-style shaped mod fitting (sized squares + tetris-block mods) → weapons.md (Captured ideas — flagged as revising the ratified #59 capacity model, grill first) (2026-07-23)
- Transmutation strain as a job-granted ability ("blood transmutation") rather than universal → transmutation-model-proposal.md (captured; decision point = #76's access-rules playtest) + job-ideas.md §C (Blood Transmuter sketch) (2026-07-23)
- Family uniqueness pass (every family ≥1 archetype-unique mechanic; carbine magazine reload; chem-spitter materia cone + element-locked prototypes; family-locked mods confirmed already the norm) → **issue #84** (the "one big issue", per your note) + weapons.md (Captured ideas + the Open list) (2026-07-23)

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
