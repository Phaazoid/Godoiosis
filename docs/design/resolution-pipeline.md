# Resolution Pipeline — the one place consequences are derived

**Status: LOCKED CONTRACT (keystone) — ratified 2026-06-18 (#5); v1 IMPLEMENTED 2026-06-19 (#28) — base + elemental stages live in `Classes/actions/resolution/PlanResolver.gd` (with `ResolvedPlan`/`ResolvedOutcome`), proven by `tests/elemental/` (E1–E8). AMENDED 2026-07-05: R9 added (the BREAK doctrine — plans are predictions; execution re-enters the resolver at divergence), a deliberate co-dev amendment out of the coherence audit's A1. The Will stage this doc specified is now built too: the lifecycle scaffold + Will resource (2026-06-21→25, #33), the limb-slot/MOV rewrite (#56), and AI Crisis stances + the CRISIS lethality preview (#57) — all 2026-07-15. This contract's job is done; it now documents *why* the shipped shape is correct, not a pending build.** A foundational decision agreed **before the elemental build (Phase 2) hardens**, because Phase 2 is where this pipeline is first built.

> **Locked 2026-06-18 (#5):** R1–R8 ratified, plus three clarifications folded in for Will's sake — **R4** threads HP (+ a Will slot), not element-states-only; **R7** counter *derivation* reads the threaded hypothetical (liveness-ready); **R8** the `ResolvedOutcome` is the single source of truth for damage (`AttackAction` stops computing it). Deferred (not locked): volley / simultaneous-hit ordering within one AoE — revisit when tile states or multi-hit-same-target arrive. This doc sits *above* the counter rules in [squad-system.md](squad-system.md) and the [elemental](elemental-system.md) / [will-and-death](will-and-death.md) designs: it defines the single seam all three plug into. The **contract (R1–R8)** is what's being locked; class names are illustrative.

**Canon checked through #83 (2026-07-22).**

## Why this doc exists

Three systems are the **same operation** wearing different hats:

| system | status | derives… |
|---|---|---|
| **Counter-attacks** | built (`SquadManager.calculate_counterattacks_for_squad`) | who counters whom, from the plan |
| **Elemental reactions** | built, Phase 2 ([elemental-system.md](elemental-system.md), E1–E8) | reacted damage + state changes, from the plan |
| **Will / death outcomes** | built, Phase 3 (#33, #56, #57 — [will-and-death.md](will-and-death.md)) | downed / maim / overkill / Crisis, from the plan |

All three: a consequence **derived from the ordered plan at queue time → surfaced in the preview → replayed at execution.** Counters already work exactly this way; the other two are specified to. They are not merely *similar* — they are **coupled and ordered** (see "The forced ordering"). If each is built as a private subsystem, you get the plan walked three times, three preview paths that drift apart, and elemental-damage and Will-lethality that disagree about ordering. **One pipeline prevents all of that.** Decide its shape now; Phase 2 builds it, Phase 3 slots into it.

## The pattern is already in the codebase

The counter implementation is the working prototype of the whole idea:

- `SquadManager.calculate_counterattacks_for_squad()` walks `action_queue`, derives `CounterAttackAction`s, and **returns** them — never stores them in the queue.
- `SquadManager.get_display_entries_for_squad()` calls it so the **preview** shows the derived counters.
- Execution instantiates counters fresh from the plan.

That's *derive → show → replay*. The pipeline generalizes this one proven move so elemental and Will reuse it instead of reinventing it.

## The pipeline

**One pure pass over the ordered plan**, in the execution order squad-system.md already promises (**moves → attacks → counters**), producing a **`ResolvedPlan`**: for every action, its resolved damage, its state-deltas, and its lifecycle outcome. **Preview and execution both consume the `ResolvedPlan`** — execution stops computing and just plays it back.

Conceptual stages, applied per attack in queued order while a **hypothetical copy of unit state** is threaded forward:

1. **Position** — already projected today via `Unit.get_projected_destination()` (the leader's planned cell, etc.).
2. **Base damage** — originally the math inside `AttackAction.create()` (`weapon.power + scaling_stat`, or `STR` unarmed); per R8 this moved into the pipeline (elemental E1) and has moved again since — `PlanResolver._source_base_damage` now reads whichever `AttackData` the order stamped (`AttackAction.fired_attack`: a carving, a specific `WeaponAttackData`, or null = the weapon's main), scaled by `scaling_blend` + active mods (#59, #72), or bare `STR` unarmed.
3. **Elemental** — read the target's hypothetical states, match an `ElementalReaction`, modify damage, write state add/remove. (Phase 2.)
4. **Will / death** — read the *now-final* damage, pick the rung: downed / maim / overkill-kill / Crisis. (Phase 3.)
5. **Counters** — counter *existence* is derived from the attack plan as `calculate_counterattacks_for_squad` does today, **but read from the threaded hypothetical** (projected positions + liveness), not live state; each counter is itself an attack and **re-enters stages 2–4** (so a counter can complete a combo — elemental E7 — and can down/kill). A counter-er killed earlier in the pass is not derived (liveness is always-true until Phase 3's Will stage).

## The forced ordering (the insight neither downstream doc states)

Elemental resolution **produces the final damage number**, and the Will ladder **judges "fatal?" against that number.** Therefore, per attack, the order is mandatory:

```
base damage  →  elemental modifies it  →  Will reads the result
```

A `SHOCK × WET` combo that boosts damage can push a hit from *"this downs them"* to *"this overkills — dead."* That coupling is real game behavior and it can only be correct if both live in **one ordered pass**. This is the single most important reason the pipeline is one thing, not three.

## Contract — R-invariants

Numbered for test coverage, like the squad spec's I/C and elemental's E. Violating any is a bug.

- **R1. One pass, one `ResolvedPlan`.** No system privately re-walks the plan to derive its own consequences.
- **R2. Pure & deterministic (Law #1).** Reads a snapshot of board/unit state, returns results, mutates **no** live state, contains **no RNG**.
- **R3. Preview and execution consume the *same* `ResolvedPlan` (Law #2).** Execution applies resolved damage / state-deltas / lifecycle outcomes and derives nothing new mid-combat.
- **R4. Hypothetical state is threaded forward — and it carries HP, not just element states.** The threaded hypothetical models, per unit, `{projected position, element states, HP, (Will — Phase 3)}`. An earlier action's deltas (HP from damage, state add/remove) are visible to later actions *within the same pass*; live unit state changes only at execution, action by action. **The carrier is built Will-ready from day one:** Phase 2 reads/writes only element states + HP-from-damage, but the Will field exists so Phase 3 slots in without re-threading. This is the keystone's whole point — a `SHOCK×WET` hit and the Will ladder read the *same* evolving HP.
- **R5. Derived, never stored.** Like counters: recomputed from the plan on every change, never persisted as player orders. The player authors *orders only*; damage, reactions, and Will-outcomes fall out of resolution.
- **R6. Order is the player's lever.** Attacks resolve sequentially in queued order; reordering the combo changes the outcome. That *is* the skill expression — protect it.
- **R7. Stage order is fixed:** position → base damage → elemental → Will/death → (counters re-enter base→elemental→Will). **Damage is final before the Will stage reads it.** **Counter *derivation* consumes the threaded hypothetical** (projected positions + liveness), not live state: a counter-er downed/killed earlier in the pass cannot counter. Phase 2 builds the counter stage reading the hypothetical with a liveness flag that is **always-true until the Will stage exists**; Phase 3 only flips it on.
- **R8. One outcome model.** Every stage annotates the *same* `ResolvedOutcome` per action (damage delta, state changes, lifecycle result); one preview widget renders it ("−12", "Electrocuted!", "Downs them", "No Will → lethal"). No per-system preview path. **The `ResolvedOutcome` is the single source of truth for an action's damage** — `AttackAction` stops *computing* damage (E1), and `execute()` consumes the `ResolvedPlan` rather than a frozen `AttackAction.damage`. (Remove the old field or keep it as a populated mirror — a build-time call; that it no longer *originates* the number is locked.)
- **R9. Plans BREAK; the resolver re-enters. (Added 2026-07-05, co-dev grill.)** The `ResolvedPlan` is a **prediction under (known state × stated assumptions)** — honest about its knowledge horizon, never omniscient. Three divergence classes: **choice** (a live decision — player Crisis — realizes differently than the assumed branch), **knowledge** (fog-hidden units/states change an outcome — the sanctioned surprise channel, philosophy Axiom 4), **cascade** (full-information self-sabotage — legal to queue, previewed per Law #2). At execution, each action's realized preconditions/outcome are compared against prediction; on divergence → **BREAK**: halt playback, flash the banner, **re-resolve the remaining plan against realized state** (pure given realized inputs — R2 survives), resume. **Aftermath: orders stand** — no mid-turn re-planning; actions whose preconditions died **fizzle loudly, no refund** (fog-probing stays expensive). R3 is amended to: *execution derives nothing new — except at BREAK points, where it re-enters the resolver.*

### The BREAK doctrine (R9 expanded — 2026-07-05)

*"No plan survives contact with the enemy. How we handle the aftermath is what's important."* — the dev, ratifying this.

> **Co-dev verdict (2026-07-14 ratification pass, Stop 6): adopted TRY-IT-AND-SEE.** Build it as written; whether it stays is decided at the table, not on paper. The one A1–A8 resolution ratified on trust rather than full conviction — flag playtest reactions to BREAKs (frequency, legibility, the fizzle-no-refund sting) back to this doc.

- **Known breaks are previewed.** With full information the resolver predicts the cascade at plan time (attack triggers a reaction → leader shoved → squad dissolves → three later orders orphan) and the queue shows a **BREAK marker** + fizzle annotations at the point of collapse. Planning your own ruin is legal — no hand-holding; doing it *unknowingly* is not (Law #2).
- **Fog breaks are the sanctioned surprise.** The resolver resolves against **player-visible** state; a hidden counter-er (the fire counter on the frozen river) diverges at execution. Epistemically honest — fog reads as fog, and PER is the counterplay. NB: once hidden information exists, the resolver must distinguish *planner-visible* state (what the hypothetical threads) from *true* state (what the executor compares against). Build the seam that way from the start.
- **Choice-points** (player-unit Crisis today; guard/reaction abilities and mid-battle re-flourishing later) are marked in the plan with an assumed branch; realizing the other branch = BREAK. **Enemy Crisis never BREAKs** — archetype stances + the full-Will gate are deterministic, so the resolver predicts it exactly ([will-and-death.md](will-and-death.md)).
- **The banner fires on every BREAK, both sides** — your traps shattering the enemy's turn get the same full-screen "BREAK" moment (the satisfying half). Motif reserved exclusively for this ([visual-clarity.md](visual-clarity.md)).
- **Play API:** a BREAK is an event-log entry — no re-planning verbs. A player-side choice-point in a headless run waits on one small `answer(choice_id, accept)` verb ("awaiting choice" envelope) — see [play-api.md](../play-api.md).
- **Rarity is a content dial** (how much fog, how much repositioning content), not a system rule. Breaks should be memorable, not routine.

R1–R8 **subsume the elemental E-invariants** (E1–E8 are this contract scoped to the elemental stage) and give Will a defined plug-in point rather than a parallel mechanism.

**Deferred (not locked — revisit when relevant):** volley / simultaneous-hit ordering *within* one AoE. v1 volleys hit distinct targets with separate state stores, so sibling pass-order is moot now; revisit when tile states or multi-hit-same-target arrive (do volley siblings resolve sequentially against threaded state, or all against one pre-volley snapshot?).

## Where it lives

A dedicated resolver invoked by `SquadManager` (already the derived-action home and overweight, so a separate class is the clean seam). The base-damage math from `AttackAction.create()` becomes a value the resolver writes (E1). **Class layout is a build-time call**; what's locked here is the contract and the stage order. Naming is open — `PlanResolver` with pluggable stages, or a thin `ElementResolver` that Phase 3 extends — decide when building Phase 2.

## Migration is incremental — you do *not* build all stages at once

1. **Phase 2 (elemental v1)** introduces the pipeline with only **base-damage + elemental** stages, plus the `ResolvedPlan` / `ResolvedOutcome` types and the single preview model (R8). The threaded hypothetical carries **HP + a Will slot** from the start (R4), and the counter stage reads it with an **always-true liveness flag** (R7) — both so Phase 3 adds the Will stage without re-threading or re-deriving counters. Counters keep working as they do; just make sure they flow through the same resolved result (R3). *The deliverable is the general seam, not a private elemental box.*
2. **Phase 3 (Will/death) — DONE.** Added the **Will stage** reading the resolved damage (R7), no re-architecture needed — it slotted in behind elemental exactly as planned, across #33 (scaffold + Will resource), #56 (limb-slot/MOV), and #57 (Crisis stance + lethality preview).
3. **Counters** already fit (they're attacks); the work is ensuring they **re-enter** the stages so E7 holds.

Building Phase 2 against this contract costs almost nothing extra now and saves rebuilding the resolver/preview in Phase 3.

## The persistence seam — FORMALIZED (#8, decided 2026-06-21)

The code splits **transient vs persistent**, and that split is now the **locked boundary** — no feature invents its own persistence. The `Unit` *node* ("these only exist during combat") holds a `UnitInstance` *resource* (the canonical persistent-identity store; HP already lives there). The rule, decided once so elemental and Will don't each grow a private store:

- **Transient `Unit` node = battle-scoped.** Everything that resets at mission start: v1 boolean element states (`Unit.element_states`, live in code), projected position, the resolver's per-pass hypothetical copy. Re-created per spawn.
- **Persistent `UnitInstance` resource = identity across missions.** The *only* persistent store **of unit state**: fixed stats, HP, limb loss, weapon proficiency, **and Will**. Anything needing cross-mission memory lands here. *(The cross-mission save/load wiring is the future campaign layer — today `UnitInstance` is `.new()`'d per spawn, so nothing survives a mission through the campaign flow yet; what's locked is **where** persistent state belongs, so each feature rides along once that layer exists rather than being stranded on the transient node. Scenario saves, though, now round-trip this store — see the #83 note below.)*
- **Campaign store (named 2026-07-05, audit A8) = what the *player/party* knows and owns.** The "no third store" rule is **unit-scoped** — it forbids a second home for *unit* state, not party state. Party/player-scoped persistence — the transmutation **codex**, squad **familiarity/connections**, the authored **economy**, unlockables / recipes / achievements — is the pattern every game carries, and its designated home is a single **campaign-store** resource in the future save-file layer. Named now, #8-style, so features land on the right side: new persistent state picks by one test — *is it about a unit, or about the party?* Unit → `UnitInstance`; party → campaign store. Nothing builds it yet; the codex is likely its first customer.

**Scenario saves carry the instance side ([#83](https://github.com/Phaazoid/Godoiosis/issues/83), 2026-07-22):** `ScenarioUnitEntry.capture_unit_state`/`apply_unit_state` snapshot the whole persistent store per unit — edited stats, current HP/Will, the full inventory (`copy_equippable` both directions; `equipped_index` replaced the old standalone equipped-weapon copy), limb states (an installed prosthetic re-links against the carried instance's shared template on load), weapon proficiency, and aura — applied *after* `initialize()`'s reset on load. Deliberately still battle-scoped and NOT saved, per this seam: element states, lifecycle/downed state, weapon readiness (#73's reset-fresh contract). This is the dev-scenario layer exercising the seam (it unblocks the #9 fixture library), not the campaign layer itself.

**Save-format forward-compat ([#11](https://github.com/Phaazoid/Godoiosis/issues/11), closed 2026-07-22):** the future campaign save file carries a `save_version` + migration path **from day one** — real player saves can't be hand-repaired. Dev-phase scenario `.tres` deliberately do NOT: additive `@export` defaults cover schema growth for free, and structural breaks are caught by the scenario load-integrity suite (#9) and repaired by scripted text-level migration (clean-over-legacy, 2026-07-16). A load-time version hook couldn't do that job anyway — Godot drops moved/unknown properties during `load()`, before any migration code could see them (proven twice: #80 and the missing-`weapon_type` wave).

Both features that hung on this seam are now resolved:

- **Element states** (elemental fork 3): boolean + chain-scoped → **transient `Unit`** (built; threaded as a copy through the resolver pass). The deferred over-time layer can revisit.
- **Will** (will-and-death fork 1, persist-vs-reset): **PERSISTS → `UnitInstance`** (decided #8, 2026-06-21). Max Will (innate identity) and current Will both live on the persistent store, beside the limb-loss it already advertises. Fork 2 (individual vs squad-*pooled* Will) stays open but is compatible: per-unit Will sits on `UnitInstance` regardless; a squad pool, if added, is **additive**, not a relocation.

> **Paired reconcile (#12) — DONE 2026-06-21:** the benched `level` / `level_up()` / `randi_range` leveling path (predating and contradicting no-leveling, [progression.md](progression.md)) was stripped from `UnitInstance`, along with the now-dead `growth_ranges` on `UnitData`. The store is now clean — *fixed stats, no growth; home for HP / limb-loss / proficiency / Will.* ([#12](https://github.com/Phaazoid/Godoiosis/issues/12))

Cross-refs: [squad-system.md](squad-system.md) (execution model, the counter prototype), [elemental-system.md](elemental-system.md) (E1–E8 = the elemental stage of this pipeline), [will-and-death.md](will-and-death.md) (the Will/death stage), [progression.md](progression.md) (UnitInstance / persistence), `../../CLAUDE.md` (Laws #1/#2).
