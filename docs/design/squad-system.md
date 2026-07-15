# Squad System — Locked Specification

**Status: SETTLED — with one deliberate redesign pending (2026-06-20): LDR's meaning.** Changes to anything below should be deliberate design decisions, not implementation drift. (Drafted 2026-06-12 by Claude from the implemented system; pending user sign-off.)

> **Design update — 2026-06-20 ([stats.md](stats.md)).** LDR is being repurposed from *squad range* to a **squad-capacity budget**: squad **size** = budget − per-member costs, and costs drop with **relationship/familiarity** (which also grows combat synergy). **Squad range is decoupled from LDR** → a **static default**, to be tuned in playtest. The invariants below still describe the *current code* (LDR-as-Manhattan-range); the flagged ones — **I5, I6, V3** — change when this lands. This is the deliberate decision the SETTLED status invites, not drift.
>
> **Numbers RATIFIED 2026-07-14** (dev + Claude, validated against the authored roster — avg squad ~2.7, spread loner→four): capacity = leader + `floor(effective LDR / MEMBER_LDR_COST)` members with **`MEMBER_LDR_COST = 2`** (rungs: eLDR 0–1 loner · 2–3 pair · 4–5 trio [the default statline] · 6–7 four · 8–9 five · 10–11 six); range = **`SQUAD_RANGE = 3`**, static Manhattan. Both are playtest-tunable named constants; effective LDR = base + PER band (built in #55). Enforcement is join-time only (existing scenario squads grandfathered, warn on overfull load); leader-death overflow detaches newest-members-first (deterministic, Law #1). Budget-not-cap framing is deliberate: familiarity later discounts per-member cost; jobs mint big-LDR exception captains. Build: [#63](https://github.com/Phaazoid/Godoiosis/issues/63).

## Purpose

Squads are Iosis's distinctive mechanic. Units group under a leader, plan together, execute together, and defend each other. Squad-vs-squad combat is the intended heart of the game; lone units are vulnerable by design.

## Entities

- **Unit** — a board piece. Holds a reference to its current squad. Never manages squad membership itself.
- **Squad** — a leader + members + an `action_queue` of player-authored orders. Manages only its own lists.
- **SquadManager** — the sole authority for squad lifecycle and the home of derived-action (counter) resolution.

## Invariants

Numbered for test coverage. Violating any of these is a bug, full stop.

- **I1.** Every unit on the board belongs to exactly one managed squad at all times. A solo unit is a 1-member squad, not squadless.
- **I2.** Only `SquadManager` creates or destroys squads. All member removal funnels through `Squad._erase_member()` — the sole caller of `members.erase()` (mirrors the sole adder `_add_member`). Its callers: `_detach_from_current_squad()` (single-unit — join/leave/death) and `disband_squad()` (bulk teardown). (Chokepoint added 2026-06-21, [#23](https://github.com/Phaazoid/Godoiosis/issues/23).)
- **I3.** Every live squad appears in `SquadManager.squads`; destroyed squads are removed from it and freed. No "ghost squads" holding units.
- **I4.** `Unit.has_squad()` answers "does this unit have squadmates" (`members.size() > 1`) — not "does a squad object exist" (that's always true, per I1).
- **I5.** The leader is always a member of their own squad. When the leader leaves/dies, leadership reassigns to the member with the highest LDR stat (first-in-member-order breaks ties). **[→ 2026-06-20: LDR now = squad-capacity budget; "highest LDR leads" still holds (biggest capacity commands) — see banner.]**
- **I6.** Members must stand within the leader's LDR range (Manhattan). After leader reassignment, out-of-range members are detached into solo squads (`check_reassign_leader`). **[→ 2026-06-20: range becomes a static default, not LDR-derived — see banner.]**
- **I7.** Spawning a unit creates its solo squad (`spawn_unit` → `create_squad`).

## Action queue rules

- The queue contains **player-authored orders only**. Derived actions (counters) are never stored in it (see Counter rules).
- **One order per action-type per unit.** Queuing a new move/attack for a unit replaces its previous one — *except* volley siblings (one AoE order = several `AttackAction`s sharing a `volley` array; `_is_volley_sibling` exempts them from replacement; a *new* attack order still sweeps the entire old volley).
- Members without an explicit move get a **hold move** (`init_hold_position`) when the squad becomes active, so every member has a stance in the plan.
- Cancelling all of a unit's actions must leave no residue: if only hold moves remain in the squad's queue afterward, the queue clears entirely and the squad deactivates.

## Validation rules (`validate_squad_plan`)

Run on every queue change; actions carry `is_valid` + error strings rather than being rejected:

- **V1.** Two units may not plan moves to the same destination.
- **V2.** A move may not target a cell occupied by a squadmate who isn't moving away.
- **V3.** Non-leader moves must land inside the leader's *projected* LDR range (the leader's own planned destination counts, not their current cell). **[→ 2026-06-20: range becomes a static default, not LDR-derived — see banner.]**

## Counter-attack rules

Counters are **derived**: recomputed from the current plan whenever it changes, displayed in the queue indented under the attack that provokes them, and instantiated only at execution.

- **C1.** When party X attacks party Y, every unit in Y gets the opportunity to counter **once per plan**. A "party" is the whole squad (a lone unit is a party of one).
- **C2.** A countering unit may target *any* unit in the attacking party that it can reach — not just the unit that attacked. (The sacrificial-frontliner rule: a long-range attacker exposes nearby squadmates to the response.)
- **C3.** Target choice is deterministic. Current policy: first valid target in attacking-party member order. **[OPEN — placeholder policy. Candidates: closest, lowest HP, leader-first. Lives in `choose_counter_target`; changing it touches nothing else. 2026-07-06: taunt/bodyguard **job abilities override** whatever the default is ([jobs.md](jobs.md) squad posture); the default itself stays a feel-test placeholder.]**
- **C4.** A defending party responds at most once per attacking squad's plan, triggered by the first attack against it in queue order.
- **C5.** Faction gate: `can_attack` (via `Team.is_enemy`) filters counters — friendly-fire victims never counter their own side.
- **C6.** Weaponless units cannot counter. A unit's counter reach is its weapon pattern from its *projected* position, with free rotation (no facing persistence on the board — revisit if facing becomes a mechanic).
- **C7.** Bystander parties never counter: only the attacked party responds, and only against the attacking party. Reaction mechanics beyond that (overwatch, intercepts) would be separate named systems.

## Execution model

1. **Moves** — all squad moves execute in parallel (the squad repositions as one).
2. **Attacks** — sequentially, in queued order. Order matters by design (future elemental combos: wet *then* shock).
3. **Counters** — sequentially, after the full attack chain. Counters never interrupt the combo.
4. Counter actions are computed **before** any phase executes (determinism: the plan decides, not mid-execution board state). Dead actors/targets cause individual actions to no-op safely; they never hang the phase (every `execute()` path must reach `finish_execution()`).

## AoE / volley semantics

- One AoE order resolves at queue time into one `AttackAction` per victim ("volley"), all sharing the `volley` array; the first is primary (plays the lunge), the rest are `is_secondary_hit`.
- Victims are gathered by **projected destination** over the pattern's affected cells: enemies always; non-enemies only when the weapon's `hits_allies` is true; never the attacker itself.
- Counters key off each victim-action individually, so C1–C7 apply unchanged to AoE.

## Display model

The queue UI renders `ActionQueueDisplayEntry` lists built by `SquadManager.get_display_entries_for_squad` — never raw queues. Sections per action type, counters indented under their provoking attack. Display rebuild happens on every plan change; the UI must tolerate freed units (actions cache display name/texture at init).

## Known gaps / future work

- **LDR redesign (2026-06-20) — numbers RATIFIED 2026-07-14, build queued as [#63](https://github.com/Phaazoid/Godoiosis/issues/63):** `MEMBER_LDR_COST = 2` capacity budget + static `SQUAD_RANGE = 3` (see banner). Until #63 lands, squad **range** still reads the leader's *effective* LDR (the `Squad.gd` getter, rerouted through the PER band in #55) and **size** is unenforced. Per-member familiarity costs remain the future discount lever; combat synergy + cost-reduction ride on familiarity, not LDR. Touches I5/I6 and V3.
- AoE victim lists don't re-resolve when moves are re-planned after the volley is queued (fix belongs in `validate_squad_plan`).
- ~~Death handling undesigned~~ — **superseded by the #33 lifecycle build (2026-06-21→25):** a would-be-fatal hit now downs (`Unit.LifecycleState`), squad ejection defers to after the resolution pass (`game._downed_pending`), counters skip mid-pass-downed actors, and rescue/countdown govern the aftermath — see [will-and-death.md](will-and-death.md) *Implementation status*. Still open squad-side: leader-down feel (leadership reassigns via I5) and squad tactics *around* downed allies (defend-the-body play).
- `choose_counter_target` policy (C3) is a placeholder awaiting feel-testing.
- Squad-formation UX rules (who may join whom, range checks at join time) live partly in `game.gd` (`can_join_squad`, `can_squad_up`) — candidates to migrate into `SquadManager`.
- **Squad archetypes by leader specialization** (idea, undesigned): a leader's dominant stat could shape the squad's identity — e.g. a high-CON leader yields a defensive squad (holds ground, blocks for members; *example updated 2026-07-07 — DEF is gear-only, never a unit stat; CON is the defensive input since the 2026-07-06 adoption, [stats.md](stats.md)*). Largely overtaken by **leader-posture jobs** ([jobs.md](jobs.md)) — fold there if pursued. Captured from the wiki scratchpad during the #32 triage.
