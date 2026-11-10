# The Marshal's Charge

**CLAUDE-AUTHORED, unreviewed.** Board: `Scenarios/missions/TheMarshalsCharge.tres`. Built
2026-11-10 on `main` at v0.340.1. Small (18 x 12), Rout, lost if the Marshal dies, no clock,
Sunset look, Basics roster with a cap of 4. Six enemies in three groups, and one allied unit run
by the AI.

## The idea

The protected unit is not yours to move. The Marshal is an AI-run ally, Rushdown, fast and
unarmoured, and he walks straight at the enemy from round 1. Between him and the enemy line is a
meadow of tall grass, and behind the line is a fire caster.

The board has no clock because he is the clock. Left alone he fights both Outriders, reaches the
pikes on round 4, and is burned and stabbed to death on round 5. Helped past the Outriders he gets there a round sooner. The player has four turns to make that not
happen, and cannot make it not happen by telling him to stop.

## The map

```
     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7
 1   a a a a a a a a a a a a a a a a O a     O  Outrider (two, Rushdown, Easy)
 3   a a a a a a , , , , , , a a a a a a     ,  tall grass (the meadow, six by six)
 4   a D D a a a , , , , , , a a a a a a     D  deployment (The Line)
 5   a D D a a a , , , , , , P a a a a a     P  the Pike Line (three, Hold)
 6   a D D M a a , , , , , , P a K a a a     M  the Marshal   K  Kindler (Sentry, two tiles back)
 7   a D D a a a , , , , , , P a a a a a
 8   a a a a a a , , , , , , a a a a a a
10   a a a a a a a a a a a a a a a a O a
```

Everything outside the meadow is sand. A fire lit in the meadow stays in the meadow.

## The encounters

### 1. The Outriders (filler, and a test of the plan)

Two Easy solos who come round the meadow on round 2, one north and one south: exactly the two
roads a flanker would take. An Overwatch lane down each road took 11 and 12 off them as they
arrived. The Marshal finished one himself on his way past.

### 2. The Pike Line (a holding squad)

Three Springspears that never move, standing shoulder to shoulder on the meadow's east edge. They
Guard each other, so a Freeze aimed at one lands on another. A Spring reaches two tiles. From three
tiles a Freeze hits them and nothing comes back. They are not the danger; they are what holds the
Marshal still in the grass.

### 3. The Kindler (a hazard, and the Marshal walks into it)

| | |
|---|---|
| **Lock** | A fire caster posted two tiles behind the pikes. When the Marshal engages, the Kindler steps up and Fireballs him: 8, and the tall grass under him is alight. A pike hits him for 8 the same turn. He has 28 HP and no armour. |
| **Tell** | A fire caster behind a line, a meadow of tall grass in front of it, and an ally with a sword icon and "must survive" who started walking before you did. |
| **Key (board)** | The meadow is six wide and the sand round it is not. A carbine that goes round reaches the Kindler's flank on round 4, standing on sand where his answer lights nothing. Two shots from two sides downed him the turn after his first cast. |
| **Key (verbs)** | A Heal keeps the Marshal above the second hit (he ended on 10). A Freeze from three tiles softens the line he is about to fight. Guard, Gust and a fire lit early in the meadow to turn him aside are all in the kit; I did not need them and did not try them. |
| **Window** | Rounds 1 to 4. The first Fireball lands at the end of round 4. |
| **Cost of brute force** | Following him through the grass: your whole party is standing in the fire with him. |

## How it was built and checked

- Written by `ScenarioManager.save_scenario` (authored) from a scratch script. A second
  load-and-save writes the same bytes.
- Check board: no BLOCKS and no DEGRADES.
- The twelve suite files that read every mission were run one file at a time with this board on
  disk, and all twelve pass (114 cases).
- **Not checked:** the board has never been opened in the windowed game. I do not know how an
  allied unit with `must_survive` is marked on screen, or whether the lose condition's text
  ("Someone you were charged to protect has fallen") names him.

## Runs

| Run | Build | What I did | Result |
|---|---|---|---|
| 1 | first draft: the Marshal built on Torv, in mail | watched him move two tiles a round | abandoned. He had inherited Torv's prosthetic limbs. Rebuilt on a sound body |
| 2 | second draft: Marshal 32 HP in mail, Kindler beside the pikes, Company roster | a Freeze through the pike line hit the Kindler twice, because he was Guarding the pike. He was down on round 4 without casting. The Marshal was never touched | abandoned as no threat at all. The Marshal lost his mail and gained a point of speed; the Kindler moved two tiles back and became a Sentry |
| 3 | third draft | did nothing for five rounds, to see | **Defeat on round 5.** The Marshal killed both Outriders alone, hit a pike, took a Fireball and a Stab |
| 4 | third draft, Company roster | the stash's scoped Gun could target the Kindler from the deployment zone on round 1 | not played. The roster became Basics, which has no Gun |
| 5 | **this board** | two carbines round the meadow with Overwatch, Isaac and Aldin behind the Marshal | **Victory, round 5.** The Marshal on 10 of 28. Nobody down; Noemie on 6 |
| blunt | this board, every side on the AI | | **Defeat on round 4,** the Marshal dead |

## What I am unsure of

- **One winning run, five rounds long.** It is the shortest board in the set and the only one I
  won at the first serious attempt on its final build. The plan I chose happened to be the plan
  the board rewards.
- **An escort you cannot steer may simply be annoying.** I enjoyed it because I knew his clock
  before I started. A player who loses him on round 4 the first time has learned the clock by
  failing, and the mission is over in four rounds either way.
- **The Marshal fights well.** He killed two Outriders, downed two pikes, and stepped off the
  burning tile by himself at the end of round 5. If he were worse the board would be harder and
  feel more like babysitting; if he were better it would not need the player.
- **Both Overwatch lanes fired at a body.** The Marshal's Blowback shoved a pike into the tile the
  lanes were watching, and both carbines spent their watch on it, one of them after it was already
  down. The Kindler then walked in unshot. That is in the bug log.
- **The Outriders arrive on the flankers' roads by coincidence of where I put them.** It worked.
  I did not design it to.
- **I never used the fire.** Lighting the meadow early, to make the Marshal go round, is the idea I
  built the grass for. Run 5 did not need it.

## Waiting on alchemy that is not built

- **Raised earth.** A wall in front of the Marshal turns him without hurting him. The tiles are
  the meadow's west edge, (6,5) to (6,7).
- **A carving that dries or douses.** One Splash on the tile he is standing on puts the fire out
  and scalds him with the steam. Something that puts out a fire without the steam would be the
  honest rescue.
- **An order for an ally.** One word a turn: wait, come back, go round.
