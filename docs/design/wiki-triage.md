# Wiki Triage Ledger

**Status: TRIAGE COMPLETE 2026-06-17** (issue #32). The exported Google Drive wiki (`C:\Iosis\Drive Wiki`, 152 `.docx`) has **no recoverable dates** — classified by content + dev confirmation. This is the durable record of what's distilled, discarded, and deferred, so the wiki never has to be re-triaged from scratch.

## How to read this
- **DISTILLED** — survivors already captured in `docs/design/`; the wiki doc is now reference-only.
- **DISCARD** — GameMaker-era / superseded; **leave in the wiki as archive, never import**.
- **DEFER** — live but future-milestone; revisit when that milestone arrives.

## DISTILLED → `docs/design/`

| Wiki source | Lives in |
|---|---|
| Elemental Combinatrix, Aristotelian Elements, Rune-Based Algorithms (element set) | `elemental-system.md`, `elemental-interactions.md` |
| Alchemy, Rune Creation, Runestone, Philosopher's Stone (mechanics) | `alchemy-kit.md` |
| The Art of Not Dying; Death, Damage Modifiers, Character-specific stats (downed/Will) | `will-and-death.md` |
| Squads | `squad-system.md` |
| Classes, Upgrade System (growth), Start (economy-as-lever) | `progression.md` |
| Damage Calculation Algorithms (deterministic-preview intent) | `resolution-pipeline.md` (now Law #2) |
| Economy/Items/Weapons/{Main info, Weapon List} | **`weapons.md`** (identities/philosophy; balance deferred) |
| Systems Mechanics/Terrain Modification | **`terrain.md`** |
| Gameplay Philosophies, Intended Player Behavior, Home | **`philosophy.md`** |

## DISCARD (confirmed 2026-06-17) — GameMaker-era, archive in place
- `Code/Headers/**` — GMIDL (Game Maker Interface Definition Language) + `base/` stdlib stubs.
- `Code/Bug tracking/**` — GML crash logs (`obj_*`).
- `Code/{Demo Goals, TODO}` — GameMaker-era working notes.
- `Code/Algorithms/Damage Calculation Algorithms` — crit + pre-RNG "simulate every outcome" (intent survives as Law #2 / `resolution-pipeline.md`).
- `Game Mechanics/Deprecated documents/**` — self-labeled; survivors already mined into `will-and-death` / `progression`.
- **Rot to strip on contact, anywhere:** any `% chance` (crit / dodge / accuracy / "Avo"), **Action Points (AP)**, "battle statistics" framing — all dead under Law #1.

## DEFER
- **Story (`Story/**`, ~44 docs)** — narrative/lore, era-agnostic. → a **Milestone-B story pass** (its own `docs/story/` then). Gameplay leads; story bends to fit gameplay, not vice-versa (dev, 2026-06-17). May be *consulted* to ground gameplay (e.g. "what is a rune?").
- **Economy / Overworld** (`Economy/{Jobs, Start, Scrap, Mounted Weapons}`, `Overworld/Mission Board`) — past basic engine work; Milestone B.
- **Roguelike Mode** — *way* down the road. *(Ticketed 2026-08-25 as [#510](https://github.com/Phaazoid/Godoiosis/issues/510), still P3 — parked, not started.)*
- ~~**Battle transition animation**~~ (grid expands 3×, FE-style zoom) — **RESOLVED 2026-08-25: tracked as [#410](https://github.com/Phaazoid/Godoiosis/issues/410)** (Battle zoom — cinematic squad-combat replay, the fight rises off the board). The "after core gameplay" gate held; the modern form is a camera zoom, not a grid expansion.
- ~~**Battle-preview / combat UI**~~ (`Precombat Informational Popup`, `Battle Preview`, `UI Suggestions`, `Unit Information`) — **RESOLVED 2026-08-25 (dev): the action queue IS this UI.** The Law #2 "preview honesty" surface never became a separate popup — it is the queue panel plus the hover/inspect panels, all built. #2 and #49 (Action Queue UX) are both closed. Nothing here is owed distillation.

## Ideas dispersed from the omnibus docs (`Scratchpad`, `Things we talked about TODAY`)
Per dev request, design ideas were noted into the docs they relate to:
- → `progression.md`: **randomness in *upgrades* (not combat) is allowed** under Law #1; optional job/class-lite layer; double-attack as a weapon property.
- → `squad-system.md`: squad **archetypes by leader specialization** (a "defense squad," etc.).
- → `weapons.md`: weapon-triangle-governs-blocking; build/weight gate; ranged-block-melee.
- → `terrain.md`: atmosphere-as-diffusing-gas.
- → `alchemy-kit.md`: player **rune-carving**; affinities can be *grown*, and unlisted units may use runes poorly (innate/untested affinities).
- Pure plot beats (parents / dragons / philosopher / level ideas) → **deferred to the story pass.**

## Surfaced undesigned mechanic — RESOLVED 2026-08-21
- ~~**Blocking / guard**~~ — **designed 2026-08-20 as Guard ([standing-reactions.md](standing-reactions.md)), BUILT 2026-08-21 ([#414](https://github.com/Phaazoid/Godoiosis/issues/414)).** The dev's *"big maybe — handle elemental + Will first, then see where it fits"* was honoured exactly — it landed after both — but the answer to *where it fits* was none of the three guesses this entry offered (Will? a squad option? a separate abilities system?). It is a **basic main action everyone has**; kit sources grant only the **brace bonus**. Nor did the wiki's framing survive: the *once per engagement* limit, the weapon-type gate and the weapon-triangle modifier are all gone (the triangle was cut 2026-07-06), and **total victim substitution** replaced mitigation-style blocking — the blocked hit resolves against the blocker as if they were the target, whole payload included. What *did* survive from the old text is the range gate and the DEF flavour.

## Method (reproducible)
Text was bulk-extracted from every `.docx` (a docx is a zip; `word/document.xml` → strip tags) and tagged for era-signals (crit/AP/GML) + topics. Re-run anytime if the wiki changes.
