# AI Tactics — the archetype layer's integration contract

**Canon checked through #711 (2026-09-03).**

**Status: BUILT 2026-07-22, #78 CLOSED 2026-07-23 (commit `239555b`)** — ratified and hand-typed the same day; full suite 444/444 green. Feel iteration continues through ordinary playtesting (the v1 approximations below are the watch-list). The #29-era archetype layer (Rushdown/Hold/Sentry, painted zones, Crisis stances — see CLAUDE.md's architecture map) is the substrate; this doc covers the #78 rebuild of *how the AI decides*, and the standing contract that keeps it from rotting again. *(2026-08-09: the Crisis-stance piece of that substrate is GONE — [#158](https://github.com/Phaazoid/Godoiosis/issues/158) made Crisis a deterministic equipped ability, deleting `CRISIS_STANCES`/`accepts_crisis` with the accept/decline question they answered; enemy Crisis access is authored content now.)*

## The doctrine: the AI is a player, all the way down

Law #3 ("AI issues orders exclusively through `SquadManager.queue_action`") was necessary but not sufficient — the fists bug (#78) happened because the AI queued through the right chokepoint while *skipping steps of the player's declare flow* (the `fired_attack` stamp). The rebuilt doctrine closes that class of bug:

- **Pick** — the AI selects among `Unit.get_selectable_attacks()`, then writes the winner to `Unit.active_attack` immediately before `declare()` stamps it, the same slot the player's pick menu writes. **Scoring itself no longer touches that slot (#102):** each candidate is passed directly to the reach/victim/splash queries, which take the attack as a parameter. Probe and declare can't disagree because they name the same object, not because they share mutable state — the old arrangement left a live pick behind that skewed every later read.
- **Declare** — both the player's click handler and the AI build attacks through `AttackAction.declare()`, the one factory that stamps `fired_attack` (Law #2's declare-time snapshot). Bare `create()` is for derived actions only.
- **Queue** — `queue_action` + `actor_can_perform()` stay the backstop behind every builder's own gate.
- **Forecast** — candidate scoring resolves the squad's own plan with the candidate added, through `SquadManager.resolve_hypothetical` (#117; it was `PlanResolver.resolve()` on a throwaway volley until 2026-09-02). Same machinery the queue panel previews, so the AI *cannot drift* from it — lethality, counters, standing reactions and the threaded hypo included. The cost is that this pass is **not** pure the way a bare volley was: it publishes projections onto units, so a scoring pass owes a restore at both ends (see *Attack scoring*).

**Consequence for future work:** anything that changes what a unit can fire or what a hit does (new families, carvings, mod effects, readiness economies, #76's strain gate, elemental changes) reaches the AI with **zero AI-side wiring**. If a feature lands player-side and the AI can't see it, the feature bypassed the player surface — fix the feature, not the AI.

## The predictability contract (read this before making the AI cleverer)

> *"One important thing about this game is that turn to turn, AI actions should be easily predictable. The complexity arises from multi-turn planning sequences that don't always go as expected."*
> — dev, 2026-09-02

**Its real use is as a reason to REJECT sophistication**, which is why it is written down rather than left as taste. The difficulty is meant to live in *multi-turn* consequence — a plan that does not survive contact — not in a single turn whose outcome the player cannot forecast. A scoring refinement that makes one turn harder to predict is therefore a cost, and has to buy something with it.

Two things follow, and both already happened:

- **It names the argument #707's pursuit ruling was already made from.** Rushdown pursues the *nearest* rather than its best target partly because *"it goes for whoever is closest"* is a rule you can bait and funnel, where *"it goes for its best target"* is a computation the player cannot see. That was argued from legibility with no name; this is the name.
- **It is what deleted the scoring bar (#711).** *"The AI should always attack if there is an option to, and if all the options are weighed bad, it has to pick its least bad option"* — a rule with no exceptions to hold in your head, replacing one whose refusals depended on counter math the player cannot do. See *Attack scoring*.

**The tension to know about:** the difficulty tiers the dev has floated — easier / medium / harder, weighing trades better and declining when only losing ones exist — make the AI *harder to model*, pulling directly against this. The resolution is [#710](https://github.com/Phaazoid/Godoiosis/issues/710), the threat preview: it lets the AI get less obvious without getting less predictable, because it draws the answer on screen. **Build order therefore matters — preview before tiers, not after.**

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
(Reload/Rev) entirely whenever the squad found no target at all (`choose_engagement_target` since
2026-09-02; `nearest_enemy` before it). `HoldArchetype` never moves, so it has no destination/move step, only this one.

**A FACTION TURN RE-DERIVES THE BOARD PER SQUAD** ([#714](https://github.com/Phaazoid/Godoiosis/issues/714), 2026-09-03). `AIController.take_faction_turn` takes no `BoardContext` parameter, and that absence is the fix: it used to build one for the whole turn while `execute_orders` between squads spans frames, so a unit an earlier squad **killed** was genuinely freed by the time a later squad planned — and `SquadManager._resolve_actions` opens by calling a method on every unit the board lists. The crash was the loud half; for the rest of that turn the AI had also been targeting, pathing and measuring cohesion against a roster including the dead.

Two things are worth carrying from it. **`play_session._take_ai_turn` had always called `_board()` inside its own loop** — two live implementations of one walk, with the fault in whichever was not the model, which is the same shape as the `went_downed` wire that was missing from the game and present in the Play API for thirteen months. And **`BoardContext`'s constructor now excludes a unit whose death has RESOLVED**, asking the domain fact (`Unit.die()` sets lifecycle DEAD *before* it queue_frees) rather than `is_queued_for_deletion()`; the filter is in the constructor because three builders feed it and a rule in one is a rule the other two disagree with.

## Attack scoring (ratified 2026-07-22; rebuilt onto the SQUAD'S PLAN 2026-09-02, #117)

A candidate is scored by its **marginal gain to the squad's plan** — `score(plan + candidate) − score(plan)`, both sides resolved by the real `SquadManager.resolve_plan` machinery — as `(net removals, net damage dealt, −damage taken from reactions)`, compared lexicographically. **The score ORDERS candidates; it never gates one** â the best-scoring candidate is queued whatever its sign (#711, below). *(Two terms until the third landed with target selection, 2026-09-02 — see* Target selection *for why it is a tie-break rather than a cost.)*

Until #117 the throwaway plan held **one volley against the live board**, so a member could not see what its squadmates had already committed to. That is what made three things impossible rather than merely unwise: a second member re-spent its action on a target the first already downed, a finishing blow looked like any other hit, and a damageless set-up (Splash) scored `(0,0)` and was refused outright — the AI was **structurally unable to open a combo**.

- Active enemies count **for**, any ally **against**, symmetrically — friendly fire is a soft penalty, not a ban (net-damage doctrine). Since #711 that penalty ORDERS rather than vetoes: a clean attack outranks one that splashes your own line, but with no clean option the splash is still taken.
- **A REMOVAL IS PER VICTIM, NOT PER HIT** — "on its feet before the plan, off them after", read through `PlanResolver.projected_lifecycle`. Counting the lethality rung of each row instead double-pays: the ladder answers `KILLED` for *any* damaging hit on a downed body, so the second member swinging at someone the first downed banked a fresh removal. CRISIS lands ACTIVE, so the gambit still counts as nothing and needs no clause of its own.
- **OVERKILL IS WORTH NOTHING** — a victim's damage is capped at the HP they had going in. Without this the removal ledger fixes only half the double-spend: full damage on an already-downed body ties exactly with the same number on an untouched enemy, leaving focus-fire to board order. The cap binds only on overkill.
- **A REACTION'S DAMAGE IS NOT SCORED, ONLY ITS REMOVALS** *(dev ruling, 2026-09-02)*. The plan now derives counters and watch shots, which is what closes *counters aren't scored* — but priced at par a counter cancels exactly: two units with the same weapon trade 3 for 3, **every even exchange scores `(0,0)`**, and a squad facing mirror-statted enemies declines every attack and reloads instead. Removals are the currency and damage the tie-break, so a counter that *fells* one of ours is a real loss and a scratch is the price of engaging. Worth knowing before re-opening this: C1/C4 make the counter a **per-plan fixed cost** that the *opener* bears alone (`defender_groups_that_countered` gates per squad, and every member of that party reacts to the first attack against it), so at par the AI would not merely decline even trades — it would never open on a multi-member squad at all.
- **Felling someone still standing always beats finishing a body or overkilling** *(dev ruling, 2026-09-02 — the reason is the player's rescue window: a down the AI leaves alone is squad play worth the trouble)*. #57's two passes are that rule and it is a **hard precedence, not a weight** — a body is neither aimed at nor scored while anyone is upright in reach, so no amount of damage on a corpse can outrank engaging someone on their feet. Overkill is the same rule read through the clamp: a second swing at someone the plan already felled is worth exactly `(0,0)`, so it ranks below any fresh target â and, since #711 removed the bar, is taken anyway when nothing else is in reach. Two clauses make the precedence honest, and each is one case in `tests/ai/test_squad_scoring.gd`:
  - ~~**Pass 2 needs an EMPTY pass 1, not a losing one.**~~ **SUPERSEDED by #711 (2026-09-03), and vacuous rather than wrong.** It distinguished *nobody to fight* from *nobody worth fighting*, which mattered only while a candidate could lose to the bar; with the bar gone pass 1 has no losing outcome — any candidate it looks at is also the one it returns — so the `considered` bookkeeping was deleted as dead code. **The half that survives is REFUSAL**: a candidate `queue_action` turned down is skipped before it can count, so it was never a real option and the body genuinely is the only thing left. What the rule protects is now pinned the other way round, by a case asserting the standing target is attacked *at a loss* while the body is still left alone.
  - **Pass 1 means "still standing once the plan so far has run"**, never "standing right now". Planning does not execute, so a unit a squadmate felled *this round* is still `is_active()` on the live board — read live it counts as a standing target and wedges pass 2 shut, leaving the last member idling beside an old body it should finish. `_attack_candidates` asks `base_plan.hypo` instead, which is also why `_best_candidate_for`/`_lookahead` take the base **plan** rather than its score: one source for both facts. It only ever drops a candidate the overkill clamp was going to score `(0,0)`, so nothing else moves, and it costs one fewer resolve per round.
  - The base score is measured on the **same `include_downed` terms as the candidate**, or a pass-2 marginal double-counts damage an earlier round already put on a downed enemy.
- Ties: earlier member, then earlier candidate — attacks in `get_selectable_attacks()` order, then units in board order. Deterministic, Law #1.
- No selectable attacks (unarmed, or an aura-dry rune) → a null pick probes the bare-fist Manhattan-1 / STR fallback, matching what the player gets in the same state.

**Selection is JOINT.** `AITactics._queue_attacks_jointly` runs in rounds: re-resolve the squad's real plan, score every remaining member's every candidate against it, queue the single best, repeat until every member that can attack has. (It ran "until nothing beats `(0,0)`" until #711 deleted the bar.) The remaining verbs stay the ratified per-unit priority walk — rescue/reload/rev/intimidate are a lexical order, not a score — so the fallback list has **ATTACK removed**, or a member the joint pass deliberately declined would re-decide alone and undo it.

**One step of LOOKAHEAD** *(dev fork, pairs in v1, 2026-09-02)*: a candidate that scores nothing alone **and** puts a state on an enemy is priced by **the better of its own solo score and the best squadmate follow-up**, scored as the pair against the same base. Bounded by that trigger rather than a depth counter, so a squad of plain weapons pays nothing. The follow-up is not committed — the next round finds it on its own, against a plan that really holds the set-up.

**The "better of" is #711's correction, and it is the one thing that ticket would have shipped broken.** The accumulator floored at `Vector3i.ZERO` and the caller *replaced* the solo score with the result — invisible while a candidate had to beat zero, since it only ever turned a refusal into a refusal. With no bar it **launders a negative into a zero**: a set-up really worth `(-1, 0, -5)` came back `(0,0,0)` and then outranked an honest plain swing at `(-1, 8, -4)` on the first term, so a member facing a lethal counter would soak instead of hitting and die dealing nothing — the predictability contract broken by the ticket that invoked it. Capping at the caller is **not** the fix: the zero lives inside the accumulator, so the floor has to become the solo score itself.

**The scoring pass is not pure, and the ORDER of its restores is load-bearing.** `resolve_plan` publishes projections onto units, so the pass must restore the real plan **before it queues** as well as on the way out. `queue_action`'s whiff gate (`SquadPlanValidator.aim_finds_a_target`) is the one reader of published knockback and is correct *only* because that knockback belongs to the already-queued aims; a scoring pass publishes a candidate's shove too, so without the pre-queue restore the gate hunted for the target on a cell some rejected hypothetical had thrown it to, found nobody, and refused the winner as a whiff — **every attack with knockback was unqueueable by the joint pass.** Found by a mutant, invisible to any fixture whose weapon does not shove.

**Dev rider (2026-07-22): this scoring rule is open to change as more AI kinds arrive.** It is deliberately one function (`AITactics._score_plan`) so a future archetype-flavored scorer swaps in one place.

Target-state awareness ships "minimal": lethality tiers (via the resolver's own prediction) + two builder tie-breaks — intimidate the lowest-Will adjacent enemy (maim-cliff pressure, skipping Will 0), rescue the most urgent downed clock. Deeper state reasoning (limb loss, Crisis avoidance/exploitation) is future scoring-term work, and the seam for it is `_score_plan`.

## Known v1 approximations (accepted at ratification)

- **Destination planning reads the default pick** — `best_attack_destination` hoists one `leader.get_fired_attack()` and evaluates every cell against it, rather than per-candidate-attack. Cells × attacks × enemies was judged not worth it yet.
  - Corrected 2026-08-06 by [#127](https://github.com/Phaazoid/Godoiosis/issues/127), which is worth knowing because the failure was *silent and permanent*: the approach ranked candidate cells by hops toward **the enemy's own square**, and `path_hops` is deliberately occupancy-blind, so a downed body parked on the one adjacent firing cell in a corridor read as the shortest way in. The unit walked up to the corpse and stopped — every turn, forever, because a dead end is stable. Two halves were both required, and each was falsified alone: the route now targets the nearest **standable** firing cell (`_nearest_standable_attack_cell`), *and* the ranking walk opts into occupancy (`path_hops(…, block_on_occupancy = true)`) so it stops imagining it can cut straight through the bodies in the way. Retargeting alone still stalled. The generalizable shape: **when a metric and the thing it measures disagree about what is passable, fixing the target does not fix the measure.** Note the two halves have **different scopes**, which is the part worth copying: the retarget is attack-specific (a firing position is not the target's own square), but the honest metric is not — it is unconditional in `_best_approach`, so **Sentry's walk home got the same fix**. Scoping it to the attack case would have meant gating it on the retarget parameter, i.e. one flag answering two unrelated questions, and `closest_reachable_cell_to` could never have reached it. A sentry stalls identically against an enemy holding a corridor; pinned by `test_walking_home_routes_around_a_body_holding_the_corridor`.
  - **Target selection was then brought onto the same metric (same day, same sweep).** Fixing the approach alone left `nearest_enemy` measuring occupancy-*blind* while the approach measured aware — two answers to "how far is that enemy", so the AI could pick a target it would only then discover was the long way round. Both now measure to a **standable firing cell** rather than the target's own square, via one shared `_standable_attack_cells`. Note the detail that makes it possible at all: an active enemy blocks passage, so an occupancy-aware walk *to enemy squares* scores every enemy UNREACHABLE — routing to firing cells is what lets target selection use the honest metric. Still one BFS for all enemies (the `until` set is the union). Pinned by `test_nearest_enemy_measures_to_a_firing_position_not_to_the_target_itself`, and **the whole rest of the suite passes with the old metric restored** — which is why this went unnoticed.
- ~~**Counters aren't scored**~~ and ~~**Squad-level coordination**~~ — **both closed 2026-09-02 by the plan-marginal rebuild above.** What they leave behind is three narrower approximations, each named so nobody re-derives it:
  - **The opener bears the counter alone — no longer a freeze, and no longer anything at all.** C1/C4 make a defending party react once per plan, to the *first* attack against it, so the whole cost lands on whichever candidate is scored first. Until #711 that froze a squad outright: if those counters would fell the opener, no candidate netted a positive removal and it would not open even when the follow-ups won the exchange (playtest symptom, *"the enemy won't attack my tank"*). With no bar the squad opens. **And nothing clever replaces it, which is worth stating so nobody goes looking**: `SquadManager.choose_counter_target` picks the first legal member of the attacking *party* in member order (or a taunter) and never asks who opened, and in round 1 nobody has moved — so every candidate aimed at a given defending squad draws the identical volley, the cost is constant across the argmax, and it cancels. Round 1 is decided by removals and damage dealt as though counters did not exist.
  - **Reaction heals are invisible.** `plan.counters` carries reactive heals (C8–C10) and heals are not scored at all, so the AI counts full damage against a healer-guarded target and the heal quietly undoes some of it. Removals stay honest — a heal never lifts a lifecycle — so only the chip-damage term is overstated.
  - **Heals and end-of-turn tile damage are not terms.** `heal_amount` would make AI healers start healing, which is its own behaviour and its own ticket; `tile_hits` is inert until movement is scored, since an attack candidate never changes where anyone ends the turn.
- **Movement never seeks rescue/intimidate targets** — fallback verbs fire from wherever attack-driven movement landed the unit.
- **Movement is not scored at all** — joint selection prices *what a member does*, never *where it stands*. `score(plan with X at cell C)` is the same delta and is the natural next step, but the destination pick is still the group move below.
- **Movement is a group move, not per-unit destinations** — both moving archetypes call `queue_group_move`, so a member's destination is "preserve your path-offset from the leader" rather than anything tactical. Measured 2026-07-29 while fixing [#103](https://github.com/Phaazoid/Godoiosis/issues/103): this is **not** why the AI authored illegal plans (a single individual leader move produces the identical refusal — the invalid order is the hold-position filler `game.gd` gives every member, and the binding rule is `SquadPlanValidator._check_leader_range`, which applies to any plan from any author). But `GroupMoveSolver` is currently the AI's *only* cohesion solver, so this cannot simply be deleted. The replacement needs no new solver — `RulesService.compute_move_range` already leashes a non-leader to the leader's *projected* destination, so queueing the leader first makes each member's own range cohesion-clamped — what it needs is a decision about each archetype's per-unit movement taste. Tracked on [#117](https://github.com/Phaazoid/Godoiosis/issues/117).

**The standing home for all of the above is [#117](https://github.com/Phaazoid/Godoiosis/issues/117)** (evergreen), added 2026-07-29 on the premise that the AI is permanently behind the feature set: every system we add creates AI work that lands after the system ships. New approximations go there as well as here — here for the doctrine, there for the queue.

## Target selection — TWO SYSTEMS, forked on "is anybody attackable this turn?"

*(Dev ruling, 2026-09-02, from playtest: an enemy adjacent to a spearman that could counter, with a mage one step beyond that could not, took the spearman. Both were attackable that turn.)*

- **Somebody is → the best EXCHANGE wins, and distance is only the tie-break.** His words: *"the closest possible unit isn't what should be picked, but the best possible trade for the attacker… absolute distance was not even, but that should not matter since both attacks were in range that turn."*
- **Nobody is → pursue the NEAREST**, exactly as before. `nearest_enemy` is unchanged and is now the pursuit half alone.

**Pursuit stays nearest deliberately, and the reasons are design rather than cost.** It is Rushdown's *identity* — a rusher that hunts the softest target across the board is the **Balanced** archetype wearing the wrong name. It rewards the player for screening a mage behind a frontline, which is the same thing #57's rescue window rewards. And it is *legible*: "it goes for whoever is closest" is a rule you can bait and funnel, where "it goes for its best target" is a computation the player cannot see (Law #1's spirit, applied to the AI's reasoning).

`AITactics.choose_engagement_target` is the fork; `RushdownArchetype` and `SentryArchetype` both call it. **Sentry passes BOTH its leashes and they answer different questions:** `within` tests the *enemy's own cell* (is this intruder in my zone), `allowed` tests the *cell I would fight from*. Dropping either lures a sentry out — one by target, one by footing.

**The exchange term is a BOOLEAN — can this target answer me from the cell I would attack from — not a scored one**, and that ceiling is structural: scoring an attack from a cell nobody has moved to is impossible today (see *Out of scope* below). It is asked through `SquadManager.can_counter`, which takes the attacker's cell as a parameter rather than `AITactics` re-deriving counter reach — Law #4's own words, *"if you cannot reach the existing answer from where you are standing, take it as a parameter"*. A private counter-reach predicate would be exactly the drift #78 exists to stop.

**One BFS, and the legality filter runs BEFORE it.** `_engageable_enemies` collects each enemy's firing cells that are both in move range and inside `allowed`, then walks `path_hops` once over the union (`_approach_distances`' own trick). Asking for the globally nearest firing cell and testing *that* is wrong twice: it excludes an enemy whose nearest cell is outside the leash when another one inside it would serve, and it pays a whole BFS per enemy — measured at +21% on Castle Assault before the fix, and *faster than baseline* after it.

**Declared asymmetry:** this layer judges an exchange by a boolean, the attack pick (`_score_plan`) by graded resolver damage. Justified rather than sloppy — this layer cannot resolve at all, and the attack pick can and would be throwing information away. Stated here so the pair is a design rather than a drift.

**Known limits, declared:**

- **The engageable set is OPTIMISTIC for a leader with squadmates.** It uses the leader's own unclamped move range, but cohesion (V3) can refuse the group move to a cell the leader alone could stand on, in which case the squad stays put. `best_attack_destination` has carried the identical optimism since #29, so nothing new is introduced — but in play it reads as *"it went for the mage and then didn't."*
- **Leader-only.** `engage` group-moves the whole squad toward the leader's pick, so a target good for the leader may be poor for a member. Widening it is #117's per-unit movement item.

## Not this layer

The Balanced archetype (#29 leftover), strain's fate (#76 — its AI integration is already free by construction), the ability-chassis content itself (#61, closed).

**Balanced now has a DEFINITION rather than only a name** (2026-09-02, out of the target-selection ruling): *pick the best target from the start and take what you meet on the way* — the answer Rushdown deliberately does not give. That is the archetype whose **movement** is scored, and it is why the two poles stay far apart: smear target quality into Rushdown and there is nothing left for Balanced to be.

**Win/loss detection is no longer a leftover** — it landed 2026-07-28 as #96 and lives outside this layer, in `MissionRules`/`MissionController` ([missions.md](missions.md)). The AI has two points of contact:

- **A guard.** `AIController.take_faction_turn` stops issuing orders the moment the mission is over, so a squad that wipes the player mid-turn doesn't keep playing behind the end-of-mission card.
- **`CAPTURE` is `MAIN_ACTION_NEVER` on all three archetypes**, forced to be an explicit decision by `tests/law/test_ai_action_coverage.gd`'s partition. **This one is not drift.** Rev and Burrow are `NEVER` because nobody has written a scored builder yet; `CAPTURE` is `NEVER` because there is nothing for an AI faction to *win* by capturing — enemy objectives are out of #96's scope, and the point belongs to the player. The AI contests it positionally with what it already has: Rushdown walks into the approach, and a Sentry squad zoned over the point defends it with no AI code at all. Revisit when non-player factions get objectives of their own — which is exactly [#571](https://github.com/Phaazoid/Godoiosis/issues/571), *defend a point* (split out of #101 when that closed), and the first thing that will need a real capture builder.
