# 10 — Weapon parts: spaces, modules, proficiency stub, prototypes

**Size L · gameplay code (user types) · after 7 (module Weight feeds the readout); independent of 9.** Source: [weapons.md](../design/weapons.md) → "Ratified model (2026-07-06 grill)" + module bank [weapon-mod-ideas.md](../design/weapon-mod-ideas.md). Synergy: dev-tool work here overlaps issue [#51](https://github.com/Phaazoid/Godoiosis/issues/51).

```
Project: Iosis (tactical RPG, Godot 4.6, GDScript). Work in C:\Iosis\Godoiosis. Read CLAUDE.md first (collaboration contract: user hand-types ALL gameplay code — complete typed code blocks + anchors + why; sharp edge: ALWAYS duplicate(true) when granting weapons — shallow duplicate shares the nested attack_pattern). Then read docs/design/weapons.md IN FULL as canon (the "Ratified model" section is the spec) and skim docs/design/weapon-mod-ideas.md (the authored module bank — pull 3-4 simple entries as fixture content, don't build the whole bank). Reference docs/design/stats.md "the scaling contract" (~10% nudges; re-points are prototype territory). Code to read: Classes/weapons/WeaponData.gd + WeaponCatalog.gd, Classes/items/Item.gd + EquippableData.gd, Classes/units/CombatComponent.gd (how the equipped weapon is consumed), Classes/dev/ItemEditorTool.gd + AttackEditorTool.gd (#51's reflection-based editor pattern), Classes/units/UnitInstance.gd (get_weight from prompt 7).

Goal: the parts system's mechanical core — spaces, sized modules, proficiency-gated activation, prototypes. RE4-style fitting UI is a LATER content/UX pass; the dev editor is the fitting tool for now. Numbers are placeholders -> named constants, "# playtest-tunable". Terse comments.

1. WeaponModData (.tres, new resource): id, display name, SIZE 1-3, weight, and a v1 effect model of TYPED FIELDS (not scripts): power delta, scaling nudge (blend shift capped ~10% — the scaling contract), added elemental damage type, weight. Keep the effect vocabulary small and additive — exotic effects (alt-fire modes, blocking, overwatch) are LATER content; leave a comment pointing at weapon-mod-ideas.md.

2. SPACES on WeaponData: three spaces with capacities 1/2/3 (constants). Fitted config = per-space arrays of WeaponModData; validate sum(sizes) <= capacity on fit. Several smalls OR one keystone per space — capacity is the whole model. Config is FREE to change BETWEEN MISSIONS ONLY (same seam prompt 9 uses for job swaps); the module itself is the purchase (economy deferred).

3. PROFICIENCY STUB: per-weapon-family int on UnitInstance (persists — #8), dev-editable, DEFAULT high enough that existing scenarios behave unchanged. Proficiency N activates spaces 1..N — a low-proficiency wielder uses a tricked-out weapon at REDUCED capability, never locked out. Effective weapon = base + modules in ACTIVE spaces only. Prompt 13 makes proficiency grow; today it's a dial.

4. EFFECTIVE-WEAPON COMPUTATION: one function computes the modded weapon view (power, scaling, element, weight) from base + active modules. Preview and execution must consume the SAME computed view (Law #2). Module weight feeds unit get_weight() (fills prompt 7's gear term).

5. PROTOTYPES: named prebuilts per family in WeaponCatalog — unique_effect flag + a SINGLE size-1 space. Author ONE example prototype whose effect is impossible via modules (pick something cheap from the wiki flavor bank, e.g. an authored stat re-point beyond the 10% contract — that IS the sanctioned break). Mark with the balance-watch comment from the doc.

6. PROSTHETIC INTEGRATED WEAPONS (audit A2, weapons.md Prosthetic family) — SECOND HALF, do only if the session has room, else file an issue and stop cleanly: a weapon-model prosthetic in a limb slot (prompt 7) is equippable as a weapon consuming NO inventory slot, scaling off ITS OWN built-in STR, never the unit's (expect special-casing in CombatComponent's weapon lookup + the equip UI). The limb keeps its day job — its STR still feeds the arm average.

7. DEV TOOLING: module authoring + fitting via the reflection-based editor pattern (this is #51's "generalize equipment authoring" — advance it, note progress on the issue).

Do NOT touch: RE4 fitting UX (content pass), the module BANK beyond fixtures, blocking/guard mechanics (undesigned — weapons.md marks them a maybe), alt-fire/multi-attack (needs its own design session against the action system), economy/scrap costs (deferred). Doc silent -> STOP and ask.

Done when: a weapon fitted past a wielder's proficiency provably fights at partial capability (only spaces 1..N count, previewed AND executed identically); overfilling a space is refused; module weight moves the unit's Weight readout; the prototype exists with its single small space; old scenarios load unchanged (default proficiency); tests cover fitting validation, activation-by-proficiency, effective-weapon math; suite green; CLAUDE.md weapons paragraph updated; committed.
```
