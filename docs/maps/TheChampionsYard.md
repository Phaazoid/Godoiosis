# The Champions' Yard

**CLAUDE-AUTHORED, unreviewed.** Board: `Scenarios/missions/TheChampionsYard.tres`. Built
2026-11-10 on `main` at v0.340.1. Tiny (13 x 9, 77 walkable tiles), Rout in 12 rounds, Night look,
a fixed cast of three and no roster. Three enemies, each alone.

## The idea

Three strong solos in one yard, each made strong by a job and each with a different wrong way to
fight him. It is the only board in the set built on enemy abilities and not on the ground: Iron
Will, Crisis and Brace had not been on an enemy in any of the twelve before it.

The fixed cast is Isaac (Freeze and a Fire Rune), Sara and Bram. No kit to pick, no deployment.

## The map

```
     0 1 2 3 4 5 6 7 8 9 0 1 2
 1   # s s s s s s s s s U s #     U  The Unbroken (north post, columns 8 to 11)
 2   # s s s s s s s s s s s #
 3   # S s s s s s s s _ _ _ #     _  ice over deep water (three by three)
 4   # I s s s s s s s _ T _ #     T  The Twice-Born, on the ice
 5   # B s s s s s s s _ _ _ #
 6   # s s s s s s s s s s s #
 7   # s s s s s s s s s W s #     W  The Wall (south post, columns 8 to 11)
```

Each champion is a Sentry with a post of a few tiles. None of them leaves it.

## The encounters

### 1. The Twice-Born (Crisis, and the hazard he stands on)

| | |
|---|---|
| **Lock** | A berserker with a revved chainsword. Put him down and Crisis stands him back up on 5 HP with +5 to Strength, Dexterity and Perception for three turns. |
| **Tell** | He is standing on ice, and Isaac carries a Fire Rune. |
| **Key** | Melt the tile under him. The Fireball did 6, the water did 14, and Crisis fired in the water: he came up on 5 HP, surged, soaked, standing in deep water with no ice in reach of his feet. A Stab from the next ice tile killed him before he acted. |
| **The wrong way** | Putting him down on the ice with weapons, then standing beside a surged berserker. The baseline set Crisis off with a Fireball and had to kill him a second time. |

### 2. The Unbroken (Iron Will)

| | |
|---|---|
| **Lock** | No hit does more than 6 to him. A 12-point shot does 6; a 14-point Spring does 6. He has 22 HP and hits for 10. |
| **Tell** | The first preview: "6 dmg" from a carbine that has done 12 all day. |
| **Key** | Count hits, not damage. Four of anything. The weakest attack in the party is as good as the strongest, so the order is whoever can reach without being answered: a shot from two tiles, a Spring from two tiles, a Fireball from the diagonal. Three in one round finished him. |
| **The wrong way** | Saving the big hit for him. |

### 3. The Wall (Brace)

| | |
|---|---|
| **Lock** | A tank in Riveted Mail who Braces: 6 to 9 off every weapon hit. A 12-point shot did 6, a 14-point Spring 5 and a counter-Stab 3. 26 HP. |
| **Tell** | A counter that does 3. |
| **Key** | Freeze does not ask about armour: 6 or 7 a cast. And he is a Sentry: he walks to the edge of his post to hit whoever is beside it, and then everything two tiles from him is free. A Freeze, a Spring and a shot from two tiles each, two rounds running. |
| **The wrong way** | Trading blows with him. Bram took 10 to give 3. |

## How it was built and checked

- Written by `ScenarioManager.save_scenario` (authored) from a scratch script. A second
  load-and-save writes the same bytes.
- Check board: no BLOCKS and no DEGRADES.
- The twelve suite files that read every mission were run one file at a time with this board on
  disk, and all twelve pass (114 cases).
- **Not checked:** the board has never been opened in the windowed game. Above all I do not know
  what tells a player that an enemy has Iron Will, Crisis or Brace before the first blow. The Play
  API's unit line does not list abilities; the game's info card may.

## Runs

| Run | What I did | Result |
|---|---|---|
| 1 | melted the ice on round 3 and stabbed the Twice-Born as he surfaced; three capped hits on the Unbroken on round 4; baited the Wall to the edge of his post and hit him from two tiles on rounds 7 and 8 | **Victory, round 8 of 12.** Nobody down. Sara and Bram each lost an arm |
| blunt | the same three, on the AI | **Defeat on the clock.** Sara and Bram dead |

First layout, one run, nothing retuned.

## What I am unsure of

- **One run, and I knew what each job did.** The whole board is three "what is this?" moments.
  I cannot tell from here whether they are discoveries or ambushes.
- **Two of the three fall to standing two tiles from a Sentry.** That is the same free poke as the
  bug log's S13, used on purpose. It makes the Wall slow and safe, not hard.
- **Crisis in the water is the best moment on the board and I am not sure it is intended.** A unit
  that cannot swim revived standing in deep water and stayed there. If Crisis is meant to save him
  from drowning, it did; if a unit is not meant to stand in deep water, it should not have.
- **The clock never mattered.** Eight of twelve, with two rounds spent walking between posts.
- **Three duels in a row is not really one map.** They never interact. A second draft would put
  the Unbroken's post where he can reach the ice.

## Waiting on alchemy that is not built

- **Raised earth.** A wall across a post cuts a Sentry off from the edge he sallies to. For the
  Wall it would be (8,6) and (8,7).
- **A burn that ticks.** Iron Will caps a hit at 6. A burning tile does 5 a turn and would not be
  capped; the yard is stone and holds no fire. A carving that sets a body alight, not a tile,
  would be the alchemist's answer to him.
