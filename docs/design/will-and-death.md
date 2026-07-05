# Will & Death — "The Art of Not Dying"

> **⚠️ PROVISIONAL (redesigned 2026-06-24, solo grill-me session). NOT playtested.** Everything below the [Implementation status](#implementation-status) section came out of design conversation and is expected to shift in playtest. The numbers (`N`, max Will, Crisis gate, Rally cap, surge) are placeholders, **pseudo-locked as built**. Tracked in [#33](https://github.com/Phaazoid/Godoiosis/issues/33).
>
> **Co-dev grilled 2026-07-04 (Fable 5 session):** the open forks are now resolved or deliberately punted — **maim effects designed (the limb-slot model)**, which-limb = fixed-rotation placeholder (prosthetics last), transmutation **strain = affordability-gated cost** (never touches the lifecycle), **AI Crisis = per-archetype stances**. See the sections below; none of it is built yet.

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

**Built 2026-06-25 — the Will resource (provisional; Claude-guided / user-typed, [#33](https://github.com/Phaazoid/Godoiosis/issues/33)):**
- `UnitInstance.current_will` (max = the WIL stat, capped at `MAX_WILL = 20`), the **flat down-cost spend** (`DOWN_WILL_COST = 5`) at `_go_downed`, **maim-when-can't-afford** (`maimed_part` enum splitting L/R arm+leg, default `ARM_RIGHT`), the **Law #2 down/maim/kill preview** (`ResolvedOutcome.Lethality.MAIMED` threaded through `PlanResolver`; icon `DownMaim.png` + text), the **Will readout** (hover status icons + inspect text), and the **`RallyAction`** (a regular main action — see Rally below).

**Built (verified in code 2026-07-01) — Crisis Mode:** the live interrupt polled between hits (`game._offer_pending_crisis`) — a FULL-Will unit that would go down gets the `CrisisPrompt`; accept → back up at 5 HP with a one-turn +5 scaling-stat surge, Will locks at 0, any later would-be-down is death for the battle. AI factions auto-accept without the prompt (provisional policy).

**Stub / not built:**
- **Maim effects** (what losing the limb *does* — deferred to progression.md); **between-battle recovery**; the deterministic **which-limb** choice (hard-coded ARM today); a smarter **AI Crisis policy** than auto-accept.

## The resource

- **Per-unit limb/integrity buffer.** Has a max and a current; spent, *not* regenerated in-battle. Own display bar under HP, different colour.
- **Max Will = the innate WIL stat** ([stats.md](stats.md)), **capped at `MAX_WILL = 20`** (`min(WIL, 20)`) — an identity number, set per-unit (incl. via the dev editor), shifting only via the authored/elective drift band. Default WIL ≈ 5, so bump it for a deep pool. ~4 downs' worth at WIL 20 / cost 5. (Shown on its own HP/WIL line, not as a stat row.)
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

**AI Crisis policy (grilled 2026-07-04): stance keys off the archetype.** RUSHDOWN = always accept; HOLD / SENTRY = never (starting table — every new archetype declares its stance at authoring time). Replaces the shipped auto-accept-for-all stopgap. **The balance lever is authored enemy WIL:** early-level enemies simply don't carry enough Will to hit the gate, so Crisis never fires; in later levels the player *scouts* dangerous enemies by their visible stats — Will included (the inspect readout already shows it). Deterministic → previewable: **Law #2 TODO** — a would-be-down on a Crisis-eligible enemy must preview as CRISIS (they stand back up surged), not DOWNS, or the queue icon lies.

## Generation & recovery

**In-fight: depletion-only.** Within a fight Will mostly moves one direction — *down*. That is the dread the system runs on ("watch Will drain toward the cliff"). The grill's key catch: **every in-battle generator fights that cliff** — a passive tick is a boring timer that trivializes downs; kills/combos snowball and feel gamey ("why does a kill restore your nerve to *not die*?"). So Will is not freely generated in combat. Two sanctioned exceptions:

- **Rally** — a **third main action** (beside Attack and Rescue; via `BaseAction.is_main_action()`). **As built (2026-06-25, simplified per dev call): a *regular* main action** — Move-then-Rally is allowed (no hunker-in-place), restoring a **flat diminishing amount** (`RALLY_BASE = 6`, then −`RALLY_FALLOFF = 2` per use that battle, dropped once it would give < 1), clamped to max. `rally_count` is battle-scoped (resets each mission, lives on the transient `Unit`). *Fuller vision (deferred):* consume the whole turn in place and restore only toward a **partial cap** (never full) so a safe pocket can't be milked — for now the diminishing amount + the max clamp do that job. Lean on **scenario pressure** to punish pure turtling (level-design). *(Optional later: gate Rally to units near their leader — the old "leader inspiration" idea's home.)*
- The other in-fight relief valve is simply **rescue** — you recover *units* (drag the body back, fragile at 1 HP and low Will), not *nerve*.

**Between battles: full recovery (campaign layer — deferred).** Rest + a **task-assignment metagame**: benched units are assigned to tasks that recover Will (and other benefits), even running in parallel with a battle they weren't brought to. This is the true home of "generation" and an authored economy lever. It is its own design pass, later.

> **Captured idea (2026-06-26, from the scratchpad — not locked):** tie Will generation to **aura / temperament**. Every unit has an aura and a **primary aura type** ([alchemy-kit.md](alchemy-kit.md)), which could map to a **temperament**; units would then generate Will *differently by temperament*, in and out of battle. The promising twist for the between-battle layer: maybe there's **no dedicated "recover Will" task** at all — instead the *ordinary* task-assignments you'd make anyway yield **more or less Will per unit by temperament**, so the recovery economy falls out of normal assignment choices rather than a grindy Will-farm chore (honors the anti-grind rubric, [progression.md](progression.md)). Could also give temperament an in-battle flavour hook (e.g. who Rallies well).

## Law #2 requirement (preview honesty) — NOT built

The attack preview **must surface** "this downs them," "no Will → maimed," and Crisis-eligibility — otherwise resolution produces surprise outcomes and breaks Law #2 / the no-surprise axiom. The down/kill **icon** preview exists; the **text form + the maim case** do not. Will / down / maim are **derived from the plan** (like counters), in the resolution pipeline's **Will stage (R7, after elemental)** — never stored player orders.

## The limb-slot model — what a maim does (grilled 2026-07-04)

**Limbs are equipment slots, and the natural limb is the default gear.** Designed at the 2026-07-04 co-dev grill (not built):

- **Each arm slot** holds a natural arm (**arm STR = the unit's innate STR**), nothing (0), or a **prosthetic** (its own built-in STR + special effects). **Effective STR = the mean of the two arm slots, rounded UP** — a 7-STR unit maimed reads 4; a STR-10 prosthetic on that unit reads 9. Prosthetics can exceed the natural ceiling — the mechanist augmentation fantasy, landing exactly where [progression.md](progression.md) wants it.
- **Legs are fully symmetric with MOV** (natural leg = innate MOV; mean of leg slots, rounded up). One rule, four slots. Prosthetic legs can exceed baseline (pinned content ideas: rocket jumps, knee cannon).
- **Verb locks stack on top** (provisional set): any missing arm → **two-handed/heavy patterns locked** + **rescue-carry locked**; off-hand gear interactions TBD with the equipment pass. Legs carry no extra verb — the MOV averaging is the effect.
- **Multi-maim is allowed** (`maimed_part` becomes a set of flags) and **never escalates to death** — a fully-maimed unit still just downs; "Will never kills" stays absolute. Half STR, half MOV, and no verbs is its own signal to bench and repair.
- **Which limb: fixed rotation, natural limbs first** — placeholder order *weapon arm → off leg → off arm → weapon leg*, always shown on the unit panel ("next at risk"). **Prosthetics are targeted only when no natural limb remains, and a maimed prosthetic is recoverable gear** — the part detaches to inventory (the investment survives; refit between battles). Flesh pays first — equivalent exchange. *Punt recorded:* damage-source-derived limb selection (melee→arm, terrain/AoE→leg) is liked but implementation-heavy — a future candidate, not the plan.
- Calibration goal unchanged: maims are semi-regular (the standing cost of fighting depleted), so **meaningful-but-survivable, never catastrophic**.
- **Rider for the stats session:** prosthetics wanting to grant defensive buffs is a second vote for reopening the **CON cut** (first vote logged in the scratchpad dispersal, 2026-06-26). Decide at a stats session, not here.

## Transmutation strain — the cross-system rule (2026-07-04)

Brute-force channeling ([transmutation-model-proposal.md](transmutation-model-proposal.md) → *Temper & channeling*) costs recoil HP — and that recoil is a **cost, not damage**: **affordability-gated like the Will down-cost.** If the strain would leave the caster at 0 or below, they *cannot pay* — the option greys out in battle (materia is the designed workaround). Strain never touches `take_damage`, never downs, never maims, never triggers Crisis. No self-down gambit, no 1-HP free-cast exploit, no special case in the damage path. (In-battle affordability greying is NOT the codex — the discovery table never greys anything out, per transmutation doctrine #2.)

## Abilities & threats (deferred layer, principles locked)

Will-driven abilities are their own later system. Locked principle: **thresholds and caps, never chance.** Captured ideas: **Iron Will** (deterministic damage cap), **Intimidation** (a *plannable* Will-drain aura — the deterministic answer to "the player shouldn't freely trust going-down"), **exact-lethal boss** (forces reliance on Crisis), **Will as leadership currency** (depends on the squad-pool fork), **Fortitude** (a regenerating pre-HP shield).

## Forks — status after the 2026-06-24 grill *(all provisional)*

1. ~~**Persist vs reset**~~ — **RESOLVED ([#8]): persists on `UnitInstance`.**
2. **Individual vs squad pool** — grill landed **per-unit, no pool** (everything designed is per-unit; a pool, if ever added, would be additive). *Provisional.*
3. **Attacking a downed unit** — **kill** (downed units rely on the AI *deprioritizing* them, not on invulnerability). *Provisional, unchanged.*
4. **Limb-loss scope** — **the maim rung only** (Crisis *kills*, it doesn't maim). *Provisional.*
5. ~~**Naming**~~ — **Will** (kept; it reads *better* under the limb-buffer framing — you spend it to stay whole, and out of it the body pays).

**Open / tuning knobs (placeholders; current values in parens — all pseudo-locked as built, playtest-tunable):** the flat down-cost `N` (**5**); max-Will magnitude (**= WIL stat, capped at 20**); the Rally base + falloff (**6, −2, floor at <1**); the Crisis Will gate (**full Will as built**) and surge (**+5 scaling stat, one turn, back at 5 HP**). *Resolved 2026-07-04:* which-limb = fixed rotation placeholder, natural limbs first, prosthetics recoverable (see the limb-slot model); AI Crisis = archetype stances. *Design debt from the grill:* crisis-aware lethality preview (Law #2); `maimed_part` single value → set of flags; the limb-slot STR/MOV derivation itself.

Cross-refs: [stats.md](stats.md), [progression.md](progression.md) (prosthetics / aura / regrowth), [squad-system.md](squad-system.md), [resolution-pipeline.md](resolution-pipeline.md) (the Will stage, R7), `../../CLAUDE.md` (Laws #1/#2).
