# Stormgate

**CLAUDE-AUTHORED, unreviewed.** Board: `Scenarios/missions/Stormgate.tres`. Built 2026-11-10 on
`main` at v0.340.1. Medium (20 x 16), Rout, lost if an enemy enters the gate, Thunderstorm, Storm
look, Warband roster with a cap of 5. Nine enemies in four groups, and three allied militia run by
the AI.

## The idea

It rains on everybody. Every unit on the board ends every turn Wet, so every shock runs through
every body that touches another, friend or foe. The enemy brings two casters whose Zap Cannon does
15 down a five-tile line. The player brings Dorian, whose Zap does the same thing on a smaller
scale. The board asks one question all mission: who is standing next to whom?

It is also the first board with an AI-run allied squad. Three militia hold the ground in front of
the gate. They fight well, they stand shoulder to shoulder, and a shock aimed at the enemy beside
them goes through them too.

## The map

```
     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9
 0   a a a a a a a a a a a a a a a a a a f g     f g  Storm Callers
 1   a a a a a a a a a b A c a a a a a a a a     A    Drowned Captain    b c  Bulwarks
 2   a a a a a a a a a d a e a a a a a a a a     d e  Cutters
 3   a a h a a a a a a a a a a a a a a i a a     h i  Marsh Rats
 4   ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~     ~    mud (two to cross)
 5   ~ w w ~ ~ w w ~ ~ ~ ~ ~ ~ ~ w w ~ ~ w ~     w    shallow water
 6   ~ w w ~ ~ w w ~ ~ ~ ~ ~ ~ ~ w w ~ ~ w ~
 7   ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
 8   a a a a a a a a a a a a a a a a a a a a     a    sand
 9   a a a a a a a w w a a a w w a a a a a a
10   a a a a a a a w w a V a w w a a a a a a     V    lightning vein
11   a a a a a a a a M M a M a a a a a a a a     M    Gate Militia (allied, AI)
12   # # # # # # # # # G G # # # # # # # # #     G    The Gate (two tiles)   #  rock
13   s s s s s s s s s s s s s s s s s s s s     s    stone floor (the yard)
14   s s s s s s D D D D D D D D s s s s s s     D    deployment
15   s s s s s s s s s s s s s s s s s s s s
```

- **The gate is two tiles in a rock wall.** An enemy that ends a move on either tile ends the
  mission. A downed body does not block the tile in front of it: units walk through.
- **The marsh** is four rows of mud and pools. It costs the wave a round and it costs the Storm
  Callers two, which is the time the player has.
- **Two puddles** sit either side of the approach. Anything standing in one is touching everything
  else in it.

## The encounters

### 1. The Drowned Company (a strong squad the rain links together)

| | |
|---|---|
| **Lock** | A Rushdown squad of five: a Captain (26 HP), two Bulwarks in Insulated Weave, two Cutters with revved chainswords. They cross the marsh in three rounds and hit the militia on round 3. |
| **Tell** | They march as a block of five, touching. Every one of them reads Wet from the end of round 1. |
| **Key (board)** | The militia. They hold for three rounds and take two or three of the squad with them. The gate behind them is two tiles wide, and the wave can only come at it down two files. |
| **Key (verbs)** | Freeze on a Wet body is Deep Chill: 14 a head down a three-tile line. From the gate, the files the wave must use are exactly Freeze lines. Isaac hit three units with one cast twice. A Chilled unit is no longer Wet, so it also stops conducting. |
| **Window** | Rounds 4 to 6, while they are packed in front of the gate. |
| **Cost of brute force** | Standing in the gate mouth shoulder to shoulder. One Zap Cannon then hits everyone. |

### 2. The Storm Callers (two strong solos who bring the hazard)

| | |
|---|---|
| **Lock** | Zap Cannon: 15 to a Wet target, five tiles down a line, and then through everything touching it. They have 12 HP each and stay at range. One of them took 15 off a unit in each of four rounds in my winning run. |
| **Tell** | They hang back from the wave on the east side and enter the marsh a round behind it. Their first shot comes on round 3 and it hits their own Captain and a Bulwark as well as its target: 25 damage to their own side in one cast. |
| **Key (board)** | The marsh. They move two tiles a round in it, and a unit that is not on their row or column cannot be hit. They are fragile: 12 damage downs one. |
| **Key (verbs)** | Sara's shot does exactly 12. A unit standing next to nobody takes one hit and not three. A downed Caller does not answer, though the other one may. |
| **Window** | Rounds 4 to 6, while they are still in the mud. |
| **Cost of brute force** | Ignoring them. In the AI-driven baseline one Caller killed five units, three of them the player's. |

### 3. The Gate Militia (the ally, and the twist)

| | |
|---|---|
| **Lock** | Not a lock: a temptation. Three allied units stand in the middle of the best Zap target on the board. |
| **Tell** | Aim Dorian's Zap at a Bulwark and the queue lists the militia among the victims, and sometimes Dorian. |
| **Key** | Do not cast it. I never found a safe Zap at the gate in four runs. The Zap belongs on the Storm Callers, who walk side by side and both die to one cast, if Dorian can get there. |
| **Cost** | The militia's own Springspear goes through a player unit standing in its line. It took 10 off Isaac. |

### 4. The Marsh Rats (filler, and the late pressure)

Two Easy solos who arrive a round after the wave, when the gate's defenders are already hurt. One
of them downed Isaac on round 7.

## How it was built and checked

- Written by `ScenarioManager.save_scenario` (authored) from a scratch script. A second
  load-and-save writes the same bytes.
- Check board: no BLOCKS and no DEGRADES.
- The twelve suite files that read every mission were run one file at a time with this board on
  disk, and all twelve pass (114 cases).
- **Not checked:** the board has never been opened in the windowed game. I have not seen the Storm
  look, the rain or a Zap Cannon's arc.

## Runs

| Run | Build | What I did | Result |
|---|---|---|---|
| 1 | a causeway through the marsh, Callers at 16 HP | cast an un-previewed Freeze beside a Caller | defeat: the counter was a Zap Cannon that chained through three of mine. The causeway became open marsh and the Callers dropped to 12 HP |
| 2 | this board | stood four units together at the gate | defeat: one volley hit all of them |
| 3 | this board | two hunters killed both Callers in the marsh on round 4; Freeze broke the wave | **defeat on round 6 with every enemy downed.** I moved a unit off a gate tile and the last Cutter walked through a downed body onto it |
| 4 | **this board** | the same plan. The wave came a round sooner and both hunters were hit for 15 before they could strike. Isaac froze the files from the gate, Sara downed one Caller on round 5 and the other on round 9 | **Victory, round 9.** No player deaths. Sara and Bram on 5 HP, Isaac on 1 after a rescue, one militia alive |
| blunt | this board, player side on the AI | | **Victory, round 9, with one survivor of five.** Three player units and two militia died, and the mission ended when the last Storm Caller caught himself in his own chain |

## What I am unsure of

- **It is the swingiest board of the eight.** I lost it three times, twice through my own mistakes
  and once to a rule I did not know (a body does not block a tile). Runs 3 and 4 used the same plan
  and the wave arrived a round apart, because where my units stood changed where the Callers
  walked. A Zap Cannon that does 15 at five tiles has no counter-play once the Caller has chosen
  his row; the only answer is to kill him first.
- **The blunt baseline wins.** It costs three of five units, and it only ends because a Caller
  electrocutes himself. That is the rain doing what the board says it does, and it is also a
  mission the AI can clear by accident.
- **Dorian did nothing.** The board was built around his Zap and I never cast it. Every target at
  the gate had militia or my own units in the chain. He was a body for the second gate tile.
- **The lightning vein was never used.** It sits at (10,10), in front of the gate, where a caster
  would have to stand in the wave to draw on it.
- **Instant defeat on the gate tile is harsh.** Run 3 was lost with nine enemies downed and none
  standing but one. The rule is the mission's and it is stated; it still felt like losing to a
  technicality.
- **Enemy friendly fire carries the mission.** The Callers did about 60 damage to their own side
  across run 4. Without that the gate would not hold.

## Waiting on alchemy that is not built

- **Raised earth.** A wall across the gate mouth for a round would buy the turn the hunters need.
  The tiles are (9,11) and (10,11).
- **A ground that breaks a chain.** Rubber, dry sand under a roof, a raised duckboard: one tile
  where a body is not a conductor. The two tiles either side of the vein, (9,10) and (11,10), are
  where the militia would stand on it.
- **A carving that dries a body.** Chilled already does it as a side effect. A cast that takes Wet
  off three of your own units is the missing direct answer to this weather.
