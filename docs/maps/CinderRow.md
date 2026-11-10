# Cinder Row

**CLAUDE-AUTHORED, unreviewed.** Board: `Scenarios/missions/CinderRow.tres`. Built 2026-11-10 on
`main` at v0.340.1. Long and narrow (24 x 16, but the playable street is 22 x 3), Extract with a
14-round clock and a protected unit, Ashfall (a look), heat 30% (one step up), Forest Fire look, a
fixed cast of five and no roster. Six enemies in three groups.

## The idea

A street three tiles wide with three yards of thatch opening onto it, each already alight at its far
end. Each fire is a fuse: it burns down its yard a row a round and then cuts the street for five
rounds. You are walking a slow, unarmed man to the far gate. Isaac carries the two time carvings,
which no shipped board has used: **Stillness** holds a fire where it is for two rounds, and
**Quickening** makes it run and burn out at double speed. So the first fire is one to hold back,
the second is one to hurry onto the squad that is standing in its path, and the third is one to
hold again while you get past.

## The map

```
     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3
 0   # # # # # # # # # # # # # # # # # # # # # # # #
 1   # # # # # # # # # # # # # # # # # # ^ ^ ^ # # #     ^  burning at the start
 2   # # # # # # # # # # # # # # # # # # , , , # # #     ,  thatch (tall grass)
 .   (rows 2 to 5: the third yard only)                  s  stone street
 6   # # # # # # # # # # # # ^ ^ ^ # # # , , , # # #
 .   (rows 7 to 9: the second and third yards)
10   # # # # # # ^ ^ ^ # # # , , , # # # , , , # # #
11   # # # # # # , , , # # # , , , # # # , , , # # #
12   # s I s s s , , , s l s W , , s s s , , , E E #     I Isaac  T Torv  S Sara  B Bram
13   # C T s s s , , , s s s , W , s s s , F , E E #     C The Chandler (protected, unarmed)
14   # B S s s s , , , s l s W , , s s s , , , E E #     l Looter   W Wrecker   F The Firestarter
15   # # # # # # # # # # # # # # # # # # # # # # # #     E  extraction (The Far Gate)
```

- **Three bands of thatch** cross the street at columns 6 to 8, 12 to 14 and 18 to 20. Each is the
  foot of a yard: two rows deep for the first, six for the second, eleven for the third.
- **The fuses,** with nobody interfering: the street's north lane in the first band is alight from
  round 3, the second from round 7, the third from round 12. Each band then burns lane by lane for
  five rounds.
- **A unit only burns if it ends its turn on a burning tile.** Walking through costs nothing. So a
  burning band is a wall exactly as thick as your MOV is short, and the Chandler's MOV is 3.

## The encounters

### 1. Looters (filler)

Two Easy thugs, 14 HP, who come through the first band and stop at its near edge on round 1. They
are there to cost you the round in which the first band is still safe to cross.

### 2. The Wreckers (a hazard squad, the hazard latent and on a timer)

| | |
|---|---|
| **Lock** | Three Sentries in Riveted Mail, 22 to 24 HP, hitting for 10, standing shoulder to shoulder in the second band. Three bodies across a three-wide street: nobody passes. Their fire will not reach them until round 7 and will not be done with the street until round 12, which is too late. |
| **Tell** | They are standing on thatch at the foot of a yard that is visibly burning toward them. The Alt outline shows where the fire will be next round. |
| **Key (board)** | Quicken the yard above them as soon as Isaac can reach it (round 4), and the street tiles under them the round after. The fire arrives two rounds early, sweeps the band two lanes at a time, and burns out twice as fast. In my run it took 5 off two of them on round 6, killed one outright on round 7 and downed the boss on round 8. |
| **Key (verbs)** | They never leave the band, so a Carbine and a Freeze work on them from two and three tiles out with no answer. Mail stops half of the Carbine and none of the Freeze. |
| **Window** | Quickening has to land while the fire is still in the yard. From round 6 they are burning; from round 9 the band is ash and open. |
| **Cost of brute force** | A melee unit that goes in stands on the same thatch. The AI-driven baseline lost Bram to the fire and two more to the boss. Downed Wreckers lie where they fell and still block the lane until they bleed out or are finished. |

### 3. The Firestarter (a strong solo, the hazard brought by the enemy)

| | |
|---|---|
| **Lock** | Fire 3 in an Asbestos Shroud, standing in the middle of the third band, which lights behind him on round 12. His Fireball does 8 and lights the thatch under whoever it hits. The Chandler has 12 HP. |
| **Tell** | He stands in the last band with the last yard burning down toward him. |
| **Key (board)** | Hold the third fire with Stillness from the stone just short of the band (round 10). It stays in the yard for two more rounds, which is the two rounds the Chandler needs. |
| **Key (verbs)** | His Fireball cannot reach an adjacent tile. Bram beside him is safe from him, and two Stabs and a Smash finish him. |
| **Window** | Rounds 10 to 12. |
| **Cost of brute force** | Ignoring him means the Chandler walks through his reach twice. Ignoring the fire means the last band is alight when the Chandler gets there. |

## How it was built and checked

- Written by `ScenarioManager.save_scenario` (authored) from a scratch script. A second
  load-and-save writes the same bytes.
- Check board: no BLOCKS and no DEGRADES.
- The twelve suite files that read every mission were run one file at a time with this board on
  disk, and all twelve pass (114 cases).
- **Not checked:** the board has never been opened in the windowed game. A board that is mostly
  rock with three burning chimneys may look like nothing at all. The Forest Fire look and Ashfall
  were chosen by name.

## Runs

| Run | Build | What I did | Result |
|---|---|---|---|
| sim | first draft, four-wide bands | nobody moved; I read off when each lane lit | the timings above. A four-wide band cannot be covered by one Stillness (it is three wide), so the bands became three wide |
| 1 | this layout, 12-round clock | Stillness on round 1, Quickening on rounds 4 and 5, fought the Wreckers from range | **lost on the clock by one round.** Everything else worked. I left the Chandler two tiles further back than he needed to be for four rounds |
| 2 | **this board,** 14-round clock | the same first eight rounds (they replayed identically), the Chandler kept closer, Stillness on the third fire on round 10 | **Victory on round 13 of 14,** all five out. Bram on 8 HP, Sara on 10 with an arm gone, Isaac on 12 |
| blunt | this board, player side on the AI | | **Defeat.** Bram burned to death in the second band, the boss killed Sara and Torv, the Firestarter killed Isaac |

## What I am unsure of

- **Stillness on round 1 may not be needed.** It bought two rounds on the first band, and I used
  them, but I think a tighter player crosses before the fire arrives without it. The first band
  teaches the carving more than it tests it.
- **Quickening is essential and that might be too narrow.** Without it the second band is alight
  from round 7 to round 12 with three armoured men in it, and I do not see another way through in
  time. The second key on the card (range) kills them but does not clear the fire.
- **The Firestarter is weak in practice.** In run 1 he lost an arm to the first Stab and did
  nothing afterwards. In run 2 he hit Isaac once. He never threatened the Chandler.
- **The time marks cover the two rows north of the aimed tile and nothing else.** I only learned
  the shape by casting it. Every yard on this board is north of the street because of that. A yard
  to the south could not be held from the street at all.
- **Fourteen rounds, won on thirteen.** The run is long for a board whose playable area is 66
  tiles, and the last three rounds are walking.

## Waiting on alchemy that is not built

- **A fire that burns a way through.** The yards are sealed by rock. If the looters' barricade were
  a fence that fire opened, the first band could have been a choice between holding the fire and
  letting it clear the road. See the wish list.
- **Still and Quicken on something other than fire.** Both carvings name heat. A mark that held a
  gas, a soaked body or a downed unit's clock would give the escort board a second act: hold the
  smoke, or hold a bleeding ally's last round. The recipes allow it (`Still(X)` for any X); no
  shipped carving says anything but `F`.
