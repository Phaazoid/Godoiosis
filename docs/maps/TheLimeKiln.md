# The Lime Kiln

**CLAUDE-AUTHORED, unreviewed.** Board: `Scenarios/missions/TheLimeKiln.tres`. Built 2026-11-10 on
`main` at v0.340.1. Small (14 x 12), Rout, no clock, clear sky, Normal air, Warband roster with a
cap of 4. Six enemies in three groups.

## The idea

A limestone yard that has already been burned to quicklime at its lip. Three armoured guards stand
in it and nothing physical dents them. Water on the quicklime makes a steam cloud that soaks them
from a distance, and a drain runs out of the yard to where you stand, so a shock put into the drain
reaches every soaked guard at once. It is the first board that uses a ground reaction.

## The map

```
     0 1 2 3 4 5 6 7 8 9 0 1 2 3
 0   # # # # # # # # # # # # # #
 1   # s L s s L s # a a a a a a     s  stone floor (the kiln floor is one level up)
 2   # s s s s K s # a a a a a a     L  lantern (a lit prop: a source of fire)
 3   # s s s s s s < a a a a , ,     <  ramp up to the kiln floor
 4   # l l l l l s a a a a h , ,     l  limestone     a  sand     ,  tall grass
 5   # l G S G l s # a a a a h .     %  quicklime (limestone, already burned)
 6   # l % w % l s # a a a a a a     w  shallow water: the drain
 7   s s s w s s s s a a a a a a     #  rock
 8   s s s s s s L s a a a . . .
 9   s s s s s s s s a a . . . .     K Kilnmaster   S Kiln Sergeant   G Kiln Guard
10   . . . . D D D D D . . . . .     h Yard Hand    D deployment (The Gate)
11   . . . . D D D D D . . . . .
```

- **The yard** is columns 1 to 5, rows 4 to 6, and it is the guards' patrol zone. Its south edge is
  open. The Sergeant stands in the head of the drain at (3,5) with a Guard on each side.
- **The quicklime** is two tiles, (2,6) and (4,6), either side of the drain.
- **The drain** is three tiles of shallow water, (3,5) to (3,7), ending one row outside the yard.
- **The kiln floor** is one level up: the stone at rows 1 to 3 and the walkway down the yard's east
  side, column 6, rows 4 to 6. It is the Kilnmaster's patrol zone. The only way up is the ramp at (7,3).
- **The south court** is stone, so a fire there does not spread. The only grass is the deployment
  strip and the south-east corner.

## The encounters

### 1. Yard Hands (filler)

Two Easy thugs, 16 HP, who rush from the east and arrive at the deployment pad on round 3. They hit
for 6. They are there to be dealt with while the yard waits, and to punish sending one unit off alone
(in my first run they took 17 HP off Bram in two turns).

### 2. The Kiln Guard (a hazard squad, the hazard latent)

| | |
|---|---|
| **Lock** | Three Sentries in Riveted Mail with CON 12: DEF 10 against every physical hit. A Carbine does 2 and a Springspear 2. Each hits for 10, which takes a limb, and they Rev every turn, so your own armour does not help. |
| **Tell** | The queue previews 2 damage and three counters. The two yard tiles in front of them read Quicklime on the tile card, which lists the reaction: water slakes it into steam. The Sergeant is standing in the drain. |
| **Key (board)** | Splash the quicklime from row 8. Thick steam rises on both tiles, and at the round's end it spills, medium, onto the two Guards. At the end of their next turn they are scalded for 2 and left Wet. Then Zap the drain mouth at (3,7): the current runs up the water to the Sergeant's tile and from there into both soaked Guards. |
| **Key (verbs)** | Any carving that is not physical gets through the mail. Splash and then a shock works on any one of them you can reach. |
| **Window** | The steam must have one full enemy turn to soak them: Splash on round 2, the first full chain on round 4. The cloud scalds for two rounds and can be rebuilt (a fire hit turns limestone back into quicklime). |
| **Cost of brute force** | Row 7 is inside their reach, and so is everything in the yard. A melee squad walking in loses limbs for 2 damage a swing. The AI-driven baseline lost all four units and killed one Yard Hand. |

What the numbers did in the intended run, with Dorian (Aether 5) casting Zap: the Sergeant took 10
from each Zap through the drain, the two soaked Guards 15 each, all three lost limbs to the first
chain, and the squad was gone on round 5 without touching anyone.

### 3. The Kilnmaster (a strong solo)

| | |
|---|---|
| **Lock** | 30 HP, Fire 3, an Asbestos Shroud: Fireball for 8 at range 2, and he counters anything that attacks him from range 2. Fire and steam do nothing to him. Beside one of his lanterns his Fireball becomes Fireburst, 7 on a five-tile plus. |
| **Tell** | He is a Sentry on the raised floor, and he walks to the edge of the walkway to shoot whoever stands in reach below. The enemy-range view shows the cells. |
| **Key (board)** | His Fireball cannot hit an adjacent tile, so a unit beside him is safe from him. The walkway's edge is one level above the yard: a Spring reaches up it, a Stab does not. Stone to stand on beside the walkway makes Rock Throw available as an answer to his counter. |
| **Key (verbs)** | Bait him to the walkway's edge with a unit that can take one hit, then kill him in a single pass with a squad: a felled unit does not counter. Or soak yourself first, which halves his fire. |
| **Window** | He stays where he last fired from until nobody is in reach, then walks home. |
| **Cost of brute force** | Every ranged poke at range 2 eats an 8-point counter. Two units trading pokes with him go down before he does. |

## How it was built and checked

- Written by `ScenarioManager.save_scenario` (authored) from a scratch script that paints through
  the game's own doors. A second load-and-save writes the same bytes (the first re-save after the
  build changes the file once, then it is stable).
- Check board: no BLOCKS and no DEGRADES.
- The twelve suite files that read every mission were run one file at a time with this board on
  disk, and all pass (114 cases): `dev/test_board_lint`, `dev/test_dev_tree`,
  `law/test_every_mission_can_be_won_on_foot`, `law/test_resource_uid_references`,
  `law/test_no_embedded_carvings`, `law/test_embedded_carvings_are_legal`,
  `law/test_no_embedded_image_resources`, `law/test_a_board_round_trips_its_tiles`,
  `flow/test_scenario_load_integrity`, `flow/test_roster_binding`, `flow/test_demo_mission_gate`,
  `presentation/test_camera_pan_limit`.
- **Not checked:** the board has never been opened in the windowed game. Nobody has looked at it.

## Runs

| Run | Build | Team | Result |
|---|---|---|---|
| 1 | first draft (grass court, guards on raw limestone) | Isaac, Dorian, Sophia, Celest | abandoned on round 5: one Fireball at a Yard Hand set the whole court alight, and the board filled with smoke and scalding steam |
| 2 | stone court, guards standing on quicklime | same | **Victory, round 5.** Too easy: Splash wets the guards directly, so the quicklime added 3 damage a turn and nothing else |
| 3 | guards a row back, a trough between | Isaac, Dorian, Sophia, Bram | abandoned: a shock into the trough does not reach guards two tiles away. The current only moves between touching conductors |
| 4 | **this board** (the drain) | Isaac, Dorian, Sophia, Bram | **Victory, round 7,** no deaths. Sophia was downed in a counter duel with the Kilnmaster that I should not have taken with 16 HP |
| blunt | this board, player side on the AI (Torv, Marco, Sara, Bram) | | **Defeat.** It walked into the yard. One Yard Hand killed |

The blunt baseline is the game's own AI playing the player's default four with no alchemy. It is a
floor, not a good player. A careful player who ignores the quicklime can still win slowly: Zap the
drain to kill the Sergeant alone (three casts), then trade for the Guards.

## What I am unsure of

- **Is it too much of a puzzle?** The safe line needs three things noticed: the quicklime, the
  spill, and the drain. A player who sees only "wet them, then shock them" has to stand on row 7 to
  do it and takes hits.
- **Dorian trivialises shock.** His Zap is 10 dry and 15 on a wet target. With Aldin or Isaac
  casting, the same line takes a round or two longer. I tuned HP against Dorian.
- **Steam's damage is small** (2 or 3 a turn against 20 HP and up). The map leans on the soak, not
  the scald.
- **The Kilnmaster lost a duel to Rock Throw counters.** A unit on stone answers his Fireball with a
  10. That may be too soft for the "strong solo".
- **Fire has no job for the player here** beyond re-burning the lime. Celest sat out the winning run.

## Waiting on alchemy that is not built

Nothing on this board needs an unbuilt mechanic. Two things would change it if they existed, and
both are on the wish list: an enemy who throws water (so the enemy could spring the quicklime on
you first and teach it), and rain slaking quicklime (which would make a weather draw matter here).
