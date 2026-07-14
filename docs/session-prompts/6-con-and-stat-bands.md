# 6 — CON + stat bands + damage floor

**Size M · gameplay code (user types) · run before 7 (the bands feed the effective-stat spine).** Source: [stats.md](../design/stats.md) → "CON — ADOPTED 2026-07-06" + "The band doctrine".

```
Project: Iosis (tactical RPG, Godot 4.6, GDScript). Work in C:\Iosis\Godoiosis. Read CLAUDE.md first (collaboration contract: the user hand-types ALL gameplay code — deliver complete typed code blocks with file anchors and the why, verify by reading the real file after each step; sharp edges: enums are APPEND-ONLY once persisted, .tres data migrations are real). Then read docs/design/stats.md IN FULL — it is canon; do not redesign it. Code to read: Classes/core/Stats.gd, Classes/units/UnitInstance.gd, Classes/units/UnitData.gd, the damage path (Classes/actions/PlanResolver.gd + AttackAction.gd + Unit.take_damage), and Classes/squads/ for who reads LDR.

Goal: land the CON stat and the band doctrine — the stat-layer foundation everything after builds on.

All doc numbers are PLACEHOLDERS: implement each as a named constant, terse "# playtest-tunable" comment. Comment style is terse throughout (user preference).

1. CON INTO THE VOCABULARY. Append CON to Stats.Stat at the END (append-only — reordering corrupts every saved .tres) and to STAT_DEFAULTS (default 5). Update the header comment's roster note (input stats: STR/DEX/PER/CON).

2. MISSING-KEY FALLBACK. Existing UnitData .tres base_stats dictionaries have no CON key, and get_base_stat currently returns 0 for a missing stat — which would zero every existing unit's CON. Fix the seam: a missing key falls back to STAT_DEFAULTS[stat] (robust for every future append), and flag to the user the option of also migrating the unit .tres files to carry CON explicitly (their call; show diffs if so). Add a test proving a stat absent from the dict reads its default.

3. DAMAGE FLOOR AT ZERO. Damage clamps at 0, never negative — and 0 is a LEGAL outcome (stats.md CON riders; the min-1 chip rule was REVERSED 2026-07-11: 0-damage bait-outs are intended skill expression). Apply max(0, dmg) at the damage-computation seam — find the ONE place damage is computed (PlanResolver's predicted number and the executed number must come from the same calculation or Law #2 breaks; verify counters share it). A 0-damage hit is still a HIT — do not early-out on dmg == 0 anywhere in the resolution path (future one-use defensives/on-hit reactions must still consume/trigger). Add a test: an attack that would compute negative deals exactly 0, and the queue preview honestly shows 0.

4. THE BANDS as pure static helpers in Stats.gd (they must be readable from anywhere and trivially testable):
   - dex_mov_band(dex): 0–3 -> -1, 4–7 -> 0, 8+ -> +1 (constants; consumed in prompt 7, just land the function now).
   - con_mhp_band(con): small, extremes no more than 4–5 MHP apart end to end (pick a placeholder mapping, e.g. -2..+2 across the CON spread).
   - per_ldr_band(per): small (e.g. -1..+1).
   Wire the two live consumers now: max HP reads MHP base + con_mhp_band(CON) — introduce get_max_hp() on UnitInstance and migrate EVERY raw MHP read to it (grep for Stats.Stat.MHP; hover panel, set_current_hp clamp, revive, tests) so there is exactly one max-HP truth. Effective LDR = base + per_ldr_band(PER) wherever squad capacity reads LDR. Bands read BASE stats for now; prompt 7 reroutes them through effective stats.

5. WEIGHT READOUT (derived, never authored): get_weight() on UnitInstance = CON body term + placeholder 0 terms for gear/modules/inventory (prompts 7/10 fill them). Surface it in the inspect/hover panel if cheap. No consumers yet (pushability is elemental-side, later) — this is the seam.

6. DEF × CON SEAM (minimal). CON scales defensive gear as a MULTIPLIER WITH NO BASE — naked CON grants zero DEF (DEF stays gear-only, never on the statline). Land the formula at the effective-DEF seam with a test-fixture armor item (Classes/items/EquippableData.gd exists — extend, don't fork). Include the heavy-armor GATE stub (CON threshold to equip, mirroring how STR would gate heavy weapons). Armor CONTENT is a deferred pass — one fixture item is enough to test the math.

7. DEV EDITOR: the unit editor is reflection-based, so CON should appear automatically — verify, don't assume.

Do NOT touch: MOV derivation (prompt 7 owns it), limb slots, jobs, the STR->carry band (parked — stats.md "Open forks").

Done when: CON exists end-to-end (enum, defaults, fallback, editor), the 0-damage floor provably holds in preview AND execution (0 legal, negatives clamp), get_max_hp()/effective-LDR consume their bands, the Weight + DEF×CON seams exist with fixture-level tests, suite green, CLAUDE.md stat-registry line updated if wording went stale, committed.
```
