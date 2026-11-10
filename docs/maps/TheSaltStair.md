# The Salt Stair

**CLAUDE-AUTHORED, unreviewed.** Board: `Scenarios/missions/TheSaltStair.tres`. Built 2026-11-10 on
`main` at v0.340.1. Medium and tall (14 x 17, about 75 standable tiles, four heights), Capture, no
clock, clear sky with a Gale (a look), Dawn look, Warband roster with a cap of 4. Seven enemies in
four groups.

## The idea

A stair two tiles wide climbing a ridge with nothing on either side of it. A shove that ends over
the void is a death, not a wound, and on this board almost every shove ends over the void. Two
Galewrights stand on side pinnacles and blow whoever climbs past them off the far edge. Three
Wardens hold the summit with the same drop behind them. Gust is the only carving that matters here
and both sides have it. The whole map is one question asked five times: when this unit is pushed,
where does it land?

## The map

```
     0 1 2 3 4 5 6 7 8 9 0 1 2 3          heights
 0   . . . . . . . . . . . . . .          (blank is void)
 1   . . . . . C K C C . . . . .   3      C  the cairn (capture zone), on the summit
 2   . . . . . s W W s . . . . .   3      K  Warden Captain    W  Stair Warden
 3   . . . . . . ^ ^ . . . . . .   2>3    ^  ramp, rising north
 4   . . . . . . s s . . . . . .   2
 5   . . . s s . s s . . . . . .   2      west pinnacle, columns 3-4
 6   . . # s G . s s . . . . . .   2      G  Galewright     #  rock (the backstop)
 7   . . . s . . ^ ^ . . . . . .   1>2
 8   . . . ^ . . s s . G s # . .   1      east pinnacle, columns 9-10
 9   . . . s . . s s . s s . . .   1
10   . . . s . . s s . . s . . .   1
11   . . . ^ . . ^ ^ . . ^ . . .   0>1
12   . . s s s s s s s s s s . .   0      the foot
13   . . s s h s s s s h s s . .   0      h  Stair Hand
14   . . a a a a a a a a a a . .   0
15   . . a a D D D D D D a a . .   0      D  deployment
16   . . a a D D D D D D a a . .   0
```

- **The spine** is columns 6 and 7. One tile of void separates it from each pinnacle.
- **Each pinnacle** has its own one-wide path from the foot, and one rock. The rock is the point:
  the tile between the Galewright and the rock is the only tile from which a unit beside him cannot
  be pushed anywhere.
- **The summit** is four tiles by two. The back row is the cairn.

## The encounters

### 1. Stair Hands (filler)

Two Easy thugs, 14 HP, who reach the deployment on round 1.

### 2. The Galewrights (strong solos, the hazard brought by the enemy)

| | |
|---|---|
| **Lock** | Each holds Gust: range 3, a two-tile shove, no damage. The east one covers the lower spine and pushes west; the west one covers the upper spine and pushes east. Anything on the spine in their reach lands in the void and dies outright. They also answer every attack with the same shove, so a unit that shoots or stabs one from the wrong tile is killed by the counter. |
| **Tell** | The queue. A Stab at the east Galewright from the tile south of him previews, under REACTION, "DIES, shoved to (9,11), into the void". The same Stab from the tile east of him, with the rock behind it, previews a reaction of 0 and nothing else. The enemy-range view shows their reach over the spine. |
| **Key (board)** | The backstop tile on each pinnacle: (10,8) in the east, (3,6) in the west. A unit that starts its turn four tiles down the path can reach it in one move and strike. Each Galewright has 16 HP and died to two blows. |
| **Key (verbs)** | A felled unit does not counter: two attackers in one squad pass kill him before he answers. Or be too heavy to move: the stash has a Ballast Harness. |
| **Window** | Any time, but before anyone sets foot on the spine section he covers. |
| **Cost of brute force** | The AI-driven baseline climbed the spine. Torv was blown into the void on the way past the west pinnacle. |

### 3. The Wardens (a hazard squad, the hazard present)

| | |
|---|---|
| **Lock** | Two Wardens in Riveted Mail and a heavy Captain (32 HP, a mace for 11) at the head of the last ramp, where only two tiles touch them. The Captain stands behind one Warden. |
| **Tell** | They stand on a platform two tiles deep with void on three sides. |
| **Key (board)** | Gust from the upper spine reaches the front row. The Warden with nobody behind him goes north two tiles and off the back. The other has the Captain behind him and will not move north, so he goes sideways: from the summit's east end, a Gust west puts him off the west edge. Two casts, two kills, no damage dealt or taken. |
| **Key (verbs)** | The Captain is too heavy to shove. He has to be fought or walked round: the objective is the cairn, and a unit that reaches the back row and captures ends the mission with him standing. |
| **Window** | The Wardens do not leave the summit. |
| **Cost of brute force** | Two tiles of frontage against DEF 6 and three counters, on a ramp, with a drop behind you. |

## How it was built and checked

- Written by `ScenarioManager.save_scenario` (authored) from a scratch script. A second
  load-and-save writes the same bytes.
- Check board: no BLOCKS and no DEGRADES.
- The twelve suite files that read every mission were run one file at a time with this board on
  disk, and all twelve pass (114 cases).
- **Not checked:** the board has never been opened in the windowed game. A board that is 70% void
  has never been looked at; I do not know what the camera does with it or how the drop reads.

## Runs

| Run | Build | What I did | Result |
|---|---|---|---|
| 1 | first draft: Company roster, no backstop rocks | gave Aster the stash's scoped Gun and shot both Galewrights and the Captain from the foot and the lower spine, thirteen damage a shot, range ten, nothing able to answer | **abandoned as a cheap win.** Every hard enemy died to one weapon without a decision being made. The roster became Warband, which has no Gun |
| 2 | **this board** | Bram took the east Galewright from the backstop tile (rounds 4 to 5), Torv the west one (rounds 6 to 7); Isaac Gusted one Warden off the back (round 9) and the other off the side (round 10), took an 11 from the Captain, and captured on round 11 | **Victory, round 11,** no deaths. Isaac on 9 HP with an arm gone |
| blunt | this board, player side on the AI (Torv, Marco, Sara, Bram) | | **Defeat.** It killed both Hands and the east Galewright, then lost Torv to the void and the rest to the Wardens |

## What I am unsure of

- **It kills outright.** Everywhere else in the game a unit goes down and can be rescued. Here a
  shove into the void is "DIES". The preview says so every time, and I think that is fair, but a
  player who commits without reading the REACTION row loses a character for the campaign.
- **The Captain can be ignored.** Capturing ends the mission. I did exactly that. If he is meant to
  be a fight, the objective needs Rout beside Capture, and then he is 32 HP of slog with no trick
  to him. I left it, because walking past the thing you cannot move is its own answer.
- **The backstop tile is one tile.** The safe approach is a single cell per pinnacle, found by
  reading the preview or by noticing a rock. That is a narrow key. The second key (two attackers
  in one pass) I did not test, and the third (the Ballast Harness) can only be worn by a unit with
  DEX 4 or less, which in Warband is Marco, Celest or Aldin.
- **The enemy Gust never fired on its own turn in the winning run,** because I never gave it a
  target. All I saw of it was the counters. The baseline shows it works when it has one.
- **Rock Throw has no job.** The stair is sandstone from top to bottom so that it would. Nothing
  on the board needed it. The name is all that is left of that idea.

## Waiting on alchemy that is not built

- **Raised earth.** This is the board the dev's example fits best: a wall raised behind your own
  unit is a backstop you carry with you, and a wall raised across the summit cuts the Captain off
  from the Warden he is propping up. Today the two rocks at (2,6) and (11,8) are fixed backstops.
  With the carving, every tile on the stair could be made safe for one turn, and the board would
  be about where to spend it.
- **Wind as a rule.** The board authors a Gale blowing east, as a look. If wind added a tile to a
  shove going with it and took one from a shove going against it, the west Galewright (who pushes
  east) would be deadlier than the east one, and the player's own Gusts would have a good side of
  the stair to cast from.
