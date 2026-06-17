# Progression Model — Leveling Replacement

**Status: WORKING DESIGN (agreed direction, open questions flagged).** Decided 2026-06-15 with the developer; a couple of forks pending a co-dev chat. Not settled like the squad spec, but the core stance (no leveling, fixed stats) is firm. Supersedes the wiki's `Stats Overview.docx` leveling section (random stat-on-level-up — dead under Law #1).

## Core stance

- **No XP / no leveling.** Units do not gain levels or level-up stat growth.
- **Stats are fixed. No stat training (benched 2026-06-15).** A unit *is* its statline. (This reverses an earlier idea of training Will/Leadership — cut because trainable stats risk late-game immortality, and trainable **LDR** especially would break squads: squad range and squad size key off LDR, so boosting it = runaway squad power. Squads are already the strongest tool in the game.)
- **Progression is horizontal:** power lives in **augmentation, skill, and relationships**, never in an intrinsic unit level. A late-recruited unit is never "20 levels behind" — only gear/proficiency/connections behind, all bounded and partly transferable.

Why this fits Iosis: matches the top axiom *"setting up the battle should be half the fun"* (prep, not a between-battle slot machine), honors **Law #1** (the old level-up RNG is gone), and keeps late units + the planned roguelike side-mode usable.

## The growth axes

1. **Gear** — weapons, stat-boosting armor, upgrades.
2. **Prosthetics** — the mechanist↔alchemist axis (below).
3. **Weapon proficiency** (mechanist-leaning) and **aura points / runes** (alchemist-leaning) — grown via *training goals* (below).
4. **Squad connections** — relational bonuses (e.g., LDR familiarity). Additive, **never decaying**, and **plot-seedable** (a story-introduced "old friend of X" arrives pre-connected — no grind, and it keeps connection bonuses from locking your roster).

## Proficiency training goals (anti-grind growth)

- A unit sets a **training goal**, **locked at mission start** (can't change mid-mission).
- With a goal set, the unit gains proficiency **up to a per-mission cap** each time it "does the thing." Past the cap, extra reps do nothing → **grinding is mechanically pointless** (the strongest form of the wiki's "grind a chainsword army → just stupid" stance).
- **Benched units with a goal** get slower automatic training during missions they sit out → no bench-rot, shrinks the late-unit gap. Fielding trains faster → an **"attention economy"**: focus is the soft resource you spend.
- **Tier thresholds** (focused missions to reach the next tier) are a **dev-controlled difficulty dial**, independent of the economy.
- Proficiency tiers **unlock new secondary attacks / attack patterns** (qualitative growth; drops onto the existing `AttackPattern` resources) — a primary "feels-good" beat. Aura points may grant **damage multipliers** — keep **modest**; large multipliers are vertical power that rebuilds a power curve and a late-unit gap.

Open: what counts as "doing the thing"; the no-opportunity case (partial fill vs nothing); D&D-style sticky commitment → preferred form is "momentum" (same goal ramps the rate, switching resets the *rate* but never loses accrued proficiency; harsh switch penalties would rebuild the grind wall). The proficiency/abilities layer is its own system to design later.

## Mechanist ↔ Alchemist = one augmentation axis

Resolves the wiki's open question *"Alchemists == Mechanists??"* — not two classes, two ends of **how augmented a unit's body is.**

- **Prosthetics raise physical stats.** Lose a limb → lose that limb's stat contribution; a prosthetic restores it and is **upgradable** (a pricey stat-raising path — and the *only* sanctioned way to exceed a unit's fixed natural statline). Arms → Str; legs → Spd/Dex. (Granularity — other parts/stats — TBD.)
- **Replacing natural limbs lowers natural aura capacity.** Chroming up (mechanist) trades aura for physical power. Full-flesh = max aura (alchemist end); heavily-augmented = strong physical, little aura (mechanist end). Every unit sits somewhere on this line and slides by choosing what to replace.
- **Natural-limb regrowth** (alchemical) is the alchemist's out: regrow a *natural* limb — **pricier, slower, more resource-intensive** than a prosthetic, but it **preserves aura / the alchemist build**. The escape hatch when a favorite alchemist is maimed and you don't want to respec them mechanist.
- *How* a limb is lost (involuntary maiming vs elective amputation) lives in [will-and-death.md](will-and-death.md).

## Economy = dev lever, not grind

- **Scrap / materia are authored.** Each mission grants exactly what the designer placed, on a drawn curve. The **single-player, play-through-once campaign** makes a faucet-free economy trivial → **nothing to grind, by construction.**
- The **roguelike side-mode** is where a faucet (random/farmable) economy belongs, and where customized campaign units can be imported. Because there's no leveling, a **stock unit's floor is fully playable** → the mode is never locked behind deep customization (customization is upside, not a tax). Watch: keep customized power from outclassing stock too hard (favor sidegrades; the mode may normalize/scale to incoming power).

## Two non-grind difficulty dials

1. **Authored economy** — gear / materia / prosthetic access.
2. **Proficiency & aura tier pacing** — missions-to-tier thresholds.

## Open questions

- Proficiency "doing the thing" trigger + no-opportunity case; momentum vs flat goals.
- Body-part granularity and which stat each part feeds.
- Roguelike power-normalization for imported units.
- See [will-and-death.md](will-and-death.md) for the Will / limb-loss forks.

## Captured ideas — wiki scratchpad (2026-06-17, unsorted)

Noted from `Scratchpad` during the #32 triage; not yet integrated decisions:

- **Randomness in *upgrades* is allowed; randomness in *combat* is not.** Law #1 governs the battlefield — but offering a **random subset of choices** when a proficiency/weapon advances (à la *Mewgenics*) is fine, and even encourages experimentation. The meta-layer may roll dice; the turn never does.
- **Optional job/class-lite layer.** Classless-first stays the default, but an adopted "job" (spend X resource → role Z) could grant a flat stat change / stat caps (a tank caps movement) plus a trainable ability pool, swappable if you re-qualify. *"Even in a classless society, people have jobs."*
- **Double-attacks as a weapon property, not a stat rule.** Rather than FE's speed-derived doubling, make multi-hit a property of specific weapons, **gated** by stats (better stats → more uses) — keeps growth horizontal.
- **Fixed stats shouldn't force weapon pairings.** A consequence of the fixed-stat stance: since weapons scale off a stat, optimal play risks **locking each character to one weapon type**. Candidate outs (detailed in [weapons.md](weapons.md)): weapon **mods/variants that change the scaling stat**, or **sub-varieties** of each family with differing set scalings — so customization stays meaningful and no single weapon is always best for a statline.

Cross-refs: [will-and-death.md](will-and-death.md), [squad-system.md](squad-system.md), [weapons.md](weapons.md), `../../CLAUDE.md` (design laws).
