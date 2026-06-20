# Resolution Pipeline — the one place consequences are derived

**Status: LOCKED CONTRACT (keystone) — ratified 2026-06-18 (#5); v1 IMPLEMENTED 2026-06-19 (#28) — base + elemental stages live in `Classes/actions/PlanResolver.gd` (with `ResolvedPlan`/`ResolvedOutcome`), proven by `tests/elemental/` (E1–E8). The Will stage is the next addition behind elemental.** A foundational decision agreed **before the elemental build (Phase 2) hardens**, because Phase 2 is where this pipeline is first built.

> **Locked 2026-06-18 (#5):** R1–R8 ratified, plus three clarifications folded in for Will's sake — **R4** threads HP (+ a Will slot), not element-states-only; **R7** counter *derivation* reads the threaded hypothetical (liveness-ready); **R8** the `ResolvedOutcome` is the single source of truth for damage (`AttackAction` stops computing it). Deferred (not locked): volley / simultaneous-hit ordering within one AoE — revisit when tile states or multi-hit-same-target arrive. This doc sits *above* the counter rules in [squad-system.md](squad-system.md) and the [elemental](elemental-system.md) / [will-and-death](will-and-death.md) designs: it defines the single seam all three plug into. The **contract (R1–R8)** is what's being locked; class names are illustrative.

## Why this doc exists

Three systems are the **same operation** wearing different hats:

| system | status | derives… |
|---|---|---|
| **Counter-attacks** | built (`SquadManager.calculate_counterattacks_for_squad`) | who counters whom, from the plan |
| **Elemental reactions** | Phase 2 ([elemental-system.md](elemental-system.md), E1–E8) | reacted damage + state changes, from the plan |
| **Will / death outcomes** | Phase 3 ([will-and-death.md](will-and-death.md)) | downed / maim / overkill, from the plan |

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
2. **Base damage** — the math currently inside `AttackAction.create()` (`weapon.power + scaling_stat`, or `STR` unarmed). This **moves into the pipeline** (elemental E1).
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

R1–R8 **subsume the elemental E-invariants** (E1–E8 are this contract scoped to the elemental stage) and give Will a defined plug-in point rather than a parallel mechanism.

**Deferred (not locked — revisit when relevant):** volley / simultaneous-hit ordering *within* one AoE. v1 volleys hit distinct targets with separate state stores, so sibling pass-order is moot now; revisit when tile states or multi-hit-same-target arrive (do volley siblings resolve sequentially against threaded state, or all against one pre-volley snapshot?).

## Where it lives

A dedicated resolver invoked by `SquadManager` (already the derived-action home and overweight, so a separate class is the clean seam). The base-damage math from `AttackAction.create()` becomes a value the resolver writes (E1). **Class layout is a build-time call**; what's locked here is the contract and the stage order. Naming is open — `PlanResolver` with pluggable stages, or a thin `ElementResolver` that Phase 3 extends — decide when building Phase 2.

## Migration is incremental — you do *not* build all stages at once

1. **Phase 2 (elemental v1)** introduces the pipeline with only **base-damage + elemental** stages, plus the `ResolvedPlan` / `ResolvedOutcome` types and the single preview model (R8). The threaded hypothetical carries **HP + a Will slot** from the start (R4), and the counter stage reads it with an **always-true liveness flag** (R7) — both so Phase 3 adds the Will stage without re-threading or re-deriving counters. Counters keep working as they do; just make sure they flow through the same resolved result (R3). *The deliverable is the general seam, not a private elemental box.*
2. **Phase 3 (Will/death)** adds the **Will stage** reading the resolved damage (R7). No re-architecture — it slots in behind elemental.
3. **Counters** already fit (they're attacks); the work is ensuring they **re-enter** the stages so E7 holds.

Building Phase 2 against this contract costs almost nothing extra now and saves rebuilding the resolver/preview in Phase 3.

## The persistence seam (already half-built — relevant to two open forks)

The code already splits **transient vs persistent**: the `Unit` *node* ("these only exist during combat") holds a `UnitInstance` *resource* ("persistent changes… stat changes, limb loss, weapon proficiency"). HP lives on `UnitInstance`. So the forks resolve against an **existing** seam, not a hypothetical one:

- **Element states** (elemental fork 3): v1 is boolean and chain-scoped → they live on the **transient `Unit`** (and on the resolver's hypothetical copy during the pass). The deferred over-time layer can revisit.
- **Will** (will-and-death fork 1, persist-vs-reset): if Will **persists** between missions, it belongs on **`UnitInstance`** — which already advertises a home for "limb loss." If it **resets** per mission, transient `Unit` suffices.

(Note: `UnitInstance` currently still contains `level` / `level_up()` / `growth_ranges` / `randi_range`, which predate and contradict the no-leveling decision in [progression.md](progression.md). Reconcile that when this seam is formalized — tracked in the backlog.)

Cross-refs: [squad-system.md](squad-system.md) (execution model, the counter prototype), [elemental-system.md](elemental-system.md) (E1–E8 = the elemental stage of this pipeline), [will-and-death.md](will-and-death.md) (the Will/death stage), [progression.md](progression.md) (UnitInstance / persistence), `../../CLAUDE.md` (Laws #1/#2).
