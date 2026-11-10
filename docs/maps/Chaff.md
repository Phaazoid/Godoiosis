# Chaff

**CLAUDE-AUTHORED, unreviewed.** Board: `Scenarios/missions/Chaff.tres`. Built 2026-11-10 on `main`
at v0.340.1. Medium (22 x 13), Extract with a 12-round clock, Dust (a look), vapor 0%, Basics roster
with a cap of 4 plus a placed guest. Eight enemies in four groups.

## The idea

A threshing floor at dusk: stone, with six heaps of dry chaff on it. A five-strong squad hunts you
across it and a slow giant follows them. You have to get everyone to the far road before the clock
runs out, and the squad's first charge kills two of you if you stand and take it. The chaff is the
answer three ways: lit, it is a wall of fire and smoke the squad walks into; its smoke shortens the
captain's leash, so the squad arrives packed and short of reach; and the scorched ground it leaves
is the ash a Smokescreen needs.

## The map

```
     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 0   a a a a a a a a a a a a a a a a a a a a a a
 1   a T a a a a g a a a , , a a a a a a a a T a     a  sand        s  stone floor
 2   a a a a a a s s s s , , s s s s s a a a a a     ,  chaff heap (tall grass)
 3   a a W s s s s s s s s s s s s s s s s s s a     T  tree
 4   a a D D s s , , s s s s s s , , s s s E E a
 5   a a D D s s , , s s s s s R , , s s s E E a     D  deployment (The West Gate)
 6   a a D D s s s s s s s s s R C R s s s T E s     E  extraction (The East Road)
 7   a a D D s s , , s s s s s R , , s s s E E a
 8   a a D D s s , , s s s s s s , , s s s E E a     W  Wren (placed guest)
 9   a a s s s s s s s s s s s s s s s s s s s a     C  Reap-Captain   R  Reaper
10   a a a a a a s s s s , , s s s s s a a a a a     T  (19,6) The Thresher
11   a T a a a a g a a a , , a a a a a a a a T a     g  Gleaner
12   a a a a a a a a a a a a a a a a a a a a a a
```

- **Six chaff heaps**, each two by two, each at least two tiles from the next, so a fire in one
  never jumps to another. Nothing else on the floor burns: the margins are sand.
- **The two west heaps** at columns 6 to 7 sit one tile in front of where the player's line
  naturally forms. That is deliberate: the fight happens beside them.
- **The floor is open.** There is no choke. (An earlier draft had stone posts; see the bug log, B2.)

## The encounters

### 1. Gleaners (filler)

Two Easy thugs, 14 HP, one from each side. They reach the deployment on round 1 and hit for 7. They
cost the player a turn's worth of attacks exactly when the squad is closing.

### 2. The Reapers (a strong squad)

| | |
|---|---|
| **Lock** | A Rushdown squad of five: a captain with a mace, two chainswords, a springspear and a carbine, each hitting for 9 to 11. They cross the floor in two turns and every one of them attacks on arrival. In the run where I held a line at the heaps, they downed two units in their first turn and left a third on 11 HP. |
| **Tell** | The enemy-range view on round 1 covers the whole west third of the floor. The pre-mission screen shows five units in one squad with a three-tile leash. |
| **Key (board)** | Burn the heap in front of you on round 1 and fall back out of their reach. Thick smoke stands on the heap and medium smoke spills into the lane beside it. A captain who stops in smoke has a one-tile leash, so the squad packs in around him, two tiles short of where it would otherwise stand, and nobody reaches you. They end their turn bunched, one of them standing in the fire. The first strike is now yours. |
| **Key (verbs)** | Hit them from range 2 where only the carbine could answer. Each kill splits the squad further (the queue shows the Split chip on the row). Wren's Smokescreen does the same job as the fire without burning a heap, but she needs ash within a tile: a heap, scorched ground, or smoke already lying there. |
| **Window** | The heap burns for three rounds and its smoke lasts a round or two past that. After round 4 the squad stands on clear ground again and regroups. |
| **Cost of brute force** | Standing at the line: two units down on round 2, and the mission is effectively lost on the clock even if the fight is won. The AI-driven baseline lost all five. |

### 3. The Thresher (a strong solo)

| | |
|---|---|
| **Lock** | 42 HP, DEF 3, a mace for 11, and too heavy for any shove. He starts on the extraction zone and walks west at 2 tiles a turn, so he meets you in the middle of the floor just as the squad fight ends, between your wounded and the road. |
| **Tell** | His MOV of 2 is on his card. The enemy-range view shows a three-tile bubble that barely moves. |
| **Key (board)** | Do not fight him. He cannot catch a unit that moves 4. Go round, through the north or south rows. |
| **Key (verbs)** | A Freeze leaves him Chilled, which takes one off his DEX and drops his MOV to 1 for two turns. In my run that is what let a 1 HP Isaac walk past him: Sophia stood in the one tile he could have stepped to. |
| **Window** | He matters from about round 6, when he reaches the middle, until your last unit is past him. |
| **Cost of brute force** | Two Carbines at 8 a shot need five turns to kill him and the clock does not have five turns. |

## How it was built and checked

- Written by `ScenarioManager.save_scenario` (authored) from a scratch script. A second
  load-and-save writes the same bytes.
- Check board: no BLOCKS and no DEGRADES.
- The twelve suite files that read every mission were run one file at a time with this board on
  disk, and all pass (114 cases).
- **Not checked:** the board has never been opened in the windowed game. The Dust weather, the
  Sunset look and the wind were chosen by name and never seen.

## Runs

| Run | Build | What I did | Result |
|---|---|---|---|
| 1 | Reapers as Sentries on the floor | walked up | abandoned: a Sentry squad on an open floor is bypassed along the edge, and anything it cannot reach it ignores |
| 2 | Reapers Rushdown, starting either side of two stone posts | waited | abandoned: **the squad never moved.** Three turns of standing still. See the bug log, B2 |
| 3 | posts removed, heaps behind the squad's arrival point | held a line | abandoned: they arrived before any heap mattered and there was no ash where the fight was |
| 4 | **this layout,** 11 rounds | held a line at the heaps, lit one on round 2 | lost in effect on round 2: Wren and Sara downed, Isaac on 11 |
| 5 | this layout, 11 rounds | lit the heap on round 1, fell back, struck on round 3 | **Victory on round 11 of 11.** All five extracted: Isaac on 1 HP, Wren on 1, Sophia on 2, three arms lost |
| blunt | this board (12 rounds), player side on the AI | | **Defeat** by round 5. Two Gleaners and one Reaper killed |

The clock went from 11 to 12 after run 5. I won with nothing to spare and I knew the board.

## What I am unsure of

- **Wren's Smokescreen was never cast in the winning run.** Fire made all the smoke I needed, and
  by the time the squad was close enough to target it was already packed. She fought with her
  Carbine. The guest is here so the carving can be tried in a real mission; the map does not need it.
- **The smoke packs the squad; it does not split it.** I designed for a split. What the AI actually
  does with a short leash is fit the formation inside it, which costs the squad its reach for a
  turn. That is still the difference between losing two units and losing none, but it is a
  different lesson from the one in the encounter notes.
- **One Reaper ended its move on a burning tile** and died of it two rounds later. The Medium band
  is meant to avoid that when a safe tile offers the same. With the leash at one tile there may
  have been no safe tile; I did not check.
- **The run is long for its size.** Rounds 6 to 11 were walking. A shorter floor or a nearer road
  would cut the dead time.
- **Losing an arm cost Isaac his Fire Rune** ("Needs aura in Fire") and Wren her ability to carry
  a body. Both are rules working, and both arrived as surprises mid-fight.

## Waiting on alchemy that is not built

- **A fence or wall the fire opens.** The first sketch had fenced fields that the player could burn
  a way through. A burnt fence is still a fence. See the wish list.
- **Wind that moves smoke.** The board authors a strong east wind and it is a look only. If wind
  drifted gas a tile a round, the west heaps' smoke would roll over the squad as it came, and the
  east heaps' smoke would roll onto the road. The heap positions would not need to change.
