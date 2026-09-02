# Transmutation Doctrine — Sigils, Flourishes & the Discovery Table

> **Status: PROVISIONAL — rebuilt 2026-07-03 around the discovery doctrine** (design sessions 2026-07-03, superseding the 2026-06-30 proposal framing: that model's *chassis* survives intact; its philosophy is replaced). Every roster below is **pinned seed content** — a starting point for exploration, not a build list.
>
> **Grilled 2026-07-04:** all six open questions resolved (see *Grill resolutions* at the bottom), and the channeling model rewrote itself along the way — rune temper + trained-leeway brute force, built 2026-07-20 ([#60](https://github.com/Phaazoid/Godoiosis/issues/60)). **That channeling model is REPEALED 2026-08-10** — see the repeal record in *Temper & channeling*: channeling is now **anchor + wildcards**, the temper gates inscription only, and strain left the system (its math preserved in the "strain as a job ability" issue). Everything else the grill resolved stands.
>
> **Co-dev RATIFIED 2026-07-11 (agenda Stop 5), with a content-priority rider:** everything here is fine for testing as-is. Going forward, **effects-first, tools-first** — think of the effects we actually *want* in game and give them to units as tools (runes/flourishes a unit actually wields) *before* trying to lock down every combination in the table. The discovery table fills in behind wanted effects, not ahead of them. (Rider also stamped on [elemental-interactions.md](elemental-interactions.md) — the shared combo content pool — and parked grill 11.)
>
> **Wording note (immersion):** in-game language stays inside the fantasy — *channeling, transmutation, carving, marks* — never "chemistry," even though the designers know exactly what it is.
>
> **Canon checked through #699 (2026-09-02).**

## The fantasy this system serves

The original vision: **Kirby 64-style experimentation** — combine things to see what you get, where every combination is a surprise worth finding. The 2026-06-30 model optimized for authorability and balance (rightly, for #51) but drifted into a *tuning* system: ratio-blending, no jackpots, greyed-out invalid slots, full information. The stiffness the dev felt was the sum of those trades.

The fix is not emergence — Kirby 64 was a hand-authored 7×7 lookup table. The fix is **authored surprise, discovered by the player.** Ours is 5 elements × a small flourish lexicon × repetition depth: a big, finite, authorable table whose cells are revealed by experimentation.

## Anatomy: carved vs drawn

A transmutation is an inscribed alchemy circle with two layers of **different permanence**:

- **Sigils are CARVED** — permanent, cut into scarce runestone. Only 5 exist: **Fire, Water, Air, Earth, Aether.** Repeats = weight. Carving is a *build decision* you sit with; runestone scarcity makes it weighty.
- **Flourishes are DRAWN in materia** — erasable, redrawn between battles. (Materia's "etches/customizes runes" job from [alchemy-kit.md](alchemy-kit.md) is this, nailed down.) Drawing is a *loadout decision* you play with.

The lore rhyme is exact and should ship in flavor text: this is **Solve et Coagula embodied** — the sigil layer is the fixed principle (Salt, Coagula — carved in stone), the flourish layer is the volatile principle (Mercury, Solve — drawn, wiped, redrawn).

Accepted consequence: one carved Water rune toggles between Water and Ice forms between battles. That's a feature (versatility rewards the carving), but "which form is this rune right now" must read clearly in the loadout UI.

## Temper & channeling — the anchor + wildcard model (dev, 2026-08-10)

> **REPEAL RECORD (2026-08-10).** The trained-leeway model this section carried from the 2026-07-04 grill (co-dev ratified 2026-07-14) is **repealed on its channeling side** — dev call, out of a #166 playtest where an aether-1 alchemist could not channel a `[1 Air, 1 Aether]` carving on an air-tempered rune. The dev's stated original intent: **temper clamps what can be INSCRIBED, never who can channel** — the 2026-07-04 model drifted from it. Two rationales: **lore** (runestone is alkahest fallout, tunable to any element — the stone itself fills small gaps) and **design** (temper-gating locked non-matching alchemists out of whole stones, killing the experimentation this doc's own fantasy section demands). What is repealed: the temper channel-floor ("never brute-forced"), trained leeway as the budget, and **strain as an inherent price** — strain's math left the code entirely and lives in the "strain as a job ability" issue (the 2026-07-23 capture at the bottom of this doc, now actioned) if it returns as a job passive. What survives: the temper's inscription rules (rule 1, verbatim), the aura data model, all sizing/discovery doctrine.

*(The aura these rules read — genetic affinity set + grown per-element points + the −1-per-lost-limb tax — was ratified 2026-07-05: [alchemy-kit.md](alchemy-kit.md) → Aura data model.)* Three rules:

1. **Temper.** A blank rune's **first carving colors its alkahest** — the stone is permanently *tempered* to that carving's primary element. Every later carving on it must **contain the temper element** and must **not be primarily another element**: a fire-tempered stone can never hold 2A+1F (off-temper weight ≤ temper weight; ties are legal — the temper just can't be outweighed). The first carving on a blank *is* the temper choice, flagged at the bench (see the warning tiers in *Grill resolutions* #4). **This is the temper's whole gate role** — at channel time it only keys rule 3's pool.
2. **The anchor.** Channeling needs **real aura ≥ 1 in at least one of the carving's own elements.** Wildcards never substitute for the anchor. (This is the Rebecca rule made per-carving — no aura anywhere still channels nothing, and a maim-taxed pool at 0 loses the anchor even though the affinity persists.)
3. **Wildcards — two pools that never stack.** The carving's **total deficit** (summed aura shortfall across all its elements, depth and breadth alike) must be covered by the wielder's wildcard capacity, which is the better of:
   - **the universal +1** — every rune covers one point of deficit for anyone anchored (the alkahest in the stone doing the filling — the lore rationale made mechanical);
   - **spare temper aura** — on a rune tempered in an element the wielder holds, their aura in that element *beyond the carving's own temper weight* is the pool instead. Spare, not all: an alchemist channeling a deep same-element carving has less left over for its riders. Never `+1` on top — capacity is `max(1, spare)`, and the dev's canonical refusal is exactly the stacking case.
   - No price, no strain, nothing spent — aura is a stat measured against, never a resource (fork 3 stands).

What the model buys: **small gaps are free everywhere; big reaches demand a matching stone.** The motivating case works on any rune (one shared element + the universal wildcard); a specialist on their own tempered stone stretches furthest (spare depth converts to flexibility); nobody stacks their way past their training (the pools are exclusive, so capacity never exceeds `max(1, spare)`). Two consequences owned openly at the repeal: **"3-Fire demands true fire-3" is dead** — fire-2 plus the wildcard now channels an Athanor (and Isaac's breadth-1-everywhere now carries +1 depth everywhere), so the deep-table-feels-earned argument in watch-item 4 weakens by exactly one point; and the specialist's budget **shrank from full temper aura to the spare** — an air-2 alchemist channeled `1A+1F+1W` under trained leeway (forced 2 ≤ budget 2, at strain 3) and is refused now (spare 1), while air-3 still reaches it, free. Specialists traded reach-by-blood for reach-by-matching-stone.

## The five doctrines

1. **Sigils make the stuff; flourishes transform the stuff.** Element combinations produce *nouns* (Magma, Steam, Mist — authored identities, never blends). Flourishes are *operations* applied to that matter (Ice is not an element — it is Water in a fixed state). The sigil ratio tunes *within* an identity (2F/1E Magma flows; 1F/2E Magma erupts), never interpolates between two identities.
2. **Every combination does something.** No greyed-out slots, no "invalid" marks — Kirby 64 has no illegal combos. Cells that look like they shouldn't work are where the weirdest discoveries live (Push + Fire = the flame vents backward: a fire-dash). Duds are allowed but must have personality (a fizzle that belches usable smoke).
3. ***Sola dosis facit venenum*** — "the dose makes the poison" (Paracelsus' own maxim; his name is on the runestone capital). Repetition scales smoothly until an **authored threshold where quantity becomes quality**: twinned flourishes cross thresholds, tripled sigils transcend their element.
4. **Jackpots in kind, never in number.** Equivalent exchange guards the *numbers* (flourishes reshape, never inflate — the #51 balance guardrail stands). But specific recipes unlock **unique verbs unreachable any other way** (Sympathy, Aqua Regia, Quintessence). Identity is generous; damage is not.
5. **The table is hidden until first inscription** (always the plan; gated on dev-tools-only so far). Outcomes are 100% deterministic (Law #1) and combat previews exact (Law #2) — but the *codex* starts blank, and the moment of inscription is the reveal. Rules:
   - A "failed" experiment **never yields nothing** — you always get a working rune plus permanent codex knowledge. Scarcity makes discovery weighty, never punishing.
   - **The channeling warning must not leak the codex.** "No one in your party can channel this combination" — full stop, without revealing what it would have made. (The warning itself is a required #51 editor guard: an M-rune carving nobody can channel is an expensive mistake.)
   - Scroll lore gives *partial* recipe hints — spend story knowledge to de-risk carving (ties to "carvings learned from scrolls," alchemy-kit fork 1).
   - **The Enclosure is the reveal stamp** (answers the old open question #2): a discovered named identity draws its bespoke outer circle; undiscovered combos show an incomplete enclosure.

## Rune size = discovery tier

**Two knobs per size** (grilled 2026-07-04 — one capacity number couldn't both keep runes multi-carving loadouts *and* keep triples out of M):

- **Circle cap** — max sigils in a *single* carving. Lore: a bigger circle needs one big uninterrupted stone face.
- **Capacity** — total sigil budget across *all* carvings (small circles tile on a big stone). Flourishes stay capacity-free — that's the drawn layer.

Slot curve: **flourish slots = 2 × sigils − 1** (1→1, 2→3, 3→5), per carving, unchanged.

| Rune | Circle cap | Capacity | Discovery tier |
|---|---|---|---|
| **S** | 1 | 1 | Pures + single flourishes — the **low-risk sandbox** (intentional: S runes stay common without being overpowered). Twins are *impossible by construction*. |
| **M** | 2 | 3 | The **Conjunction table** (pairs) + twinned flourishes — one pair with a pure riding along. The Kirby moment arrives with your first M rune. |
| **L** | 3 | 6 | Triples: weather, life, the deep Aether ladder. Two triples, or triple + pair + pure. |

Numbers are **pseudo-locked 2026-07-04** — committed so content can land, expected to move in playtests. Alkahest (5 sigils) stays *physically uncarvable* — correct: it's the story-gated silhouette. Twin placement is now pure arithmetic (pairs→M, triples→L); the ⚠ watch-list entries stay at their arithmetic tier pending playtests.

Gating rule of thumb: **every axiom-sensitive effect (stagger, mass-reposition, hard CC) sits behind a twin or a ×3**, so the capacity ladder does the balancing — no fiat needed. Worked example: 2 Air + Focus×2 (Thunderclap) spends 2 of 3 slots on the twin; intensity is bought with breadth.

---

# Seed tables (all pinned, none final)

Tags: **✓** already canon in code/docs · **⬅** absorbs an idea-bank esoteric ([elemental-interactions.md](elemental-interactions.md)) · **✦** new, fell out of the doctrine · **⚗** speculative bench · **⚠** axiom watch-item.

## Tier 1 — Pure sigil × flourish (the S-rune sandbox)

| Recipe | Result | Effect |
|---|---|---|
| Water + Stillness | **Ice** ✓ | Freeze — CHILLED/FROZEN, ice bridges |
| Fire + Quickening | **Shock** ✓ | Lightning — chains on CONDUCTIVE |
| Water + Quickening | **Solvent** ✦ | Dissolve — strip a coating (OILED, buffs), erode soft terrain; the *diluted echo of alkahest* (lore whisper) |
| Fire + Stillness | **Calcine** ⬅ | Flameless smolder — DRY + BRITTLE; anti-WET, feeds Shatter |
| Earth + Quickening | **Quake** ✦ | Tremor line — knockdown/ROOTED, shakes cover |
| Air + Focus | *(focused gust — weak)* | True stagger moved up-tier — see Thunderclap ⚠ resolved |
| Aether + Stillness | **Coagula** ⬅ | Lock states on the target — the fixative master-verb |
| Aether + Quickening | **Azoth** ⬅ | The animating spark — re-fires a reaction; the revive medium |
| Aether + Focus | **Radiance** ⚗ | Beam — REVEALED/blind (LIGHT's recipe, if second-wave ever lands) |

Structural find: **Coagula and Azoth are pure Aether across the Solve/Coagula polarity** — the two most esoteric verbs are the *simplest* Aether carvings, right for lore (fundamental principles, not exotic products), and give Aether-affinity units identity from their first S rune.

## Tier 2 — The Conjunction pairs (the M-rune table)

| Pair | Base identity | Transformations worth authoring |
|---|---|---|
| Fire + Water | **Steam** ⬅ — scalding cloud, cuts vision | +Focus → **Pressure Jet** (scald lance) · +Stillness → **Condense** (rain-on-demand: WET field) |
| Fire + Earth | **Magma** ✓ — 2F/1E flowing wave, 1F/2E erupting spout | +Stillness → **Obsidian** ✦ (BRITTLE shard terrain, Shatter bait) |
| Fire + Air | **Firestorm** ✦ — windborne spreading blaze | +Stillness → **Smoke** ⬅ (vision/LDR denial) · 2A/1F +Quickening → **Storm Bolt** ✓ |
| Fire + Aether | **Phlogiston** ⬅ — PHLOGISTICATED primer | +Spread → phlogisticated *zone* — a minefield any spark detonates |
| Water + Earth | **Mire** ⬅ — bog: ROOTED, movement tax | +Corrode → **Vitriol** ✓ · +Stillness → **Rampart** ✦ (mud that sets: instant cover) |
| Water + Air | **Mist** ⬅ — local fog: vision/LDR denial | +Stillness → **Rime** ✦ (frost-slick, CHILLED field) · +Quickening → **Squall** ✦ (rain + shove) |
| Water + Aether | **Soul Dew** ✓ — splash, lesser healing | +Spread → healing rain · +Stillness → lingering regen tile ⚗ |
| Earth + Air | **Dust** ⬅ — abrasive blinding cloud | +Quickening → **Scour** ✦ (chip + strips coatings) · +Stillness → sand pit (bog + slam synergy) |
| Earth + Aether | **Stone Ward** ✓ — heavier, tougher enchant | +Pull → **Lodestone** ✦⬅ (haul FERROUS, yank weapons — MAGNETO's role from the alchemist's side) |
| Air + Aether | **Telesma** ⬅ — untyped kinetic force | +Focus → hurl + AIRBORNE · +Spread → gather/scatter squads · +Quickening → **Sublime** ⬅ (SUBLIMED) |

Deliberately absent: planetary metals, Galvanic, Clockwork — **mechanist-side on purpose** (Lodestone/Pressure Jet are the alchemist *reaching toward* that domain, which beats owning it).

## Tier 3 — Triples (the L-rune tier, selective)

Pattern: **triples want to be atmospheres and living things** — the L-rune tier is the induced-weather hook made castable.

| Recipe | Result | Effect |
|---|---|---|
| Fire + Air + Water | **Tempest** ⬅ | Local storm: WET tiles + telegraphed strikes on a cadence |
| Water + Earth + Aether | **Verdance** ⬅ | PLANT recipe'd: entangle (ROOTED), bramble cover · +Quickening → grasping overgrowth · +Stillness → set bramble wall |
| Fire + Earth + Air | **Ashfall** ✦ | Volcanic pall: vision cut + Calcine chip to the unsheltered |
| Fire + Water + Aether | ⚗ humoural line | Warm living fluid — BLOOD/frenzy's seat if the four-humours axis ever graduates. Parked |
| all five | **Alkahest** ⚗⚗ | Story-gated, never carvable — but the codex **shows the empty silhouette** (Isaac's arc as a question mark at the bottom of the table) |

## Repetition Axis A — Stacked sigils (the specialist's ladder)

×2 = the canon smooth case (2F = heavier fireball ✓). **×3 transcends:**

| Element | ×3 transforms into |
|---|---|
| Fire | **Athanor** ✦ — the furnace-flame: cannot be doused, burns WET targets (breaks QuickDry) |
| Water | **Deluge** ⬅ — flood the low ground: real water tiles ("attack the map," castable) |
| Earth | **Bulwark** ✦ — true terrain edit: persistent wall line, rubble cover when broken |
| Air | **Cyclone** ✦ ⚠ — AoE launch: AIRBORNE on a cluster (Axiom 4: mass-reposition must stay expensive) |
| Aether | **Sympathy** ⬅ — bind two units; states and a damage share mirror between them. (Ladder: ×1 cleanse → ×2 **Conduction** ⬅ carry a combo at range → ×3 Sympathy) |

Mono-stacks scale off one element's aura repeatedly → **the specialist's payoff**; conjunctions reward the generalist. Party-composition texture for free.

## Repetition Axis B — Twinned flourishes (intensity thresholds)

| Twin | Threshold | Worked example |
|---|---|---|
| Focus ×2 | Concentration → concussion | **2A + Focus×2 → Thunderclap** ⬅ — STAGGERED, now correctly gated at M-rune with 2/3 slots spent (Axiom 3 ✓ — the S-rune version was too cheap) |
| Stillness ×2 | Fixing → freezing solid | **2W + Stillness×2 → Glacier** ✦ — skip CHILLED: instant FROZEN + persistent walkable ice sheet |
| Quickening ×2 | Volatile → double-acting | **2F + Quickening×2 → Fulmination** ✦ ⚠ — strikes twice (two deterministic activations; preview must show both — Law #2 resolver check needed) |
| Spread ×2 | Instant → **lingering field** | any AoE → its zone version (2F+Spread×2 = a Burning Field that *stays*) — the clean seam to the EoT/tile-state layer 🔗 |
| Push ×2 | Shove → launch | knockback → AIRBORNE, no Telesma required |
| Pull ×2 | Drag → implosion | **Air+Aether + Pull×2 → Maelstrom** ✦⬅ ⚠ — gather a scattered squad into one tile (VACUUM absorbed; "Gather → Delete" setup as one carving) |
| Corrode ×2 | Acid → the acid of acids | **W+E + Corrode×2 → Aqua Regia** ✦ — *the only thing that bites gold* (planetary-metals doc already declares this) — the anti-gold-boss answer as a findable recipe |
| Stillness ×2 on 2Ae | Locking → petrifaction | **Fixation** ✦ — COAGULATED + can't move or be moved; the hard-CC that counters repositioning |
| *(triple mark, L-rune only)* | | **2Ae+1W + Quickening×2 → Quintessence** ⬅ — re-fire the whole reaction stack ("busted, fun" — exactly what the deepest rung should hold) |

What this axis buys: (a) S-rune power ceiling enforced **by construction** — twins can't exist below M; (b) the codex gets a **vertical tease** — a discovered recipe with a shadowed rung beneath it ("you know Water+Stillness; something lies deeper"); (c) weighted stacks (2Ae+1W) are where the ratio rule and repetition rule compose.

## Flourish lexicon — two natural classes

The exploration data answered old open question #3: transformative cells cluster on the classical axes, utility marks mostly keep generic behavior.

- **Transmuting marks** (change what it IS): **Stillness, Quickening, Corrode** — the Solve et Coagula polarity + the descent-into-earth. Rare, possibly *learned* (making Corrode late-game is the tuning lever if Aqua Regia's slot-math gate proves too cheap).
- **Shaping marks** (change how it LANDS): **Spread, Focus, Push, Pull** — generic reshaping by default, with a few authored exceptions (Thunderclap, Lodestone, Maelstrom).

Teachable in one line of flavor: *"the mercurial marks change what it is; the geometric marks change how it lands."*

## Axiom watch-list (updated at the 2026-07-04 grill)

1. **Cyclone / Maelstrom** — mass-repositioning is a win condition (Axiom 4); ×3-Air / twin-Pull + the channel gate are probably enough. *(Amended 2026-08-10: the gate is now wildcard arithmetic, not a strain price — a ×3-Air demands air-2-plus-the-wildcard minimum, air-3 for comfort.)* Watch in playtests.
2. **Fulmination** — double activation = two reaction passes; deterministic but the resolver + preview must show both (Law #2).
3. **Aqua Regia — RESOLVED 2026-07-04:** Corrode is a *learned* mark (mid-game scroll/story reveal) — the gate is content pacing, no new rules. See grill resolution #2.
4. **Aether aura rarity — strengthened 2026-07-04, ⚠ weakened one point 2026-08-10:** the wildcard model lets anyone anchored channel one point past their training, so deep-Aether verbs (Fixation, Sympathy, the ×3 ladder) now demand deep-Aether-minus-one rather than the full depth (an aether-2 alchemist reaches a ×3 via the universal wildcard). The roster check matters MORE now, not less: Aether affinity must stay rare enough that even depth-minus-one feels earned. Watch in playtests.
5. **Pair discovery starts at M runes** (S circle cap = 1) — *chosen* pacing beat (pures first, then the world opens), confirmed intentional 2026-07-03; numbers pseudo-locked 2026-07-04.

## Far future — pinned, not designed

- **Mid-battle re-flourishing.** Materia is ambient on the battlefield — and, since the 2026-08-29 pass, at authored **veins** too (grill resolution 6 below; ticket [#513](https://github.com/Phaazoid/Godoiosis/issues/513)); redrawing a flourish mid-fight is a latent alchemist verb. Must eat a main action minimum. The target fantasy: *erasing a flourish in a way that weakens the unit as a final gambit — trading power for the one utility that opens a previously impossible path to victory.* Pinned 2026-07-03.
- **Mounts & taming (the Bond).** Alchemist mounts = beasts lulled and bonded via transmutation; mechanist mirror = engineered vehicles (planetary metals + materia fuel) — *built vs befriended*, asymmetry preserved. Doctrine (pinned 2026-07-03):
  - **A Bond is a Sympathy made permanent** — the pure-Aether ladder (×2 Conduction, ×3 Sympathy) fixed by Coagula. Recipe shape: **2 Aether + 1 species-element sigil + Stillness×2** (3 sigils → 5 slots; Aether primary = the bond, species sigil = the key cut for that beast, twin Stillness = outlives the battle). Permanent bond = `UnitInstance`-side state (the persistence seam), hence deliberately the most expensive recipe class in the game. Lands at **tier 3**: a deep-Aether demand (aether-2 minimum under the 2026-08-10 wildcard model — at aether-1 the recipe's total deficit is 2, one aether + the species sigil, and no pool covers two; at aether-2 the wildcard carries the species sigil), L-rune slots, plus—
  - **Taming is a reaction, not a new system:** Bond × [required beast state] → TAMED. The bond only takes on a *prepared* beast (fire-drake must be Quenched, storm-roc GROUNDED, cave-bull MESMERIZED — the lull; that bench state's job). Deterministic capture, no roll (Law #1); the preparation *is* the combinatrix — taming becomes a multi-beat combo assembled in the field.
  - **Per-species recipes are per-species discoveries** — "what tames *this*?" is the Kirby question aimed at fauna.
  - **Lore loop:** beasts were *wrought* by Stone-era aether-alchemy (the hidden dragon lab) — which is mechanically *why* they answer transmutation. Creation is the ancient taboo tier (a codex silhouette beside Alkahest; diluted modern affinities can't do it); taming is the modern echo. The lab dragon is alkahest-touched → **only an Alkahest affine can bond it: dragon riding is gated by Isaac's arc, not numbers.**
- **Inventory limits** for carried runes (e.g. an M + two S) — later balance pass.
- **Manual carving — players draw the rune themselves** (captured 2026-07-08, [#52](https://github.com/Phaazoid/Godoiosis/issues/52)). A long-held dev + co-dev wish: the player physically *performs* the carving — enclosure, sigils, flourish marks — instead of menu-picking at a carving site (resolution #4's workshop UX stays the baseline). An **input method, not a new power system**: a drawn carving resolves through the same inscription-legality rules, size knobs, and discovery table; recognition must be deterministic and previewable (Law #1 — skill expression, never a roll). Rides on the doctrine code (#30 lane), the codex layer, and the carving-site UX. Own grill before any code — parked in [grill-queue.md](grill-queue.md). *(Supersedes a briefly-captured "player-built transmutations" idea from the 2026-07-08 sweep — that scratchpad entry predated the 2026-07-04 grill, whose sigil/flourish model already delivers it.)*

## Where this sits / in code now (#30 substrate + #60 doctrine catch-up, BUILT 2026-07-20)

- **In code:** weighted sigils (`TransmutationData.sigils`, repeats = weight), the flourish lexicon + opposite-rejection (`Classes/alchemy/Flourish.gd`), the slot curve (2n−1), derived-element lookup (Water+Stillness→Ice, Fire+Quickening→Shock) feeding `get_elements()` → combinatrix/terrain. **The doctrine catch-up (#60), re-cut 2026-08-10:** the genetic affinity set (`UnitInstance.affinity`), the two-knob rune sizes (`RuneData.CIRCLE_CAP`/`CAPACITY`, `is_legal()` load-time validation), the temper rule (`RuneData.temper`, set permanently by the first inscribed carving, `_fits_temper` enforcing "contains it, never outweighs it" — now inscription-only), and the channel gate as **one reason-first ladder**: `TransmutationData.channel_block_reason` (anchor + wildcards via `total_deficit`/`wildcard_capacity`), with `can_channel` derived from it (#166's seam). Pinned by `tests/items/test_transmutation_and_runes.gd`'s channel section — one case per row of the model's worked-examples table.
- **Strain left the code entirely (2026-08-10):** `STRAIN_BY_FORCED`/`forced_points`/`strain_cost` are deleted, their math preserved in the "strain as a job ability" issue. [#76](https://github.com/Phaazoid/Godoiosis/issues/76) — the resolver-stage affordability check + HP payment — is superseded by that issue (flagged there; closing it is the dev's call).
- **Not yet code:** the Conjunction identities, repetition thresholds, the codex/discovery layer (recipe→identity mapping, tracked separately as [#75](https://github.com/Phaazoid/Godoiosis/issues/75)), **empowered forms** ([#695](https://github.com/Phaazoid/Godoiosis/issues/695) — what a carving becomes at a materia source; *materia offsets* stood here until 2026-08-29 and are retired, being strain's, and strain left in 2026-08-10), every seed-table entry beyond the two canon derivations, and the maim aura-tax tiebreak's real selector (still enum-order placeholder, [#77](https://github.com/Phaazoid/Godoiosis/issues/77)). Co-dev adjustments land as table/data edits, not rework.
- The 5-element + rune/aura/capacity stack stays **locked** in [alchemy-kit.md](alchemy-kit.md) (channeling section rewritten there 2026-07-04 to match this doc, then built 2026-07-20); the combinatrix architecture in [elemental-system.md](elemental-system.md) is untouched — this doc still just defines where an attack's element tags come from, only now the tag-space is a discovery table.

## Grill resolutions (2026-07-04 — all six open questions closed)

1. **Numbers → two knobs, pseudo-locked.** Circle cap 1/2/3 · capacity 1/3/6 (see *Rune size = discovery tier*). Twin placement = arithmetic (pairs→M, triples→L); no fiat moves — the ⚠ watch-list rides at its arithmetic tier until playtests say otherwise.
2. **Mark learning → a principle, not a roster.** The flourish lexicon is *incomplete by design* and mark availability is **progression content**: some marks are figured out/unlocked later, justified in-world (the game opens mechanist-side, where carving knowledge is thin and Paracelsus hoards secrets). **Corrode = the presumptive first learned mark**, doubling as Aqua Regia's gate. The day-one roster is a content pass, not a rule.
3. **Codex → public geometry, private lexicon.** The sigil grid (pures/pairs/triples) shows from the start as empty enclosures — pair-theory is in-world common knowledge, and the checklist pull is the Kirby engine ("knowing how much you don't know is boring" — rejected fog-of-war). Flourish rows exist **only for marks you know** — the lexicon's size stays secret. Shadowed rungs reveal *existence + axis* only; scrolls ink partial components directly into a cell ("Water + ? + Stillness"); inscription reveals name + enclosure + effect at once. **The codex is party-scoped:** recruited alchemists (the Bleeding Hearts' alchemists; the aether alchemist from the military camp) merge their known recipes on join and arrive carrying inscribed runes — the table starts pre-inked, no cold-start.
4. **Blind carving → workshop-only, three warning tiers.** Carving happens between battles at **authored carving sites** (facility quality/knowledge is a story lever — mechanist-side benches know less; the alchemy side of the world adds other sites later). Warnings *(re-termed 2026-08-10 for the wildcard model)*: (a) **temper notice** on a blank stone's first carving — always shown, not a leak; (b) **hard confirm** when nobody in the party can channel it, wildcards included; (c) **soft note** when reachable only through wildcards ("only X can channel this, and only on this stone"). Copy never reveals what it would make.
5. **Naming → register tracks depth.** Common matter reads plain (Steam, Quake, Rampart); the deep table — Aether-touched, threshold-crossers, ×3 transcendents — earns genuine alchemical vocabulary (Athanor, Azoth, Aqua Regia, Quintessence): the archaeology of real alchemy *is* the reward ladder. Author's override rights reserved for one-off cool names. Per-name survival = a content pass with this rule as the filter. **Rider — the tooltip doctrine:** hover any elemental effect on the field, or any carried rune, and get its reaction list — the game never requires memorizing the table (filed in [visual-clarity.md](visual-clarity.md)).
6. **Re-flourish → proximity OR burn carried.** Mid-battle redraw needs its etching medium: adjacent matching ambient source + main action, or burn carried pure materia to do it anywhere — materia substitutes for *position* like it substitutes for *aura* (the "pay up" rhyme). Feature itself still contingent on playtests; this is the starting posture. **Unchanged by the materia pass (2026-08-29) — and that is the point: the whole doctrine was built to rhyme with this rule.** Two additions only: **veins now count as sources** and an **alkahest vein matches any temper**, so an authored board can make a redraw possible where no natural terrain would; and *adjacent* is now a defined term with one implementation (on or adjacent, Manhattan 1, reach a knob — [#694](https://github.com/Phaazoid/Godoiosis/issues/694)) rather than a number this feature had to invent. Ticket: [#513](https://github.com/Phaazoid/Godoiosis/issues/513), whose stated blocker this closes.

**Still open after the grill (pruned 2026-08-10 — strain items moved to the "strain as a job ability" issue; pruned again 2026-08-29 by the materia pass):** ~~materia offset rates~~ **retired — they were strain's offsets, and the ratified materia model has none** (see [alchemy-kit.md](alchemy-kit.md) → *Materia*); flourish magnitudes (deferred earlier); the full mark lexicon roster + day-one availability; the per-name pass; playtest validation of every pseudo-locked number, now including the wildcard model's two watch-points (Aether depth-minus-one; the specialists' spare-budget squeeze).

**Captured idea (scratchpad sweep, 2026-07-23) — strain as a job-granted verb, not a universal: ACTIONED 2026-08-10.** The capture read: brute-force channeling might be **granted by a job ability** ("blood transmutation" flavor) rather than a baseline every trained unit owns. The repeal took the first half of that path — strain is no longer inherent to channeling (the wildcard model carries access instead) — and the job-ability half is now filed as the "strain as a job ability" issue, carrying the removed math so nothing is lost. Still inside the jobs doctrine fence (jobs may work the *strain* side, never grant aura/temper — [job-ideas.md](job-ideas.md) §Watch-list). Sibling sketch: the **Blood Transmuter** entry in [job-ideas.md](job-ideas.md) §C.
