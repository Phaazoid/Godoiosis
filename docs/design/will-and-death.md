# Will & Death — "The Art of Not Dying"

**Status: WORKING DESIGN (agreed direction, open questions flagged).** Decided 2026-06-15; structural forks deferred to a dev/co-dev chat (marked below). Builds on the implemented **death mechanical floor** (`Unit.unit_died` fan-out). Supersedes the wiki's random-dismemberment framing (`Deprecated documents/Death.docx`, old `Stats Overview`) — every "% chance to maim/break" is dead under Law #1.

## Naming note

"Will" is **provisional.** "Out of Will → you lose a limb" doesn't read intuitively (low willpower shouldn't amputate an arm). Candidate rename: **Tenacity** — or reframe the fiction so the resource = a unit's capacity to *cling to life / endure*, and when it's spent the body pays instead. **Mechanics are accepted; the name/fiction is open.**

## Will is an expendable resource

- **HP-like.** Has a **max** and a **current**; current is built and spent. Own display bar under HP, different color.
- **Max Will is innate per unit** — a **capacity stat** on the statline (see [stats.md](stats.md)): an identity number, not a progression one. Not trainable/grindable; it may shift only via authored/elective events within the bounded drift band (per [stats.md](stats.md) / [progression.md](progression.md)).
- **Built** via squad activity (leader inspiration) and combos. **Lost** via expenditure and enemy **intimidation**.
- Ability rungs gate on **max-Will thresholds** (an identity gate, since max is fixed).

## The deterministic stakes ladder (no randomness — Law #1)

How a unit handles a would-be-fatal hit, by how much Will it has:

1. **Will in the tank → go DOWNED (safe).** Spend Will; drop to downed — can't move or attack; enemies **deprioritize** downed units (a standing unit is the bigger threat). Recoverable.
2. **Will exhausted → survive by MAIMING.** A fatal hit with no Will to spend costs a **limb** instead of a life → aura loss → prosthetic *or* alchemical regrowth (see progression.md). The **involuntary** door to prosthetics. Crucially, **limb-loss is the *exhausted* rung — rare and earned, NOT every down** (this was the dev's main worry; the ladder answers it).
3. **Overkill ceiling → just dead.** If a hit exceeds remaining life by more than X, it kills outright regardless of Will (so low-Will units aren't immortal).
4. **CRISIS MODE (opt-in) → the one home of permadeath.** Instead of downing, a unit may choose Crisis: a **stat surge**, but **Will → 0** and **death while in Crisis is permanent**. Permadeath isn't removed from the game — it's *reserved* for a desperate, eyes-open choice. Deterministic and telegraphed. (Wiki upgrade ideas — bigger surge, longer duration, Will floor of 1 not 0 — fold into the later abilities system.)

Stakes escalate with how depleted a unit is → this *is* the "punish risky play / don't abuse the safety net" pressure, achieved **deterministically** rather than with the floated random down/maim roll.

### Why deterministic, not a "going-down" dice roll

The dev floated keeping random chance for going down (it wouldn't touch the action queue, so Law #2 is safe). Rejected: it collides with **Law #1** and the axiom *"outcomes have predictable bounds — it won't be a surprise if someone dies."* In a deterministic tactics game the punishment for risk is **the math catching up** (finite Will → a visible cliff), not a coin flip. The dread comes from *watching Will deplete with the cliff in view*; randomness would let reckless play occasionally get lucky — determinism never does.

## Downed state

- **Attacking a downed unit kills it.** (Open: a deterministic "maim instead of kill" was floated — if pursued, threshold-based, never a chance.)
- **Rescue sub-game (strong idea):** a downed unit must be **reached by a squadmate within X turns** or it's lost/captured. Overextending a **lone** unit = it goes down beyond rescue = **deterministic doom** (foreseeable, the player's fault). Turns downing into *gameplay* — the squad collapses to defend the body — instead of a flat penalty. Lone-down = dire; squad-down = a fight worth having. (Intersects the individual-vs-squad Will fork.)
- Higher-max-Will downed perks from the wiki (get up after X turns, move 1–2 while down, guard allies, larger insta-kill buffer, stay down indefinitely) — **deferred to the abilities system**, de-randomized.

## Law #2 requirement (preview honesty)

The attack preview **must surface Will outcomes**: "this downs them," "no Will left → lethal," "this costs a limb." Otherwise resolution produces surprise deaths and breaks both queue-honesty (Law #2) and the no-surprise axiom. This is what the wiki's *Precombat Informational Popup* is for. Will / down / maim / Crisis are **derived consequences computed from the plan** (like counters) — never stored player orders.

## Abilities & threats (deferred layer, principles locked)

Will-driven abilities are **their own system to design later.** Locked principle: **thresholds and caps, never chance.** Captured ideas:

- **Iron Will** — deterministic damage cap (a hit above X is reduced to Y).
- **Intimidation** — a known **Will-drain aura** (enemy/boss/squad ability). Makes the safety net conditionally unreliable *in a plannable way* (you can see the intimidator). The deterministic answer to "the player shouldn't freely trust going-down."
- **Exact-lethal boss** — always deals precisely lethal damage → forces reliance on Crisis Mode. A deterministic set-piece.
- **Will as leadership currency** — a leader spends squad Will to trigger squad reactions (guard, reposition, drag a downed ally) → Will as a tactical resource, not only a death-buffer. (Depends on the individual-vs-squad fork.)
- **Fortitude** — a regenerating shield broken before HP; possibly a squad ability. (May overlap Will-as-second-health — reconcile later.)

## Open forks (need dev + co-dev)

1. **Persist vs reset:** does Will carry between missions (Three Houses "motivation" — burned-out units need recovery, a campaign-level resource that pairs with the authored economy) or reset each mission (simpler)?
2. **Individual vs squad-pooled Will** (or both): personal grit vs the squad's collective nerve. Leans on fork 1. *(Stats session 2026-06-20 leans **per-unit, squad-fed** — personal stakes, but the squad refills the pool; revisit in playtest.)*
3. **Downed-attack outcome:** straight kill (current lean) vs a deterministic maim option.
4. **Limb-loss scope:** only the Will-exhausted rung, or also a possible Crisis consequence?
5. **Naming:** Will → Tenacity, or a reframed fiction.

Cross-refs: [stats.md](stats.md), [progression.md](progression.md) (prosthetics / aura / regrowth), [squad-system.md](squad-system.md), `../../CLAUDE.md` (laws).
