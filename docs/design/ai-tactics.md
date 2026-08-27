# AI Tactics — the archetype layer's integration contract

**Canon checked through #151 (2026-08-06).**

**Status: BUILT 2026-07-22, #78 CLOSED 2026-07-23 (commit `239555b`)** — ratified and hand-typed the same day; full suite 444/444 green. Feel iteration continues through ordinary playtesting (the v1 approximations below are the watch-list). The #29-era archetype layer (Rushdown/Hold/Sentry, painted zones, Crisis stances — see CLAUDE.md's architecture map) is the substrate; this doc covers the #78 rebuild of *how the AI decides*, and the standing contract that keeps it from rotting again. *(2026-08-09: the Crisis-stance piece of that substrate is GONE — [#158](https://github.com/Phaazoid/Godoiosis/issues/158) made Crisis a deterministic equipped ability, deleting `CRISIS_STANCES`/`accepts_crisis` with the accept/decline question they answered; enemy Crisis access is authored content now.)*

## The doctrine: the AI is a player, all the way down

Law #3 ("AI issues orders exclusively through `SquadManager.queue_action`") was necessary but not sufficient — the fists bug (#78) happened because the AI queued through the right chokepoint while *skipping steps of the player's declare flow* (the `fired_attack` stamp). The rebuilt doctrine closes that class of bug:

- **Pick** — the AI selects among `Unit.get_selectable_attacks()`, then writes the winner to `Unit.active_attack` immediately before `declare()` stamps it, the same slot the player's pick menu writes. **Scoring itself no longer touches that slot (#102):** each candidate is passed directly to the reach/victim/splash queries, which take the attack as a parameter. Probe and declare can't disagree because they name the same object, not because they share mutable state — the old arrangement left a live pick behind that skewed every later read.
- **Declare** — both the player's click handler and the AI build attacks through `AttackAction.declare()`, the one factory that stamps `fired_attack` (Law #2's declare-time snapshot). Bare `create()` is for derived actions only.
- **Queue** — `queue_action` + `actor_can_perform()` stay the backstop behind every builder's own gate.
- **Forecast** — candidate scoring runs `PlanResolver.resolve()` on a throwaway volley. The resolver is a pure pass (R2), so this is free of side effects and *cannot drift*: the AI evaluates a candidate with exactly the math the queue panel previews, lethality included.

**Consequence for future work:** anything that changes what a unit can fire or what a hit does (new families, carvings, mod effects, readiness economies, #76's strain gate, elemental changes) reaches the AI with **zero AI-side wiring**. If a feature lands player-side and the AI can't see it, the feature bypassed the player surface — fix the feature, not the AI.

## The policy registry (the one place per-archetype behavior lives)

`AIArchetype` declares, per archetype (the idiom the now-deleted `CRISIS_STANCES` table also used, until #158):

- `MAIN_ACTION_PRIORITY` — an ordered try-list over `BaseAction.MAIN_ACTION_TYPES`; `AITactics.queue_main_action` walks it and the first type that yields a buildable candidate wins.
- `MAIN_ACTION_NEVER` — the explicit opt-outs.

Every main action type must land in exactly one of the two, for every archetype — pinned by `tests/law/test_ai_action_coverage.gd`. **A new verb cannot silently skip the AI**: the suite stays red until a stance is declared, even if that stance is NEVER. This is the action registry's AI column, mirroring how `test_action_registry.gd` pins the pipeline.

Candidate builders live in `AITactics` (one per type, each mirroring `MainActionMenu`'s gate for that verb); an undeclared builder is a loud `push_error`, never a silent skip.

### Ratified tables (dev calls, 2026-07-22; REV column added 2026-08-06)

| | ATTACK | RESCUE | RELOAD | INTIMIDATE | RALLY | REV |
|---|---|---|---|---|---|---|
| **Rushdown** | 1 | never | 2 | never | never | 3 |
| **Hold** | 1 | 2 | 3 | 4 | never | never |
| **Sentry** | 1 | 2 | 3 | 4 | never | never |

- Intimidation/rescue on Hold+Sentry only — defenders recover their own and menace what they can't hit; Rushdown stays pure aggression.
- Rescue before Reload: a returned unit now beats rearming for later. (The verb was `SPRING_LOAD` when these tables were ratified; it went generic as `RELOAD` in #84 when the Carbine wanted the same order — same slot, same priority, one more family using it.) Intimidate last: menace only when nothing better exists.
- RALLY is NEVER everywhere for now: early rallies burn the strong falloff steps (6/4/2…) while idling. Revisit with real Will-awareness — this is a deliberately parked knob, not an oversight.
- **REV is Rushdown-only, added 2026-08-06 (AI generalization sweep, finding #3).** It had been
  `NEVER` for every archetype with no builder at all (unreachable even if declared — the
  `queue_main_action` match had no arm for it). `AITactics._try_rev` now mirrors `_try_reload`
  exactly (`Unit.can_rev_weapon()`/`rev_weapon()`, same shape as the reload pair), and Rushdown
  tries it last, after ATTACK and RELOAD. Hold/Sentry keep REV `NEVER` — undecided for them, not
  ruled out.

## Shared engage plumbing

`AITactics.engage(squad, target, board, squad_manager, allowed = null)` is the one place "fight
this target" is defined: destination pick (`best_attack_destination`) → conditional group move
→ every member tries a main action. Rushdown's whole turn and Sentry's intruder branch both call
it. It had been hand-duplicated between the two files since #29 — flagged by the #127 handoff
(2026-08-06) as the shape that let that fix's destination-picker half reach both archetypes for
free, since it landed one layer down in `AITactics` rather than in either archetype file;
extracted the same day.

The per-member "everybody tries a main action" step is itself `AITactics.queue_main_actions_for_squad(squad, board, squad_manager)`
— `engage()`'s tail, the whole of `HoldArchetype`'s turn, and (since finding #3, same day)
Rushdown's own no-enemy branch, which used to `return` above it and skip fallback main actions
(Reload/Rev) entirely whenever the squad's own `nearest_enemy` search found nothing on the whole
board. `HoldArchetype` never moves, so it has no destination/move step, only this one.

## Attack scoring (ratified, flagged evolvable)

Per candidate `(attack, aim cell)`: resolve the throwaway volley, then score `(net removals, net damage)`, compared lexicographically; a candidate must beat `(0,0)` to queue.

- Active enemies count **for** (damage; +1 removal on a predicted DOWN/MAIM/KILL).
- Any ally in the volley counts **against**, symmetrically — friendly fire is a soft penalty, not a ban (net-damage doctrine).
- Downed enemies count nothing in pass 1; a second pass counts (and aims at) them only when pass 1 yields no candidate — #57's deprioritization, preserved exactly.
- CRISIS predictions count as nothing: the target stands back up surged, so triggering it is neither prize nor penalty.
- Ties: first candidate wins, iterating attacks in `get_selectable_attacks()` order (main/carve order first) then units in board order — deterministic, Law #1.
- No selectable attacks (unarmed, or an aura-dry rune) → a null pick probes the bare-fist Manhattan-1 / STR fallback, matching what the player gets in the same state.

**Dev rider (2026-07-22): this scoring rule is open to change as more AI kinds arrive.** It is deliberately one function (`AITactics._score_volley`) so a future archetype-flavored scorer swaps in one place.

Target-state awareness ships "minimal": lethality tiers (via the resolver's own prediction) + two builder tie-breaks — intimidate the lowest-Will adjacent enemy (maim-cliff pressure, skipping Will 0), rescue the most urgent downed clock. Deeper state reasoning (limb loss, counter-risk terms, Crisis avoidance/exploitation) is future scoring-term work, and the seam for it is `_score_volley`.

## Known v1 approximations (accepted at ratification)

- **Destination planning reads the default pick** — `best_attack_destination` hoists one `leader.get_fired_attack()` and evaluates every cell against it, rather than per-candidate-attack. Cells × attacks × enemies was judged not worth it yet.
  - Corrected 2026-08-06 by [#127](https://github.com/Phaazoid/Godoiosis/issues/127), which is worth knowing because the failure was *silent and permanent*: the approach ranked candidate cells by hops toward **the enemy's own square**, and `path_hops` is deliberately occupancy-blind, so a downed body parked on the one adjacent firing cell in a corridor read as the shortest way in. The unit walked up to the corpse and stopped — every turn, forever, because a dead end is stable. Two halves were both required, and each was falsified alone: the route now targets the nearest **standable** firing cell (`_nearest_standable_attack_cell`), *and* the ranking walk opts into occupancy (`path_hops(…, block_on_occupancy = true)`) so it stops imagining it can cut straight through the bodies in the way. Retargeting alone still stalled. The generalizable shape: **when a metric and the thing it measures disagree about what is passable, fixing the target does not fix the measure.** Note the two halves have **different scopes**, which is the part worth copying: the retarget is attack-specific (a firing position is not the target's own square), but the honest metric is not — it is unconditional in `_best_approach`, so **Sentry's walk home got the same fix**. Scoping it to the attack case would have meant gating it on the retarget parameter, i.e. one flag answering two unrelated questions, and `closest_reachable_cell_to` could never have reached it. A sentry stalls identically against an enemy holding a corridor; pinned by `test_walking_home_routes_around_a_body_holding_the_corridor`.
  - **Target selection was then brought onto the same metric (same day, same sweep).** Fixing the approach alone left `nearest_enemy` measuring occupancy-*blind* while the approach measured aware — two answers to "how far is that enemy", so the AI could pick a target it would only then discover was the long way round. Both now measure to a **standable firing cell** rather than the target's own square, via one shared `_standable_attack_cells`. Note the detail that makes it possible at all: an active enemy blocks passage, so an occupancy-aware walk *to enemy squares* scores every enemy UNREACHABLE — routing to firing cells is what lets target selection use the honest metric. Still one BFS for all enemies (the `until` set is the union). Pinned by `test_nearest_enemy_measures_to_a_firing_position_not_to_the_target_itself`, and **the whole rest of the suite passes with the old metric restored** — which is why this went unnoticed.
- **Counters aren't scored** — the throwaway plan resolves the AI's own volley only; walking into counter range costs nothing in the score.
- **Movement never seeks rescue/intimidate targets** — fallback verbs fire from wherever attack-driven movement landed the unit.
- **Squad-level coordination** — members choose independently in member order; no focus-fire or combined-arms reasoning.
- **Movement is a group move, not per-unit destinations** — both moving archetypes call `queue_group_move`, so a member's destination is "preserve your path-offset from the leader" rather than anything tactical. Measured 2026-07-29 while fixing [#103](https://github.com/Phaazoid/Godoiosis/issues/103): this is **not** why the AI authored illegal plans (a single individual leader move produces the identical refusal — the invalid order is the hold-position filler `game.gd` gives every member, and the binding rule is `SquadPlanValidator._check_leader_range`, which applies to any plan from any author). But `GroupMoveSolver` is currently the AI's *only* cohesion solver, so this cannot simply be deleted. The replacement needs no new solver — `RulesService.compute_move_range` already leashes a non-leader to the leader's *projected* destination, so queueing the leader first makes each member's own range cohesion-clamped — what it needs is a decision about each archetype's per-unit movement taste. Tracked on [#117](https://github.com/Phaazoid/Godoiosis/issues/117).

**The standing home for all of the above is [#117](https://github.com/Phaazoid/Godoiosis/issues/117)** (evergreen), added 2026-07-29 on the premise that the AI is permanently behind the feature set: every system we add creates AI work that lands after the system ships. New approximations go there as well as here — here for the doctrine, there for the queue.

## Not this layer

The Balanced archetype (#29 leftover), strain's fate (#76 — its AI integration is already free by construction), the ability-chassis content itself (#61, closed).

**Win/loss detection is no longer a leftover** — it landed 2026-07-28 as #96 and lives outside this layer, in `MissionRules`/`MissionController` ([missions.md](missions.md)). The AI has two points of contact:

- **A guard.** `AIController.take_faction_turn` stops issuing orders the moment the mission is over, so a squad that wipes the player mid-turn doesn't keep playing behind the end-of-mission card.
- **`CAPTURE` is `MAIN_ACTION_NEVER` on all three archetypes**, forced to be an explicit decision by `tests/law/test_ai_action_coverage.gd`'s partition. **This one is not drift.** Rev and Burrow are `NEVER` because nobody has written a scored builder yet; `CAPTURE` is `NEVER` because there is nothing for an AI faction to *win* by capturing — enemy objectives are out of #96's scope, and the point belongs to the player. The AI contests it positionally with what it already has: Rushdown walks into the approach, and a Sentry squad zoned over the point defends it with no AI code at all. Revisit when non-player factions get objectives of their own — which is exactly [#571](https://github.com/Phaazoid/Godoiosis/issues/571), *defend a point* (split out of #101 when that closed), and the first thing that will need a real capture builder.
