# Will & Death — "The Art of Not Dying"

**Status: PARTLY BUILT — the unblocked scaffold landed 2026-06-21 (committed to `main`); the Will resource itself is still a stub.** Design decided 2026-06-15; structural forks deferred to a dev/co-dev chat (marked below), though two now have provisional in-code calls. See **[Implementation status](#implementation-status-scaffold-landed-2026-06-21)** for exactly what is in code vs design-only. Builds on the implemented **death mechanical floor** (`Unit.unit_died` fan-out). Supersedes the wiki's random-dismemberment framing (`Deprecated documents/Death.docx`, old `Stats Overview`) — every "% chance to maim/break" is dead under Law #1.

## Implementation status (scaffold landed 2026-06-21)

The **unblocked half** of the ladder is built — hand-typed, working, **uncommitted on `main`**, with gdUnit coverage for the two rules most likely to regress (`tests/squad/test_main_action_ordering.gd`, `test_rescue_validation.gd`). The **Will resource itself is NOT built**: the rung selector keys off a flat `Unit.OVERKILL_CEILING` constant, *not* spent Will. Tracked in [#33](https://github.com/Phaazoid/Godoiosis/issues/33).

**In code** — all on the *transient* `Unit`, nothing on `UnitInstance` yet:
- **Lifecycle state machine** — `Unit.LifecycleState {ACTIVE, DOWNED, DEAD}` (`is_active()` / `is_downed()`). `take_damage()` owns the fork: survivable → apply damage; would-be-fatal → `_select_lethal_rung()` → **DOWN** (cling at 1 HP, `_go_downed()`) or, past the overkill ceiling, straight **DEAD**. `_go_downed()` swaps to the downed sprite and emits `went_downed`.
- **Squad ejection on down** — `SquadManager.handle_unit_downed()` boots the unit to a solo squad; it can no longer be ordered (`can_control` + `queue_action` both reject a non-`is_active()` actor). Ejection is **deferred** to after the execution pass (`game._downed_pending` + `_process_downed_pending`) — restructuring squads mid-`execute` was buggy.
- **Counter liveness (R7 / Law #2)** — a unit downed or killed earlier in a resolution pass no longer fires its already-resolved counter: `PlanResolver._counter_actor_live()` reads the threaded hypothetical HP, `ResolvedOutcome.skipped` no-ops the playback, and the queue preview hides it.
- **"Main action" rule** — attack and rescue (and any future main type) are mutually exclusive, one per unit per turn (`BaseAction.is_main_action()`, `Unit.has_main_action_queued()`), and a **main action must come after a move, never before** (locking a main action removes the move option). Closes an attack-then-flee / dodge-the-counter exploit. Enforced at the menu *and* `SquadManager.queue_action`.
- **Manual Rescue** (`RescueAction` + `Unit.revive()`) — see [Downed state](#downed-state); this is a deliberate **divergence** from the timed sub-game described there.

**Stubbed / deferred (still design-only below):**
- **Will resource** — max/current on `UnitInstance`, build/spend, the display bar, and the rung selector reading Will instead of `OVERKILL_CEILING`. Nothing yet.
- **The Law #2 Will preview** ("downs them" / "no Will → lethal" / "costs a limb") — not built; the preview is silent on Will outcomes.
- **Maiming**, **Crisis Mode**, **Will abilities** (Iron Will, Intimidation) — not built.
- **Timed-countdown rescue** ("reach within X turns or it's lost") — stood in for, for now, by the manual rescue; the generic turn-scoped timed state it needs isn't built.

**Provisional in-code calls** (working assumptions — revisit in playtest / the fork chat):
- **Fork 2** (individual vs squad-pooled Will): **per-unit only, no pool** for now.
- **Fork 3** (downed-attack): **kill**.
- **Maiming deferred** entirely.
- A **rescued unit is spent** the turn it's raised (`squad.has_acted = true`) and does **not** auto-rejoin its old squad — a candidate Will hook later.

## Naming note

"Will" is **provisional.** "Out of Will → you lose a limb" doesn't read intuitively (low willpower shouldn't amputate an arm). Candidate rename: **Tenacity** — or reframe the fiction so the resource = a unit's capacity to *cling to life / endure*, and when it's spent the body pays instead. **Mechanics are accepted; the name/fiction is open.**

## Will is an expendable resource

- **HP-like.** Has a **max** and a **current**; current is built and spent. Own display bar under HP, different color.
- **Max Will is innate per unit** — a **capacity stat** on the statline (see [stats.md](stats.md)): an identity number, not a progression one. Not trainable/grindable; it may shift only via authored/elective events within the bounded drift band (per [stats.md](stats.md) / [progression.md](progression.md)).
- **Persists between missions (decided 2026-06-21, #8).** Both max (innate) and current Will live on **`UnitInstance`** — the persistent-identity store — *not* the transient combat `Unit`. A unit carries its spent/built Will forward: burnout becomes a campaign-level state that pairs with recovery and the authored economy. (Storage boundary formalized in [resolution-pipeline.md](resolution-pipeline.md), "The persistence seam.")
- **Built** via squad activity (leader inspiration) and combos. **Lost** via expenditure and enemy **intimidation**.
- Ability rungs gate on **max-Will thresholds** (an identity gate, since max is fixed).

## The deterministic stakes ladder (no randomness — Law #1)

How a unit handles a would-be-fatal hit, by how much Will it has:

> **Build status (2026-06-21):** rungs 1 (DOWNED) and 3 (overkill → dead) are in code, but selected by the flat `OVERKILL_CEILING` stub rather than spent Will; rungs 2 (maim) and 4 (Crisis) are design-only. See [Implementation status](#implementation-status-scaffold-landed-2026-06-21).

1. **Will in the tank → go DOWNED (safe).** Spend Will; drop to downed — can't move or attack; enemies **deprioritize** downed units (a standing unit is the bigger threat). Recoverable.
2. **Will exhausted → survive by MAIMING.** A fatal hit with no Will to spend costs a **limb** instead of a life → aura loss → prosthetic *or* alchemical regrowth (see progression.md). The **involuntary** door to prosthetics. Crucially, **limb-loss is the *exhausted* rung — rare and earned, NOT every down** (this was the dev's main worry; the ladder answers it).
3. **Overkill ceiling → just dead.** If a hit exceeds remaining life by more than X, it kills outright regardless of Will (so low-Will units aren't immortal).
4. **CRISIS MODE (opt-in) → the one home of permadeath.** Instead of downing, a unit may choose Crisis: a **stat surge**, but **Will → 0** and **death while in Crisis is permanent**. Permadeath isn't removed from the game — it's *reserved* for a desperate, eyes-open choice. Deterministic and telegraphed. (Wiki upgrade ideas — bigger surge, longer duration, Will floor of 1 not 0 — fold into the later abilities system.)

Stakes escalate with how depleted a unit is → this *is* the "punish risky play / don't abuse the safety net" pressure, achieved **deterministically** rather than with the floated random down/maim roll.

### Why deterministic, not a "going-down" dice roll

The dev floated keeping random chance for going down (it wouldn't touch the action queue, so Law #2 is safe). Rejected: it collides with **Law #1** and the axiom *"outcomes have predictable bounds — it won't be a surprise if someone dies."* In a deterministic tactics game the punishment for risk is **the math catching up** (finite Will → a visible cliff), not a coin flip. The dread comes from *watching Will deplete with the cliff in view*; randomness would let reckless play occasionally get lucky — determinism never does.

## Downed state

- **Attacking a downed unit kills it.** **[BUILT — this is the in-code Fork 3 call: kill.]** (Open: a deterministic "maim instead of kill" was floated — if pursued, threshold-based, never a chance.)
- **Rescue sub-game (strong idea):** a downed unit must be **reached by a squadmate within X turns** or it's lost/captured. Overextending a **lone** unit = it goes down beyond rescue = **deterministic doom** (foreseeable, the player's fault). Turns downing into *gameplay* — the squad collapses to defend the body — instead of a flat penalty. Lone-down = dire; squad-down = a fight worth having. (Intersects the individual-vs-squad Will fork.)
  - **[BUILT — but as a *manual* rescue, NOT this timed countdown.]** What's in code: an adjacent ally spends its **main action** on **Rescue** (`RescueAction`) → the downed unit stands up (`Unit.revive()`, ACTIVE at 1 HP). No turn timer, no capture-on-timeout, no "beyond rescue" doom yet — those need the generic turn-scoped timed state, which isn't built. The rescued unit is **spent that turn** and does **not** auto-rejoin its old squad. Full flow: adjacency-gated menu option → targeting + hover feedback → queue preview → execution phase → re-validation in `_validate_action_list_once` (a re-planned move that breaks adjacency, or a target picked up first, invalidates the queued rescue).
- Higher-max-Will downed perks from the wiki (get up after X turns, move 1–2 while down, guard allies, larger insta-kill buffer, stay down indefinitely) — **deferred to the abilities system**, de-randomized.

## Law #2 requirement (preview honesty)

> **[NOT BUILT yet.]** Counter liveness is wired into the preview (a counter that won't fire is hidden), but the Will/down/maim outcomes below are not — the preview is currently silent on them. This is the first thing the Will resource stage must add, or downing produces exactly the surprise deaths Law #2 forbids.

The attack preview **must surface Will outcomes**: "this downs them," "no Will left → lethal," "this costs a limb." Otherwise resolution produces surprise deaths and breaks both queue-honesty (Law #2) and the no-surprise axiom. This is what the wiki's *Precombat Informational Popup* is for. Will / down / maim / Crisis are **derived consequences computed from the plan** (like counters) — never stored player orders.

## Abilities & threats (deferred layer, principles locked)

Will-driven abilities are **their own system to design later.** Locked principle: **thresholds and caps, never chance.** Captured ideas:

- **Iron Will** — deterministic damage cap (a hit above X is reduced to Y).
- **Intimidation** — a known **Will-drain aura** (enemy/boss/squad ability). Makes the safety net conditionally unreliable *in a plannable way* (you can see the intimidator). The deterministic answer to "the player shouldn't freely trust going-down."
- **Exact-lethal boss** — always deals precisely lethal damage → forces reliance on Crisis Mode. A deterministic set-piece.
- **Will as leadership currency** — a leader spends squad Will to trigger squad reactions (guard, reposition, drag a downed ally) → Will as a tactical resource, not only a death-buffer. (Depends on the individual-vs-squad fork.)
- **Fortitude** — a regenerating shield broken before HP; possibly a squad ability. (May overlap Will-as-second-health — reconcile later.)

## Open forks (need dev + co-dev)

1. ~~**Persist vs reset**~~ — **RESOLVED 2026-06-21 (#8): Will PERSISTS between missions**, stored on `UnitInstance` (the persistent-identity store). Burned-out units carry depletion forward (Three Houses "motivation"): a campaign-level resource paired with recovery + the authored economy. The transient↔persistent boundary is formalized in [resolution-pipeline.md](resolution-pipeline.md). *(Fork number kept — other docs cite forks by number.)*
2. **Individual vs squad-pooled Will** (or both): personal grit vs the squad's collective nerve. *(Fork 1 now decided — per-unit Will persists on `UnitInstance`; this fork is only whether a squad-level pool **also** exists, which would be additive, not a relocation. Stats session 2026-06-20 leans **per-unit, squad-fed** — personal stakes, but the squad refills the pool; revisit in playtest.)* **Scaffold provisional: per-unit only, no pool.**
3. **Downed-attack outcome:** straight kill (current lean) vs a deterministic maim option. **In code now: kill.**
4. **Limb-loss scope:** only the Will-exhausted rung, or also a possible Crisis consequence?
5. **Naming:** Will → Tenacity, or a reframed fiction.

Cross-refs: [stats.md](stats.md), [progression.md](progression.md) (prosthetics / aura / regrowth), [squad-system.md](squad-system.md), `../../CLAUDE.md` (laws).
