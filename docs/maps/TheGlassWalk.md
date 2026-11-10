# The Glass Walk

**CLAUDE-AUTHORED, unreviewed.** Board: `Scenarios/missions/TheGlassWalk.tres`. Built 2026-11-10 on
`main` at v0.340.1. Tiny (13 x 7, 55 open tiles), Rout with a 10-round clock, no weather, Night
look, a fixed cast of three and no roster. Five enemies in four groups.

## The idea

A sand-floored hall with one lightning vein at the door. Dorian carries the Electric Rune and no
Yellow Diamond, so his Zap only works within a tile of a source, and the vein is the only one. But a
shock fuses sand into thunderstone, and thunderstone is a source. So he can pave his own way: every
Zap spent on empty sand is a stepping stone for the next one. Two armoured giants wade a pool toward
him while he decides which to spend his turns on. It is the first board that paints a vein and the
first that uses thunderstone.

## The map

```
     0 1 2 3 4 5 6 7 8 9 0 1 2
 0   # # # # # # # # # # # # #
 1   # a a a a r w w a a a a #     a  sand            w  shallow water
 2   # a T a a a w w a B a a #     V  lightning vein (on sand)
 3   # V D a a a w w a a a E #     E  Glazier's Eye, on a stone dais one level up
 4   # a S a a a w w a B a a #     B  Glass Bulwark   r  Sand Rat
 5   # a a a a r w w a a a a #     D Dorian   T Torv   S Sara
 6   # # # # # # # # # # # # #
```

- **The pool** is two tiles wide and runs wall to wall. Nobody crosses the room without wading it,
  and a unit with MOV 2 spends two turns in it.
- **The dais** at (11,3) is one stone tile, one level up, at the far end.
- There is nothing else. No fuel, no cover, no second source.

## The encounters

### 1. Sand Rats (filler)

Two Easy thugs, 12 HP, who reach Torv and Sara on round 1 and hit for 7. One swing or one shot each.

### 2. The Bulwarks (a hazard squad that walks into its hazard)

| | |
|---|---|
| **Lock** | Two units in Riveted Mail with CON 12: DEF 10, 26 HP, a mace for 10. A Carbine does 2 to them. They advance two tiles a turn and reach your corner on round 4. |
| **Tell** | The queue previews 2 damage for anything physical. Dorian's Zap row is greyed anywhere but beside the vein: "needs a source of lightning within 1 tile". The sand's tile card lists the reaction: a shock fuses it. |
| **Key (board)** | They must wade, and a wader is Wet and standing in a conductor. One Zap into any pool tile within reach hits both for 15. Two such Zaps kill both. The pool is four tiles from the vein, so first you fuse a stone at (4,3), which costs round 1. |
| **Key (verbs)** | Dry, the same Zap does 10 to one of them. Three each, six in all, and they arrive first. Torv can hold one in place while Dorian works on the other. |
| **Window** | Rounds 3 and 4, the two turns they stand in the water. |
| **Cost of brute force** | The AI-driven baseline never fused a stone. Both Bulwarks reached the corner and downed all three. |

### 3. The Glazier's Eye (a strong solo, and the twist)

| | |
|---|---|
| **Lock** | A Hold marksman on the dais: 12 a shot at range 2, an Overwatch lane down the middle row, and a counter for anything that shoots him from range 2. Your three are on 12 or 13 HP by now. And to reach him you waded: all three of you are Wet, so the pool you used on the Bulwarks will now carry your own Zap into your own people. |
| **Tell** | His watch lane is drawn on the floor. The Wet tag is on all three of your units. A Zap aimed at the water previews your own names. |
| **Key (board)** | Two more stones, at (8,3) and (10,2), carry the source across the pool and round the lane, so Dorian can stand at range 2 of the dais on dry sand. |
| **Key (verbs)** | Kill him inside one turn: a felled unit does not counter. Sara's shot and then Dorian's Zap is exactly enough. Or heal first: Dorian also carries a Heal for 11. |
| **Window** | The clock. I reached him on round 8 of 10. |
| **Cost of brute force** | A lone shooter trades a 12 for a 12 and loses, because he shoots first on his own turn. |

## How it was built and checked

- Written by `ScenarioManager.save_scenario` (authored) from a scratch script. A second
  load-and-save writes the same bytes.
- Check board: no BLOCKS and no DEGRADES.
- The twelve suite files that read every mission were run one file at a time with this board on
  disk, and all twelve pass (114 cases). I read the output before committing this time.
- **Not checked:** the board has never been opened in the windowed game. In particular I have not
  seen the vein, the thunderstone marks, or whether a three-unit fixed cast with no pre-mission
  screen opens cleanly from Mission Select.

## Runs

| Run | What I did | Result |
|---|---|---|
| 1 | fused (4,3) on round 1; Zapped the pool on rounds 3 and 4; fused (5,3), (8,3) and (10,2) on rounds 5 to 7; Sara then Dorian on the Eye | **Victory, round 8 of 10,** no deaths. Torv and Sara on 13 HP, Dorian untouched |
| blunt | player side on the AI | **Defeat.** It killed both Rats and nothing else |

This board was right on the first layout. That is the only one so far.

## What I am unsure of

- **It may be a one-solution puzzle.** The Bulwarks can only be hurt by the Zap, and the Zap can
  only be carried by stones. A player who does not read the sand's card has no second way. The
  encounter notes ask for two keys; the second one here (Torv holding a Bulwark while Dorian works
  dry) is thin.
- **Dorian again.** Everything is tuned to his Aether 5. The board gives the player no choice of
  caster, so at least it cannot be played with the wrong one.
- **The Eye did not counter Sara.** Her shot took his right arm, and he did not answer. If that was
  the arm and not luck, the last fight is easier than its card says.
- **The twist is quiet.** Nothing forced me to Zap the pool with my own people in it, so the danger
  the Eye's card describes never fired. A second pool between the stones and the dais would force it.
- **Ten rounds is generous if you know the line and tight if you do not.**

## Waiting on alchemy that is not built

- **Thunderstone that conducts.** A fused tile is a source and nothing else. If a line of
  thunderstone carried the current the way water does, the stones would be a fuse laid across the
  floor as well as a road, and the last fight could be a Zap run down the line from the door. The
  stones are placed where that line would run: (4,3), (5,3), (8,3).
- **A storm.** With lightning strikes that fuse the sand they hit, the room would grow its own
  stones on the telegraphed tiles and the player would plan a route through them.
