# AI Tactics — the archetype layer's integration contract

**Canon checked through #78 (2026-07-22).**

**Status: BUILT 2026-07-22** — ratified and hand-typed the same day (#78); full suite 444/444 green, in-game feel-test pending. The #29-era archetype layer (Rushdown/Hold/Sentry, painted zones, Crisis stances — see CLAUDE.md's architecture map) is the substrate; this doc covers the #78 rebuild of *how the AI decides*, and the standing contract that keeps it from rotting again.

## The doctrine: the AI is a player, all the way down

Law #3 ("AI issues orders exclusively through `SquadManager.queue_action`") was necessary but not sufficient — the fists bug (#78) happened because the AI queued through the right chokepoint while *skipping steps of the player's declare flow* (the `fired_attack` stamp). The rebuilt doctrine closes that class of bug:

- **Pick** — the AI selects among `Unit.get_selectable_attacks()` by setting `Unit.active_attack`, the same slot the player's pick menu writes. Every reach/victim/splash query reads it, so probe and declare can't disagree.
- **Declare** — both the player's click handler and the AI build attacks through `AttackAction.declare()`, the one factory that stamps `fired_attack` (Law #2's declare-time snapshot). Bare `create()` is for derived actions only.
- **Queue** — `queue_action` + `actor_can_perform()` stay the backstop behind every builder's own gate.
- **Forecast** — candidate scoring runs `PlanResolver.resolve()` on a throwaway volley. The resolver is a pure pass (R2), so this is free of side effects and *cannot drift*: the AI evaluates a candidate with exactly the math the queue panel previews, lethality included.

**Consequence for future work:** anything that changes what a unit can fire or what a hit does (new families, carvings, mod effects, readiness economies, #76's strain gate, elemental changes) reaches the AI with **zero AI-side wiring**. If a feature lands player-side and the AI can't see it, the feature bypassed the player surface — fix the feature, not the AI.

## The policy registry (the one place per-archetype behavior lives)

`AIArchetype` declares, per archetype (same idiom as `CRISIS_STANCES`):

- `MAIN_ACTION_PRIORITY` — an ordered try-list over `BaseAction.MAIN_ACTION_TYPES`; `AITactics.queue_main_action` walks it and the first type that yields a buildable candidate wins.
- `MAIN_ACTION_NEVER` — the explicit opt-outs.

Every main action type must land in exactly one of the two, for every archetype — pinned by `tests/law/test_ai_action_coverage.gd`. **A new verb cannot silently skip the AI**: the suite stays red until a stance is declared, even if that stance is NEVER. This is the action registry's AI column, mirroring how `test_action_registry.gd` pins the pipeline.

Candidate builders live in `AITactics` (one per type, each mirroring `MainActionMenu`'s gate for that verb); an undeclared builder is a loud `push_error`, never a silent skip.

### Ratified tables (dev calls, 2026-07-22)

| | ATTACK | RESCUE | SPRING_LOAD | INTIMIDATE | RALLY |
|---|---|---|---|---|---|
| **Rushdown** | 1 | never | 2 | never | never |
| **Hold** | 1 | 2 | 3 | 4 | never |
| **Sentry** | 1 | 2 | 3 | 4 | never |

- Intimidation/rescue on Hold+Sentry only — defenders recover their own and menace what they can't hit; Rushdown stays pure aggression.
- Rescue before Spring Load: a returned unit now beats rearming for later. Intimidate last: menace only when nothing better exists.
- RALLY is NEVER everywhere for now: early rallies burn the strong falloff steps (6/4/2…) while idling. Revisit with real Will-awareness — this is a deliberately parked knob, not an oversight.

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

- **Destination planning reads the default pick** — `best_attack_destination` evaluates reach with `active_attack` reset, not per-candidate-attack. Cells × attacks × enemies was judged not worth it yet.
- **Counters aren't scored** — the throwaway plan resolves the AI's own volley only; walking into counter range costs nothing in the score.
- **Movement never seeks rescue/intimidate targets** — fallback verbs fire from wherever attack-driven movement landed the unit.
- **Squad-level coordination** — members choose independently in member order; no focus-fire or combined-arms reasoning.

## Not this layer

Win/loss detection, the Balanced archetype (#29 leftovers), strain's fate (#76 — its AI integration is already free by construction), the ability-chassis content itself (#61, closed).
