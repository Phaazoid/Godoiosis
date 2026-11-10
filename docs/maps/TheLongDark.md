# The Long Dark

**CLAUDE-AUTHORED, unreviewed.** Board: `Scenarios/missions/TheLongDark.tres`. Built 2026-11-10 on
`main` at v0.340.1. Huge (38 x 24, 912 cells), Extract in 26 rounds, Night look, aether-rich air
(20%), Warband roster with a cap of 6. Sixteen enemies in seven groups.

## The idea

It is the exam. The board is a crossing from the west edge to the east edge, split down the middle
by a ridge of rock. North of the ridge is one road, south of it another, and a gap in the middle
(the Notch) joins them. Each road has two set pieces taken from the earlier boards, and a hunting
squad comes down whichever road the player is on.

Nobody has to be killed. The mission is to get six units to the Far Gate. But each set piece
stands across its road wall to wall, so the choice is which two to solve, not whether.

## The map

```
     0         1         2         3
     01234567890123456789012345678901234567
 2   aaaaaaaaalllwllaaaaawWWWWWwaaaaaaaaaaa     rows 2 to 9: the north road
 3   aaaaaaaaalllwllaaaaawWWWWWwSaaaaaaaaaa     l  limestone (the Kiln Yard)   w  the drain
 4   aaaaaaaaal%%wllaaaaawWWWWWwaaaaaaaaaaa     %  quicklime, with the Lime Burners on it
 5   aaaaaaaaalBBwllaaaaaw_____wTaaaaaaaaaa     W  the Mere (deep)   _  the ice causeway
 6   aaaaaaaaalB%wllaaaaaw_____waaaaaaaaaaa     T  Thaw Warden   S  Shore Shot   H  Shore Hand
 7   aaaaaaaaal%%wllaaaaawWWWWWwHaaaaaaaaaa
 8   aaaaaaaaalllwllaaaaawWWWWWwaaaaaaaaaaa
 9   aCaaaaaaalllwllaaaaawWWWWWwaaaaaaaaGGa     C  The Camp (deployment, rows 9 to 14)
10   aCaaaaa##########aa#############aaaGGa     G  The Far Gate (rows 9 to 14)
11   aCaaaaa##########aa#############aaWWGa     W W  The Wardens (four, Rushdown; one starts on the Gate)
12   aCaaaaa##########aa#############aaWWGa        the gap at columns 17 and 18 is the Notch
13   aCaaaaa##########aa#############aaaGGa
14   aCaaaaaaaaaPaaaaaaaaa####aaaaaaaaaaGGa     rows 14 to 21: the south road
15   aaaaaaaaawwwwwaaaaaaa####aaaaaaaaaaaaa     P  Pool Guard (one north of the pool, one south)
16   aaaaaaaaawwwwwaaaaaaa####aaaaaaaaaaaaa     the pool, with the Galvanist (Z) on a dry tile
17   aaaaaaaaawwZwwaaaaaaaaaaaKMaaaaaaaaaaa     on a lightning vein
18   aaaaaaaaawwwwwaaaaaaaaaaaXaaaaaaaaaaaa     #### the Cut: rock, with a two-wide trench
19   aaaaaaaaawwwwwaaaaaaa####aaaaaaaaaaaaa     K  Cut Captain   M  Marksman   X  Cutter
20   aaaaaaaaaaaPaaaaaaaaa####aaaaaaaaaaaaa
21   aaaaaaaaaaaaaaaaaaaaa####aaaaaaaaaaaaa
```

Rows 0, 1, 22 and 23 are rock. Everything marked `a` is sand: it holds no fuel, no salt and no
water, so away from a wall a Rock Throw fizzles and a fire does not spread.

## The groups

### North 1. The Lime Burners (hazard squad, the hazard under their feet)

| | |
|---|---|
| **Lock** | Three Sentries in Riveted Mail with CON 12. A carbine does 2 to them. They hold the Kiln Yard, which is the whole width of the road. |
| **Tell** | They are standing on quicklime, beside a drain. |
| **Key** | Splash, then Zap. The Splash wets two of them and slakes the quicklime into scalding steam. The Zap does 15 each and goes through mail. A second Zap a round later finished two of them and the steam finished the third. |
| **Cost of brute force** | The baseline walked in. All three of its first deaths were here. |

Round 4 to round 5 in my run. They came off the quicklime to hit the two casters for 17 between
them.

### North 2. The Shore Watch (a fire caster across the ice)

| | |
|---|---|
| **Lock** | The Mere is five tiles of deep water with a frozen causeway two tiles wide. The Thaw Warden on the far shore has a Fireball: he melts the tile you stand on, you drown, and his Shot finishes you. His reach ends two tiles from the shore. |
| **Tell** | A fire caster and a road made of ice. |
| **Key** | Stop on the third ice tile, one outside his reach. Next round the far bank is one move away: stand in the shallows, which are water and cannot be melted, and strike. He has 18 HP. A Stab and a shot downed him before he cast once. |
| **Cost of brute force** | Ending a turn on the last two ice tiles. I did not test it here; The Drowned Orchard's note has what it looks like. |

His two guards then put two of my units down, both through my own carelessness (a Stab I did not
preview drew a counter).

### South 1. The Galvanist's Pool (a strong solo the road goes round)

A caster on a lightning vein in the middle of a pool, with a guard on the dry strip either side.
The strip to the north is one tile wide between the pool and the ridge. I killed the north guard
and walked the strip; the Galvanist never had a target. He is there to be respected, and to punish
a unit that wades.

### South 2. The Cut (a strong squad that holds, and can be out-ranged by one tile)

| | |
|---|---|
| **Lock** | A wall of rock with a trench through it, two wide and four long. Three units Hold the far end: Captain, Cutter, Marksman. A unit that attacks from beside them takes all three answers at once. That killed Torv on the first attempt: 27 damage in one reaction. |
| **Tell** | They do not move. The Marksman's Overwatch lane is drawn down the upper file of the trench. |
| **Key** | Count the tiles. A Freeze reaches three and a Spring reaches two; a mace reaches one and the carbine reaches exactly two. From the third tile of the lower file, Freeze hits them and nothing hits back. From the second, a Spring does. The Captain Guards the Cutter, so the first blows land on him. All three were down in four rounds for one Overwatch shot taken. |
| **Cost of brute force** | See the runs below. |

### The Wardens (the hunting squad)

Captain, two Wardens and a Mender, Rushdown, starting at the Far Gate. They take whichever road
leads to the nearest player unit and arrive on round 5 or 6.

- **On the south road** they come out of the Cut's trench. I met them at its mouth with a first
  strike and it still cost about 30 damage. Their Mender heals the downed: a healed body stays
  down, stops bleeding, and blocks its tile until someone kills it.
- **On the north road** they cross the ice (out of reach of anything I had) and then wade the
  Kiln Yard's drain. Two Zaps, a Freeze and two shots destroyed all four between round 9 and
  round 10. They did no damage at all.

## How it was built and checked

- Written by `ScenarioManager.save_scenario` (authored) from a scratch script. A second
  load-and-save writes the same bytes.
- Check board: no BLOCKS and no DEGRADES.
- The twelve suite files that read every mission were run one file at a time with this board on
  disk, and all twelve pass (114 cases).
- **Not checked:** the board has never been opened in the windowed game. It is 38 tiles wide and
  mostly bare sand between the set pieces. I do not know how it frames, or how long the walking
  feels with a mouse.

## Runs

| Run | Road | Build | What happened | Result |
|---|---|---|---|---|
| 1 | south | first draft: the Cut held by four Sentries | Pool Guard and Wardens beaten by round 10 with no losses. In the trench an attack I did not preview drew three reactions and killed Torv; a downed unit lay in the firing lane | abandoned on round 13. The Cut lost its Bulwark; its Marksman went from 16 HP to 12; the clock went from 24 to 26 |
| 2 | south | second draft | the same ten rounds. Entered the trench with the two line attackers in front; the first of them was downed before he acted | abandoned on round 12 |
| 3 | south | third draft: the Cut's zone widened so they would come out | they came out six rounds early and joined the Wardens | abandoned on round 7. The Cut became three Hold units at the trench's east end |
| 4 | south | **this board** | Wardens beaten by round 8, the Cut by round 15 from outside its reach. Then nine rounds of walking, at the pace of a unit that had lost a limb and moved two tiles a round | **Victory, round 24 of 26.** All six out |
| 5 | north | **this board** | Lime Burners by round 5, Wardens by round 10, Shore Watch by round 16 | **Victory, round 22 of 26.** All six out, two of them rescued on round 16 |
| blunt | north (the AI's choice) | this board, player side on the AI | | **Defeat on round 14.** At least four of six dead |

## What I am unsure of

- **The two roads are not equal.** The north road was won on its first attempt and the south took
  four, three of them spent on the Cut. Some of that is the Cut's redesigns and some is that the
  north road's answers (Splash then Zap, stop short on the ice) are ones I had already learned
  on other boards. A player who has not played those boards meets them cold.
- **The walking.** The south run spent rounds 15 to 24 walking with every enemy dead. The clock is
  set by the slowest wounded unit, not by any fight. A shorter board, or a Far Gate nearer the
  last set piece, would lose nothing.
- **The Cut is a puzzle about ranges and nothing else.** Once the tiles are counted it is safe and
  slow. It reads as a shooting gallery from the right tile and a massacre from the wrong one, with
  one tile between them. Holding units cannot answer; the bug log's S13 is the same complaint
  from the other side.
- **The Notch was never used.** It is there so a party that fails at one road's second piece can
  cross to the other. Neither winning run needed it and the losing runs were too hurt to try.
- **The Galvanist does nothing.** The dry strip north of his pool is out of his reach by one tile.
- **The aether-rich air mattered a little.** Heals read +9 against a usual 7, and Freeze
  +2. Then my own Freezes left frost, which took the 2 back: the third cast in the same trench did
  6. I did not plan that and I like it.
- **Six is the cap and I never tried fewer.**

## Waiting on alchemy that is not built

- **Raised earth.** In the Cut, a wall across the trench behind the Captain cuts the Marksman's
  line and his Guard. The tile is (26,17). On the ice, a wall on the far bank at (26,5) blocks the
  Thaw Warden's line to the causeway for the turn the party crosses.
- **A fire the player can throw three tiles.** The Wardens crossed the causeway in single file on
  rounds 5 and 6, eleven tiles from my nearest unit. One melted tile would have drowned two of
  them. Nothing in the kit reaches.
- **A carving that dries.** The whole party ended the north road Wet from the shallows, standing
  in a conductor, one Zap from killing itself.
