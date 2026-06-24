# Will & Death — "The Art of Not Dying"

> **⚠️ PROVISIONAL (redesigned 2026-06-24, solo grill-me session). NOT playtested, NOT yet co-dev-reviewed, NOT built.** Everything below the [Implementation status](#implementation-status) section is a **starting line**, not a locked spec — it came out of one design conversation and is expected to shift in playtest and once the co-dev weighs in. The numbers especially (`N`, max Will, Crisis gate, Rally cap) are pure placeholders. The *lifecycle scaffold* (downing, rescue, etc.) **is** built; the **Will resource itself is still a stub** (`Unit.OVERKILL_CEILING`, not spent Will). Tracked in [#33](https://github.com/Phaazoid/Godoiosis/issues/33).

Design direction first agreed 2026-06-15; **reframed 2026-06-24**. Builds on the implemented death floor (`Unit.unit_died` fan-out). Supersedes the wiki's random-dismemberment framing (Law #1) **and this doc's own pre-2026-06-24 "Will gates life" ladder** (see below).

## The 2026-06-24 reframe — Will gates *limbs*, not *life*

The old ladder made Will a **life buffer**: you spent Will to convert a fatal hit into a down, and *running out of Will meant death*. The grill flipped it:

- **Will is a *limb / integrity* buffer.** A sub-overkill fatal hit **always** downs you (Will or not). Will only decides whether you go down **intact or maimed**.
- **Will never directly kills.** Death comes only from overkill, a failed rescue, or Crisis.

Why this is better: it removes the harsh "low Will → you just die" cliff (nobody dies from depletion — they get maimed and need rescue), it makes maim the *earned cost of fighting depleted* rather than a narrow edge rung (the dev's original worry), and — conveniently — it's **closer to the existing stub** (which already downs-unless-overkill regardless of Will) than the old design was. Determinism is preserved throughout (Law #1): no down-roll, no maim-roll; the down is unconditional and the maim is a threshold.

## Implementation status

**Built + committed 2026-06-21 — the lifecycle scaffold** (unaffected by the redesign; the new model *layers onto* it):
- `Unit.LifecycleState {ACTIVE, DOWNED, DEAD}`; `take_damage()` funnels a would-be-fatal hit through `_select_lethal_rung()` → DOWN (cling at 1 HP) or, past `OVERKILL_CEILING`, DEAD.
- Squad ejection on down (deferred to after the pass — `game._downed_pending`/`_process_downed_pending`); counter liveness (R7 — `PlanResolver._counter_actor_live` + `ResolvedOutcome.skipped`); the **main-action rule** (attack/rescue mutually exclusive, must follow a move); a **manual `RescueAction`** (+ `Unit.revive()` to 1 HP); the down/kill queue-icon preview; the 3-turn **downed countdown**.

**Stub / not built — where the redesign lands:**
- The **Will resource** — max/current on `UnitInstance`; the flat down-cost spend; maim-when-can't-afford; the display bar; `_select_lethal_rung` reading Will instead of just `OVERKILL_CEILING`.
- **Crisis Mode**, the **Rally** action, the **Law #2 down/maim preview text**, **maim effects**, between-battle recovery.

## The resource

- **Per-unit limb/integrity buffer.** Has a max and a current; spent, *not* regenerated in-battle. Own display bar under HP, different colour.
- **Max Will = innate WIL stat** ([stats.md](stats.md)) — an identity number, not grindable; shifts only via the authored/elective drift band. ~2–3 downs' worth for an average unit *(placeholder)*.
- **Persists between missions** ([#8](https://github.com/Phaazoid/Godoiosis/issues/8), on `UnitInstance`). Burnout is a campaign-level state paired with between-battle recovery (the Three Houses "motivation" feel).
- **It gates limbs, never life.** (The whole reframe.)

## The deterministic stakes ladder (Law #1)

A would-be-fatal hit, **sub-overkill**:

1. **Always DOWNED**, regardless of Will. The down **spends a flat cost `N`**.
2. **Can't afford `N` (Will < N) → down anyway, but MAIMED** — a limb is lost, Will floors at 0. Decided **at down-time** (so by the time you choose whether to revive, the limb is already gone or not). Maim is the *earned cost of fighting depleted*, not a separate rung.
3. **Overkill** (overshoot beyond remaining life exceeds the ceiling) → **dead outright** — now the *only* instant damage-death, so it carries more tuning weight than before.
4. **Downed + not rescued before the 3-turn countdown → dead.**

**Flat cost (not overshoot-scaled)** is deliberate: it keeps maim *depletion*-driven and legible (a unit is worth ~`Will / N` downs, and you can feel the cliff coming), and the overkill ceiling already supplies the "big hits are scary" drama — no need to bake it into the cost twice. (Overshoot-scaled cost is parked as a later knob.)

### Crisis Mode (opt-in gambit — the one home of permadeath)

The reframe made downing the *universal safe net*, so Crisis is **no longer a death-save** — it's a gambit for **power**, accessible only by flirting with death:

- **Offered via a live interrupt** at the moment a unit *would* go down — combat briefly freezes; accept or decline — but **only if the unit's Will is high** (likely an *absolute* threshold, making it an identity gate: only high-WIL units ever qualify).
- **Accept →** no down. Instead: **Will → 0**, **Will regen locked for the rest of the battle**, and a **short stat surge** (kept brief so it can't dominate).
- **For the rest of that battle there is no safety net** — no downs, no maims; **0 HP = permanent death.** You've traded your net for the whole fight. A very risky gambit.
- The **only door to the surge is accepting a near-death moment** — "berserk, but dangerous." Decline → a normal down.

**Why a live interrupt, not a pre-committed stance:** would-be-downs land on the *enemy's* turn (and mid-*your*-turn via counters), so there's no symmetric moment to pre-commit — the choice must be offered live, wherever it fires. It breaks **no design law**: no RNG (it's a *choice*, Law #1 intact); no surprise death (it's an *offered escape*, not a hidden outcome); and Law #2 governs *your planned queue*, while this fires during resolution playback. Its only real cost is the resolver's pure single-pass replay (pipeline R2/R3) — contain the ripple by applying the **surge from the unit's next turn**, so the current pass changes only by "survives standing," not a re-run of the damage math. NB: this introduces **player decisions during the enemy turn** — a new interaction beat, and the same seam future reaction/guard abilities would use.

## Generation & recovery

**In-fight: depletion-only.** Within a fight Will mostly moves one direction — *down*. That is the dread the system runs on ("watch Will drain toward the cliff"). The grill's key catch: **every in-battle generator fights that cliff** — a passive tick is a boring timer that trivializes downs; kills/combos snowball and feel gamey ("why does a kill restore your nerve to *not die*?"). So Will is not freely generated in combat. Two sanctioned exceptions:

- **Rally** — a **third main action** (beside Attack and Rescue; slots in like `RescueAction`, via `BaseAction.is_main_action()`). Consumes the unit's **entire turn** (main + move, in place — it forbids the pre-move, so the unit hunkers down where it stands). Restores Will toward a **partial cap only** (never to full), and **restores less on each successive use that battle** (diminishing returns). A safe pocket therefore *cannot* be milked to max — it's structurally impossible, so there's no need to police where/when players Rally. Lean on **scenario pressure** (objectives, advancing threats) to punish pure turtling — that's a level-design job. *(Optional flavour/limit: gate Rally to units near their leader — the old "leader inspiration" idea's natural home.)*
- The other in-fight relief valve is simply **rescue** — you recover *units* (drag the body back, fragile at 1 HP and low Will), not *nerve*.

**Between battles: full recovery (campaign layer — deferred).** Rest + a **task-assignment metagame**: benched units are assigned to tasks that recover Will (and other benefits), even running in parallel with a battle they weren't brought to. This is the true home of "generation" and an authored economy lever. It is its own design pass, later.

## Law #2 requirement (preview honesty) — NOT built

The attack preview **must surface** "this downs them," "no Will → maimed," and Crisis-eligibility — otherwise resolution produces surprise outcomes and breaks Law #2 / the no-surprise axiom. The down/kill **icon** preview exists; the **text form + the maim case** do not. Will / down / maim are **derived from the plan** (like counters), in the resolution pipeline's **Will stage (R7, after elemental)** — never stored player orders.

## Deferred — what a maim *does*

The mechanical effect of losing a limb is **undesigned**, and belongs with **prosthetics / aura / regrowth** ([progression.md](progression.md)). One forward-flag from the grill: the reframe makes maim **more reachable** than the old "rare exhausted rung" (it's now the standing cost of fighting depleted), so calibrate the effect for **semi-regular + meaningful-but-survivable**, not catastrophic.

## Abilities & threats (deferred layer, principles locked)

Will-driven abilities are their own later system. Locked principle: **thresholds and caps, never chance.** Captured ideas: **Iron Will** (deterministic damage cap), **Intimidation** (a *plannable* Will-drain aura — the deterministic answer to "the player shouldn't freely trust going-down"), **exact-lethal boss** (forces reliance on Crisis), **Will as leadership currency** (depends on the squad-pool fork), **Fortitude** (a regenerating pre-HP shield).

## Forks — status after the 2026-06-24 grill *(all provisional)*

1. ~~**Persist vs reset**~~ — **RESOLVED ([#8]): persists on `UnitInstance`.**
2. **Individual vs squad pool** — grill landed **per-unit, no pool** (everything designed is per-unit; a pool, if ever added, would be additive). *Provisional.*
3. **Attacking a downed unit** — **kill** (downed units rely on the AI *deprioritizing* them, not on invulnerability). *Provisional, unchanged.*
4. **Limb-loss scope** — **the maim rung only** (Crisis *kills*, it doesn't maim). *Provisional.*
5. ~~**Naming**~~ — **Will** (kept; it reads *better* under the limb-buffer framing — you spend it to stay whole, and out of it the body pays).

**Open / tuning knobs (all placeholders):** the flat down-cost `N`; max-Will magnitude; the Crisis Will-gate threshold (absolute vs fraction of max); the Rally partial cap + decay curve; the Crisis surge size and duration.

Cross-refs: [stats.md](stats.md), [progression.md](progression.md) (prosthetics / aura / regrowth), [squad-system.md](squad-system.md), [resolution-pipeline.md](resolution-pipeline.md) (the Will stage, R7), `../../CLAUDE.md` (Laws #1/#2).
