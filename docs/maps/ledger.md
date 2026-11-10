# Variety ledger

**CLAUDE-AUTHORED, unreviewed.** Written before the first map so that map 9 is not map 2 again.
The plan below is a starting list, not a commitment: a map that does not work is redesigned or
shelved, and the row says so. Status is one of *planned*, *building*, *done*, *shelved*.

## What already ships, so these do not repeat it

| Mission | Size | Objective | What it is about |
|---|---|---|---|
| Terraces | 13 x 14 | Rout | height |
| The Ford | 18 x 12 | Capture, 12 rounds | freeze a river crossing |
| The Causeway | 20 x 13 | Capture | a one-tile bridge and a sentry leash |
| The Dry Field | 20 x 12 | Extract | spreading grass fire, hot dry air |
| The Quarry | 22 x 16 | Rout | height, a drowned pit, a Zap caster |
| The Gorge | 36 x 24 | Capture two points | multi-squad, holes, a ford |
| The Switchbacks | 32 x 26 | Capture and Rout | a climb |
| Hold the Pass | 30 x 30 | Rout, three defended gates | waves |

None of them uses: a weather that moves the air, a drawn weather set, a vein, a ground reaction
(quicklime, thunderstone, brick, gypsum, quicksilver), smoke as a tool, a time mark, an escort, or a
board with a fixed cast and no roster since the tutorial.

## The axes

- **Size:** tiny (under 100 cells), small (100 to 200), medium (200 to 450), large (450 to 900), huge (over 900).
- **Win:** Rout, Capture, Extract, or two together.
- **Lose (beyond a wipe):** none, a round limit, a defended point, a protected unit.
- **Sky and air:** the weather, and any authored air reading.
- **Cast:** a roster with a cap, a fixed cast, or a roster plus a placed guest.
- **Alchemy spine:** the one or two Deep Alchemy rules the hard encounters turn on.
- **Hard shapes** (from the encounter-design notes, #1649): *strong squad* (overpowered, easy to
  separate), *strong solo* (no squad to lean on), *hazard squad* (powerful, standing by a silly
  kill). Every map has at least two encounters and names which shapes they are.

## The plan

| # | Name | Size | Win | Lose | Sky and air | Cast | Alchemy spine | Hard shapes | Status |
|---|---|---|---|---|---|---|---|---|---|
| 1 | The Lime Kiln | small | Rout | none | clear, Normal | Warband, cap 4 | quicklime slaked into steam that soaks from a distance; a drain carries the shock | hazard squad (latent), strong solo, filler | **done** |
| 2 | Chaff | medium | Extract | round limit (12) | Dust (a look), vapor 0% | Basics, cap 4, plus a guest with Smokescreen | burning chaff heaps make smoke that shortens a hunting squad's leash; Freeze slows the giant | strong squad, strong solo (slow), filler | **done** |
| 3 | Meltwater | medium | Capture | none | Light Snow (heat down a step) | Warband, cap 5 | ice over deep water is the road and the trap; fire melts it, Freeze rebuilds it, open water carries a shock | hazard squad (present), strong solo on water, a fire Sentry who melts you, filler | **done** |
| 4 | The Salt Stair | medium, tall, four heights | Capture | none | clear, a Gale (look only) | Warband, cap 4 | Gust over a void: a shove that ends in a hole is a death, and the counter-shove is too; one backstop tile per enemy | two strong solos who bring the hazard, a hazard squad on a ledge with a captain too heavy to shove, filler | **done** |
| 5 | Stormgate (was Stormglass) | medium | Rout | defended point | Thunderstorm (everyone ends Wet, vapor up three) | Warband, cap 5, plus an AI-run allied squad | rain soaks every body each turn, so every shock chains through friend and foe alike; Freeze on a Wet body | strong squad the rain links together, two strong solos who bring the hazard, an ally standing in the chain, filler | **done** |
| 6 | The Glass Walk (was The Cellar) | tiny | Rout | round limit (10) | none; Night | fixed cast of three, no roster | a lightning vein, and sand fused to thunderstone as stepping stones for a Zap with no diamond; a pool that conducts | hazard squad that wades into its hazard, strong solo, filler | **done** |
| 6b | The Cellar | tiny | Rout | round limit | none indoors; aether-rich air | fixed cast | essence and frost move a Heal; kill order | strong solo with a healer | planned, lower priority: I could not find an alchemy hook strong enough |
| 7 | Cinder Row | long and narrow | Extract | protected unit and a round limit (14) | Ashfall, heat 30% | fixed cast of five, one of them the escort | Stillness holds a fire, Quickening hurries one: three burning yards as fuses onto a three-wide street | hazard squad on a timer, strong solo in the last fire, filler | **done** |
| 8 | The Lodes (was Quicksilver Flats) | large | Capture three | none | Aurora (aether up two), Night | Warband, cap 7 | veins: each site's caster is nothing off his vein, and the vein tile is the only capture tile; an unguarded alkahest vein in the middle | strong solo in a conducting pool, strong squad hunting, hazard squad in tall grass, strong solo behind a Guard | **done** |
| 9 | The Drowned Orchard | medium | Rout | none | drawn: Clear, Fog or Rain | Basics, cap 5 | mud and loam feed water carvings; wet then ice; water-walkers | strong solo that ignores terrain (Overwatch key), hazard squad | planned |
| 10 | Earthworks | medium | Rout | defended point | clear | Company | **unbuilt:** raised earth walls. Playable today with cover and choke points; the note marks where a wall would go | strong squad to be cut in two | planned |
| 11 | Three Banners | small | Rout | none | clear | fixed cast | a third faction hostile to both; turn their fire and gas on each other | two rival squads, one solo | **shelved:** the hostility table has no third side (wish list). An AI-run ALLY squad is possible and may replace it |
| 12 | The Long Dark | huge | Capture and Rout | round limit | Night, drawn weather | Warband, cap 9 | everything above, as an exam | all three | planned |

## Built so far

Each finished map gets a row here with its real numbers.

| # | Board | Cells | Enemies | Won by me in | Blunt baseline | Note |
|---|---|---|---|---|---|---|
| 1 | `TheLimeKiln.tres` | 14 x 12 | 6 in 3 groups | 7 rounds, no deaths | AI-driven default four: defeat | [TheLimeKiln.md](TheLimeKiln.md) |
| 2 | `Chaff.tres` | 22 x 13 | 8 in 4 groups | round 11 of 11 (clock since raised to 12), all five out, three on 1 or 2 HP | AI-driven default four plus the guest: defeat by round 5 | [Chaff.md](Chaff.md) |
| 3 | `Meltwater.tres` | 22 x 16 | 8 in 5 groups | 9 rounds, no deaths (an earlier draft: 13 rounds, one death) | AI-driven default five: defeat | [Meltwater.md](Meltwater.md) |
| 4 | `TheGlassWalk.tres` | 13 x 7 | 5 in 4 groups | 8 rounds of 10, no deaths, first layout | AI-driven fixed cast: defeat | [TheGlassWalk.md](TheGlassWalk.md) |
| 5 | `CinderRow.tres` | 24 x 16 (street 22 x 3) | 6 in 3 groups | round 13 of 14, all five out (a 12-round draft was lost by one round) | AI-driven fixed cast: defeat | [CinderRow.md](CinderRow.md) |
| 6 | `TheSaltStair.tres` | 14 x 17 | 7 in 4 groups | round 11, no deaths (a first draft was shelved: one long-range gun beat it) | AI-driven default four: defeat, one unit blown into the void | [TheSaltStair.md](TheSaltStair.md) |
| 7 | `TheLodes.tres` | 30 x 18 | 13 in 7 groups | round 16, no deaths, four of seven on 2 or 3 HP | AI-driven default seven: defeat, five of them to one caster | [TheLodes.md](TheLodes.md) |
| 8 | `Stormgate.tres` | 20 x 16 | 9 in 4 groups, plus 3 allied | round 9, no player deaths, three of five on 5 HP or less (three earlier runs lost) | AI-driven default five: victory with one survivor, ended by a Storm Caller shocking himself | [Stormgate.md](Stormgate.md) |
