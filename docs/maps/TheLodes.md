# The Lodes

**CLAUDE-AUTHORED, unreviewed.** Board: `Scenarios/missions/TheLodes.tres`. Built 2026-11-10 on
`main` at v0.340.1. Large (30 x 18), Capture three sites, no clock, Aurora (aether up two steps),
Night look, Warband roster with a cap of 7. Thirteen enemies in seven groups.

## The idea

Three materia veins on a sand flat, each with a caster standing on it who is nothing without it.
The Stonecaller has no rock within reach except his earth vein. The Galvanist carries no diamond and
draws his lightning from the vein under his feet. The Kindler's Fireball only becomes a five-tile
Fireburst because he stands on a fire vein. Each vein tile is also the only capture tile of its
site. So every site asks the same question a different way: how do you get that caster off that
tile? A fourth vein, alkahest, lies unguarded in the middle and empowers everything, and a hunting
squad arrives in time to contest it. It is the first board whose fights are about veins.

## The map

```
     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9
 1   a a a a a a a a a a a a a a a a a a a a a a a a a P P a a a     P  The Prospectors (four)
 2   a a a a a a a a a a a a a a a a a a a a a a a a a P P a a a
 3   a a a a a a a a a a a a a w w w w w a a a a a a a a a a a a     w  shallow water (the pool)
 4   a a a a a a a a a a a a a w w w w w a a a a a a a a a a a a
 5   a a a a a a a a a a a a a w w Z w w a a a a a a a a a a a a     Z  Galvanist, on the lightning vein
 6   a a a # a a a a a a a a a w w w w w a a a , , , , , , , a a     ,  tall grass (the seam field)
 7   a a a a a a a a a a a a a w w w w w a a a , , , a , , , a a
 8   a a a a a S a a a a a a a a g a g a a a a , s a K a s , a a     S  Stonecaller, on the earth vein
 9   a a a a L a L a a a a a a a a a a a a a a , , , a , , , a a     K  Kindler, on the fire vein
10   a a a a a a a # a a a a a a a a a a a a a , , , , , , , a a     L  Lode Guard   g  Pool Guard
11   a a a a a a a a a a a a a a a A a a a a a a a a a a a a a a     s  Seam Guard
 .   (rows 12 to 14: open sand)                                      A  the alkahest vein, unguarded
15   a a a a a a a a a a a a D D D D D D a a a a a a a a a a a a     D  deployment (The Camp)
16   a a a a a a a a a a a a D D D D D D a a a a a a a a a a a a
```

- **Each capture zone is one tile:** the vein tile, with its keeper on it. Nobody can run in and
  claim a site while the keeper stands there.
- **The pool** is five by five with one dry tile in the middle. Every tile within two of the
  Galvanist is water.
- **The seam field** is tall grass, seven by five, with a cross of bare sand at its centre.
- **Everything else is sand,** which holds no salt, no ash and no water. Away from a vein, Rock
  Throw and Smokescreen fizzle on this board.

## The encounters

### 1. The Spark Pool (a strong solo, the hazard present)

| | |
|---|---|
| **Lock** | The Galvanist's Zap does 8 dry and 13 to anything Wet, and everything in reach of him is wading. The current then runs through the water into every other wader within three tiles. In the AI-driven baseline he landed six 13-point hits and killed three units by himself. Two guards stand on the dry south rim. |
| **Tell** | He stands on one dry tile in the middle of a pool, with no diamond in his kit. His Zap row reads its need: lightning within a tile. |
| **Key (board)** | Gust reaches three tiles, one more than he does. From the dry rim it shoves him two tiles off the vein into his own pool. His card then reads "Fizzles: needs a source of lightning within 1 tile", and he does nothing for the rest of the mission. |
| **Key (verbs)** | Freeze the water: ice does not conduct and a unit on it is dry. Or let Dorian take the vein once it is empty and return the favour. |
| **Window** | Any time. He never moves. |
| **Cost of brute force** | Wading in. See the baseline. |

### 2. The Prospectors (a strong squad)

| | |
|---|---|
| **Lock** | A Rushdown squad of four with a Mender: a Foreman with a mace, two cutters, and a healer whose Heal is 10 under the Aurora. They come down the east side and reach the middle on round 4. |
| **Tell** | They are the only group that moves on round 1. The Aurora is on the pre-mission screen and in the corner of the HUD: aether up two steps. |
| **Key (board)** | The alkahest vein at (15,11). A fire caster beside it fires Fireburst, and the squad arrives packed two by two. The Aurora that feeds their Mender also feeds a Freeze: Isaac's did 10. |
| **Key (verbs)** | Be one tile outside their reach on the turn they arrive, so they stop short and you strike first. Kill the Foreman and the squad falls apart: the Mender becomes its leader. |
| **Window** | Round 5, the turn after they stop. |
| **Cost of brute force** | Four attacks on arrival. The baseline lost Sara and Isaac to them. |

In my run they arrived, could reach nobody, and the Foreman was dead before any of them had swung:
Fireburst 6, Freeze 10, Zap 10, Smash 10.

### 3. The Ember Seam (a hazard squad, the hazard brought by the enemy)

| | |
|---|---|
| **Lock** | The Kindler's Fireburst is 7 on a five-tile plus, and the plus reaches a tile further than a Fireball does. He wears an Asbestos Shroud. Two guards stand in the tall grass around him, one with a Carbine and an Overwatch lane across the field. Any fire in that grass spreads eight ways. |
| **Tell** | Tall grass, a fire caster in the middle of it, and the Fireburst line on his card. |
| **Key (board)** | Burn the field first. One Fireball on its west edge and the grass is ash in five rounds; the guards come out of it to you, one at a time. Then he is a man on a tile with no fuel around him. |
| **Key (verbs)** | A unit beside him cannot be aimed at, though his plus can still catch it by aiming at the tile behind. Two units finish him in two turns. |
| **Window** | After the field has burned: from about round 12 in my run. |
| **Cost of brute force** | Walking into the grass puts you on fuel under a Fireburst and inside an Overwatch lane. |

### 4. The Salt Lode (a strong solo behind a wall)

| | |
|---|---|
| **Lock** | Two Lode Guards with CON 12 in Riveted Mail (DEF 10) and a Stonecaller between them whose Rock Throw does 9 and answers anything at range 2. One guard Guards him: a blow meant for the Stonecaller lands on the mail. |
| **Tell** | The queue: a Freeze aimed at him previews as hitting "Lode Guard, guarding Stonecaller". |
| **Key (board)** | His earth vein is the only salt for twenty tiles. Off it he fizzles. A Gust would do it; I did not have Isaac on that side. |
| **Key (verbs)** | Zap pierces a Guard. A Spring from two tiles away reaches him over the guard's shoulder. Neither guard moves more than two tiles a turn, so a unit three tiles out is safe from them. |
| **Window** | Any time, slowly. |
| **Cost of brute force** | Physical damage does nothing to the guards and the Stonecaller counters every poke. Bram took 18 for one Spring. |

## How it was built and checked

- Written by `ScenarioManager.save_scenario` (authored) from a scratch script. A second
  load-and-save writes the same bytes.
- Check board: no BLOCKS and no DEGRADES.
- The twelve suite files that read every mission were run one file at a time with this board on
  disk, and all twelve pass (114 cases).
- **Not checked:** the board has never been opened in the windowed game. I have not seen a vein, an
  Aurora or the Night look. A 30-wide board of mostly bare sand may look empty.

## Runs

| Run | Build | What I did | Result |
|---|---|---|---|
| 1 | first draft: three-by-three capture zones with the keepers beside the veins | took the pool by round 4 and broke the Prospectors on round 5 | abandoned on round 6 when I saw the cheap win: a fast unit could run onto a free zone tile and capture a site without fighting anyone. Each zone became the one vein tile with its keeper standing on it |
| 2 | **this board** | the same six rounds (they replayed identically); then split the force: burned the seam field and took the Kindler in the east, froze and zapped through the Salt Lode's guard in the west | **Victory, round 16,** no deaths. Four of seven units ended on 2 or 3 HP |
| blunt | this board, player side on the AI | | **Defeat.** The Galvanist alone downed or killed five units in the pool |

## What I am unsure of

- **The Salt Lode is the weakest site.** Its key is "shove him off the vein", and the two guards
  with DEF 10 around him just make that slow. I got through with a Zap that pierces Guard and a
  bleed-out timer, which is attrition, not an answer.
- **Splitting the force was my choice, and it was nearly fatal.** Both halves ended with units on
  2 HP. A player who keeps seven together has an easier and much longer mission.
- **Sixteen rounds.** Rounds 7 to 11 were mostly walking and waiting for grass to burn.
- **A downed keeper holds his tile for three rounds.** The body blocks the capture tile until it
  bleeds out or is struck again. Twice the mission waited on that. It reads as a rule working and
  plays as a pause.
- **The Aurora mattered once.** It added 2 to one Freeze and 2 to the Mender's Heal. I am not sure
  a player would notice it without the queue tip.
- **The alkahest vein did its job in one cast** and was then behind the lines for the rest of the
  mission. It wants a reason to be held.
- **Isaac is doing three jobs** (Gust, Freeze, and I never gave him the Fire Rune). Warband has one
  other unit who can channel Gust. The pool has only one clean answer if Isaac is not brought.

## Waiting on alchemy that is not built

- **A drill that opens or buries a vein.** With it, the answer to a keeper could be to bury the
  vein under him, and the alkahest vein could be something the player uncovers. The four vein tiles
  are where it would act.
- **Hidden veins.** The Salt Lode's guards would make more sense standing over something the player
  cannot yet see.
- **Raised earth.** A wall between the Stonecaller and his guards would take the Guard off him for
  a turn. The tile is (5,9), between the two Lode Guards.
