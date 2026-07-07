# Job Ideas — The Roster Idea Bank

**Status: BRAINSTORM (2026-07-06, same session as the jobs grill).** The divergent bank for [jobs.md](jobs.md)'s deferred roster/naming pass — the jobs analogue of [elemental-interactions.md](elemental-interactions.md). **Nothing here is locked**; every number is a sketch. Two prongs: jobs→abilities (world-grown + genre-adapted) and abilities→jobs (Iosis-unique mechanics seeking owners).

**Naming register:** trades and posts, never classes — occupational words a mercenary company would actually use (Sawbones, Quartermaster, Banneret). *"Even in a classless society, people have jobs."*

**Format:** *Name (posture · lean)* — fantasy. Starter = day-one ability; Main = main-tier; Sub = sub-tier; ceilings/MOV where they define the job. Taxonomy tags: [A]ction [R]eaction [P]assive [M]ovement.

---

## A. World-grown jobs (fiction-first)

1. **Vanguard** *(team · —)* — the shield of the line. Starter: **Taunt** [R] (standing policy: counters against my party must target me — the C3 override). Main: **Guard** [R] (once per pass, adjacent-ally damage redirects to me, previewed), **Immovable** [P] (cannot be shoved — Weight override; anti-Bludgeon/air-burst teeth). Sub: **Brace** [P] (+MHP). Ceiling: DEX ≤ 4 (plate is free). MOV 3.
2. **Banneret** *(leader · —)* — the standard-bearer; Rally made doctrine. Starter: **Steady Rally** [P] (Rally falloff −1). Main: **Rallying Cry** [A] (Rally becomes a small AoE), **Hold Fast** [P] (leader-gated: squadmates within N have Will down-cost −1). Sub: **Second Wind** [P] (+1 to own rally_count).
3. **Sawbones** *(team · mech-ish)* — field medic in a world that loses limbs. Starter: **Practiced Hands** [P] (my rescues revive at 3 HP, not 1). Main: **Triage** [A] (extend an adjacent downed ally's countdown +1 — buys the rescue loop a turn), **Stretcher Drill** [P] (rescue-carry doesn't lock my move). Sub: **First Aid** [A] (small heal). Camp: recovery-task multiplier (deferred interface).
4. **Prosthetist** *(team · mech)* — tinker of flesh and brass; the job the limb-slot model invents. Starter: **Field Refit** [A] (reattach an adjacent ally's detached prosthetic mid-battle — it's recoverable gear). Main: **Overtune** [A] (+1 a prosthetic's built-in stat until mission end, previewed), **Kit Bash** [A] (jury-rig a broken item). Sub: **Oiled Joints** [P]. Camp: prosthetic/mod work discounts.
5. **Quartermaster** *(team · —)* — the company's arms and legs. Starter: **Hand-off** [A] (free-action item pass to an adjacent ally). Main: **Deep Pockets** [P] (+inventory slots), **Provision** [A]. Sub: **Pack Mule** [P]. Rider idea: cheap familiarity/LDR cost to field in anyone's squad. Camp: shop/economy dial (⚠ economy-jobs = "maybe" per canon).
6. **Outrider** *(loner · —)* — first in, last seen. MOV 6; ceiling MHP low. Starter: **Pathfinder** [M] (rough terrain costs normal). Main: **Farsight** [P] (+PER band; reveals enemy *jobs* at range — the legibility amplifier), **Ghost** [M] (does not trigger Sentry-zone engagement — ⚠ needs preview so painted zones stay honest). Sub: **Fleet** [M] (+1 MOV while unarmored).
7. **Lamplighter** *(team · —)* — light-bearer; the honest-information trade. Starter: **Lantern** [P] (reveal radius). Main: **Signal** [A] (mark a target: squad attacks against it +1 — deterministic focus-fire), **Spotter** [P] (squadmates' volleys exclude allies — `hits_allies` protection; huge with Chemical Spitters). Sub: **Watchman** [P].
8. **Dowser** *(loner · alch)* — reads the land's veins. Starter: **Vein-sense** [P] (see hidden materia caches — the materia-pass dowsing hook). Main: **Draw Up** [A] (improve the ambient materia band on your tile). Sub: **Diviner** [P]. Camp: materia-find dial (⚠ economy caution).
9. **Vessel** *(team · the bridge)* — the willing battery; mechanist body serving alchemist craft. Starter: **Lend Flesh** [P] (an adjacent caster may pay strain from my HP — same affordability rules, never downs me). Main: **Ironblood** [P] (strain routed through me is reduced), **Fortitude** [P] (regenerating pre-HP shield — re-homed Will orphan). Dark, very Iosis.
10. **Adept** *(any · alch)* — Paracelsus-trained: technique over talent. Starter: **Steady Hands** [P] (own brute-force strain recoil −N). Main: **Scholar** [P] (codex shows reaction *hints* one step earlier). ⚠ **Doctrine fence:** no job may grant aura or effective temper ("temper never brute-forced" + aura-is-genetic are inviolable) — this job works the *strain* side only.
11. **Beasthandler** *(loner · —)* — taming's mundane half. Starter: **Soothe** [A] (apply the lull/bench state that preps a beast for the Bond reaction). Main: **Bond** [A] (deliver the taming reaction), **Kennelmaster** (tamed-beast handling rules). ⚠ Rides the deferred summons/taming lane — post-Milestone-A.
12. **Pit Fighter** *(loner · mech)* — the gangs' gladiator. Starter: **Scrap** [P] (unarmed counts as a weapon scaling off arm STR — flips C6's "weaponless can't counter," legibly; prosthetic-arm synergy). Main: **Headliner** [P] (+damage with no squadmate within N — the solo niche), **Deathwish** [P] (Crisis gate at ≥80% Will instead of full — ⚠ watch-list). Sub: **Brawler** [P].
13. **Duelist** *(loner · —)* — the counter artist. Starter: **En Garde** [P]. Main: **Riposte** [R] (counters every attack against *me*, not once per plan — a C1 modifier), **Slipstream** [R] (a shove against me moves me 1 extra tile in a direction I chose at plan time — judo with the physics system). Sub: **Poise** [P].
14. **Agitator** *(loner/leader · —)* — the Will war made a trade. Starter: **Intimidation** [P] (plannable Will-drain aura — the re-homed orphan). Main: **Demoralize** [A] (targeted Will chunk), **Infamy** [P]. Counter-play: see Counselor. (No AI-behavior manipulation beyond published policies — taunt-style overrides only.)
15. **Counselor** *(team · —)* — the company's spine-keeper. Starter: **Steadying Word** [A] (small Will restore, falloff like Rally). Main: **Bulwark Mind** [P] (allies within N are immune to Will-drain auras — policy vs policy, fully previewable), **Iron Will** [P] (deterministic damage cap — re-homed orphan). Camp: Will-recovery task multiplier.

### Story-unique jobs (the sanctioned gate)

16. **Captain of the Bleeding Hearts** *(leader · — · Torv)* — the refuge-maker: maimed/prosthetic-bearing units cost less of his squad budget; his Rally reaches the downed. Mechanics echo the story: he collects the discarded.
17. **Panacea** *(? · alch · Isaac)* — the alkahest cover story. Displays as a mundane adept-of-everything job; **the job's existence is the lie** that hides the hidden sixth element from the player until the story tips it.
18. **Godhand** *(any · mech · Rebecca-arc)* — what the talentless build instead: faster weapon-proficiency training, deeper prosthetic integration. The 0-aura answer, story-seeded at her arc's turn.

## B. Genre-adapted jobs

19. **Drillmaster** *(leader · —)* — (Advance Wars CO / FE tactician) doctrine passives. Main: **Coordinated Assault** [P] (leader-gated: each later squad hit against the same target this pass +1 cumulative — rides sequential resolution; the order-lever made a build). Sub: **Drill** [P] (squad training-rate nudge).
20. **Springheel** *(any · mech)* — (FF Dragoon, steampunk'd: piston legs). Starter: **Vault** [M] (jump over units/1-tile obstacles). Main: **Crash Landing** [A] (leap move + small landing shove). Leg-prosthetic synergy; ⚠ AoE-on-landing may belong weapon-side.
21. **Wrangler** *(team · —)* — (Into the Breach's forced movement) hook and chain. Starter: **Hook Pull** [A] (pull a target 1–2 tiles; Weight-gated — physics teeth). Main: **Long Haul** [A] (pull *allies* — repositioning combos), **Anchor Toss** [A]. Combinatrix gold: pull into fire, off ice, out of zones.
22. **Filcher** *(loner · —)* — (FFT Thief, de-RNG'd). Starter: **Slip** [M] (move through enemy-occupied cells, can't stop there). Main: **Strip** [A] (take a weapon/item from an adjacent DOWNED unit — deterministic theft, dark and fitting). Sub: **Cutpurse**.
23. **Signal Officer** *(team · —)* — (FE Dancer, de-magic'd). Main: **Semaphore** [A] (one squadmate who has already moved may queue a second *move* — never a second main action). ⚠ Watch-list: action-economy manipulation; queue idempotency must hold.
24. **Landwright** *(any · —)* — (FFT Geomancer, de-magic'd): terrain literacy without aura. Main: **Read the Ground** [P] (+damage from elevation/favorable tile states), **Shovel Work** [A] (mundane tile flips only — mud↔dust; ⚠ fence: real transmutation stays alchemy's monopoly). Sub: **Surefoot** [M].
25. **Skirmisher** *(loner · —)* — the flanker; future-proofing hooks. Main: **Backstrike** [P] (+N when attacking a target's rear facing — the seam CLAUDE.md already carved), **Opportunist** [P] (+damage vs targets in any elemental state — exploitation, not immunity). Ceiling: MHP.
26. **Adjutant** *(team · —)* — the second-in-command. Main: **Aide-de-camp** [P] (half my LDR adds to my leader's squad budget; **one Adjutant per squad**). Solves "big squads need one giant-LDR unit" — ⚠ runaway-squad watch (the reason LDR-training was banned; bounded + elective here, but grill the numbers).

## C. Abilities seeking jobs (the reverse prong — Iosis-unique mechanics wanting owners)

Placed above where obvious; still orphaned or contestable:

- **Downed-clock cruelty** — enemy-only authored job (**Reaper**): adjacent downed units' countdowns tick double. Terrifying, legible, villain-grade. (Player-side clock *extension* went to Sawbones.)
- **Down-cost reduction** (Stoic: my down-cost is 3, not 5) — Pit Fighter? Veteran job? Touches the Will economy's core constant — grill before authoring.
- **Rescue-chain verbs** (carry a downed ally *and* hand off to another carrier in one pass) — Sawbones/Quartermaster pairing; a squad-verb ("stronger with both in the squad").
- **Facing-setter** (an ability that lets a unit *end* its move facing any direction as a locked plan choice, feeding backstrike play) — Skirmisher or Duelist.
- **Weight-shifter** (drop carried inventory as a free action to duck under a shove threshold / swim) — Quartermaster sub or a Movement perk anywhere.
- **Elemental immunities** — **NOT jobs.** Status/element resistance routes through gear/runes (stats.md's CON cut). Jobs get *exploitation* (Opportunist), never immunity.
- **Overwatch, dual-wield, terrain-grinding, alt-fire anything** — **NOT jobs.** Weapon-side, parts system ([weapons.md](weapons.md)).

## Watch-list & fences (carry into the roster pass)

1. **Doctrine fences:** no job grants aura/temper (alchemy's genetics stand); no elemental immunity (gear's lane); no weapon-behavior abilities (parts system's lane); no AI manipulation beyond published policy overrides (taunt-family).
2. **Balance watch:** Deathwish (Crisis gate), Adjutant (LDR pooling), Semaphore (action economy), Ghost (zone stealth vs AI legibility), Riposte (counter economy). Each is previewable and deterministic — the risk is power, not law-breaking.
3. **Economy-dial jobs** (Dowser/Quartermaster camp effects) stay "maybe" — authored dials only, never faucets.
4. **Deferred-system riders:** Beasthandler (taming), backstrike abilities (facing seam), camp multipliers (recovery grill) — author the job, stub the rider.

## First-roster shortlist (Claude's pick, ~8 + story)

**Vanguard · Banneret · Sawbones · Outrider · Wrangler · Pit Fighter · Prosthetist · Lamplighter** (+ story uniques when story lands). Rationale: covers all three postures and both leans; exercises every chassis clause (taunt/guard reactions, Rally enhancer, rescue verbs, the MOV spread 3–6, physics pulls, the C6 flip, prosthetic hooks, focus-fire) with **zero dependency on undesigned systems** — no taming, no backstrike, no materia pass required to ship the first eight.

Cross-refs: [jobs.md](jobs.md) (the chassis this content fills) · [will-and-death.md](will-and-death.md) (re-homed orphans) · [weapons.md](weapons.md) (the parts-system fence) · [squad-system.md](squad-system.md) (C1/C3/C6 touchpoints) · [alchemy-kit.md](alchemy-kit.md) (aura/temper fences).
