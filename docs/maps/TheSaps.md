# The Saps

**CLAUDE-AUTHORED, unreviewed.** Board: `Scenarios/missions/TheSaps.tres`. Built 2026-11-10 on
`main` at v0.340.1. Small (14 x 14, about 90 walkable tiles), Capture then Extract in 14 rounds,
Company roster with a cap of 4. Eight enemies in three groups.

## The idea

This is the board built for the earth wall that does not exist yet. It is a set of trenches cut
through rock: every fight happens in a corridor one or two tiles wide, and the question each time
is how many of them can reach how many of you. A wall raised across a trench would answer that
question anywhere. Today the rock answers it in the places I drew, and the player's job is to
make the fight happen in one of those places.

It is also a raid. The magazine is at the far end. Take it, then get all four back to the gate
with a relief squad of five on the way in behind you.

## The map

```
     0 1 2 3 4 5 6 7 8 9 0 1 2 3
 0   # # # # # # # # # # # # # #
 1   # K s s s s s s # # # # # #     K  Magazine Keeper, on the capture tile
 2   # s s s s s s s s s s s s #     rows 1 to 3: the hall, and the passage east
 3   # s s s s s s s s s s s s #
 4   # . # # # s s # # # # s s #     .  the west trench (grass, one wide)
 5   # . # # # s s # # # # s s #     columns 5 and 6: the centre trench (two wide)
 6   # . # s S s s s # # # s s #     rows 6 and 7: the bay.  S  Sapper
 7   # . # s s s s S # # # s s #     columns 11 and 12: the east passage
 8   # . # # # s s # # # # s s #
 9   # . # # # s s # # # # s s #
10   # . . . . s s # # # R R R #     R  The Relief (five)
11   # # E E E E E E # # s R R #     E  The Way Out (deployment is its south row)
12   # # E E E E E E # # s s s #
13   # # # # # # # # # # # # # #
```

- **Three ways north.** The west trench is one tile wide, nine tiles straight, and ends at the
  Keeper. The centre trench is two wide and opens into the bay halfway up. The east passage is
  the Relief's road: north, west along the hall, and down the centre trench at you.
- **Every wall is rock,** so a Rock Throw has a source on every tile of the board.
- **The west trench is grass.** It is the only fuel on the board.

## The encounters

### 1. The Keeper (a strong solo at the end of a lane)

| | |
|---|---|
| **Lock** | He stands on the capture tile, so the magazine cannot be taken while he lives. He watches the west trench: four tiles of it are his Overwatch lane, and it is one tile wide. |
| **Tell** | His lane is drawn down the trench from round 1. |
| **Key (board)** | The trench is nine tiles of straight line. The Company stash holds the scoped Gun: 13 a shot at up to ten tiles. Three shots from the trench's foot, with no answer. |
| **Key (verbs)** | Go the other way: through the hall, where his lane does not point. Or send armour up the trench to take the shot. |
| **Window** | Rounds 2 to 4, while the Relief is still walking. |
| **Cost of brute force** | Walking a soft unit up the lane: 11 a round for two rounds. |

### 2. The Sappers (filler that sets the pocket)

Two Easy Sentries in the bay. They are there to be killed on round 2 and 3, and their bodies then
lie in the bay's mouth, where they shape who can stand where.

### 3. The Relief (a strong squad, and the board is the key)

| | |
|---|---|
| **Lock** | Captain, Bulwark in Riveted Mail, two Cutters, a Marksman. About fifty damage a round if all five reach you. They arrive at the top of the centre trench on round 4. |
| **Tell** | They are the only group that moves on round 1, and their road is the long way round. Count the tiles: four rounds. |
| **Key (board)** | The centre trench is two wide and they came down it in single file. The bay below it is a pocket: units either side of the trench mouth and one behind a body. Only the first of them could reach anyone. A Spring up the file hit two at once, twice. The Captain was down on round 5 before his squad had formed up, and the squad split. |
| **Key (verbs)** | Freeze up the file: three in a line. Rock Throw over a friend's shoulder from two tiles back. |
| **Window** | Rounds 4 to 6, at the trench mouth. |
| **Cost of brute force** | Meeting them in the hall, which is seven wide. I did not try it; the AI-driven baseline did, and all four died. |

The Bulwark is the sting in the tail. He came last, in mail, after the pocket had spent itself:
5 to 7 a hit to him, 10 a hit from him. He downed two units and took the third to 2 HP before he
fell on round 10.

## How it was built and checked

- Written by `ScenarioManager.save_scenario` (authored) from a scratch script. A second
  load-and-save writes the same bytes.
- Check board: no BLOCKS and no DEGRADES.
- The twelve suite files that read every mission were run one file at a time with this board on
  disk, and all twelve pass (114 cases).
- **Not checked:** the board has never been opened in the windowed game. A board that is mostly
  rock columns may be hard to read in 3D: a tall column hides the cell behind it.

## Runs

| Run | What I did | Result |
|---|---|---|
| 1 | Bram (in the stash's mail), Aster with the Gun, Isaac, Celest. Aster shot the Keeper from the foot of the west trench on rounds 2 to 4, walked up and captured on round 6. The other three held the bay. Two rescues on rounds 8 to 10. The slowest unit reached the Way Out on round 13 | **Victory, round 13 of 14.** All four out: Aster on 10 HP, Isaac on 2, Bram and Celest on 1. Celest lost both arms and a leg and moved two tiles a round |
| blunt | default four, player side on the AI | **Defeat on round 9,** all four dead |

This is the first layout and the only run. Nothing was retuned.

## What I am unsure of

- **One run.** Every other board in this set took two to five. I may have found the intended line
  on the first try, or the board may have only one line.
- **The Gun does the Keeper's whole encounter.** He never fired. A player without it has to walk
  the lane or go through the hall, and I tried neither.
- **The west trench's grass was never lit.** Isaac carried a Fire Rune for it. The plan was to
  burn the trench behind the runner. Nobody chased her.
- **The Relief came down one column of a two-wide trench.** That is why the pocket worked so
  well. I do not know whether they would use both columns if the bodies lay differently.
- **The retreat was not a fighting retreat.** By the time anyone walked south every enemy was
  down. The clock mattered only because a unit with one leg moves two tiles a round. A second
  squad arriving late would make the Way Out a race. I left it out to see the first shape plainly.
- **A downed unit must be carried out.** Two rescues cost two actions at the worst moment, and a
  rescued unit on 1 HP was downed again the same round. That is the board's real pressure and it
  comes from the rules, not from anything I placed.

## Waiting on alchemy that is not built

This is the board for **raised earth**. The tiles where a wall would act:

- **(5,4) and (6,4), the top of the centre trench.** Raised behind the first two of the Relief,
  it cuts the squad in two: the pocket in the bay gets two enemies, not five, and the Captain is
  on the wrong side of his own men.
- **(1,4), the top of the west trench.** Raised behind the runner, it closes the lane for the
  walk home.
- **(8,2) and (8,3), the hall's east door.** Raised on round 2, it sends the Relief back round
  the long way and buys three rounds.
- **(5,8) and (6,8), below the bay.** Raised on the way out, it is the door shut behind you.

Each of those is a place where today the player has to be standing, or has to have killed
something, to get the same effect. A wall would let a unit that is not there do it.
