# Meltwater

**CLAUDE-AUTHORED, unreviewed.** Board: `Scenarios/missions/Meltwater.tres`. Built 2026-11-10 on
`main` at v0.340.1. Medium (22 x 16), Capture, no clock, Light Snow (heat down one step), Overcast
look, Warband roster with a cap of 5. Eight enemies in five groups.

## The idea

A shrine on an island in a deep lake. The only dry road to it is a frozen causeway, and four armoured
guards stand on the ice. Fire on ice melts it, and whoever stands on melted ice over deep water goes
under. So the ice is the guards' post and their grave, it is your road and theirs, and whoever holds
the fire decides which. A shallow ford on the far side is the slow, safe way round. A marksman who
walks on water patrols the lake.

## The map

```
     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 0   a a a a a a a a a a a a a a a a a a a a a a
 1   a a a T a a a a a a a a a a a a a a T a a a     a  sand (snow bank)   s  stone
 2   a a W W W W W W W W W W W W W W W W a a a a     W  deep water         w  shallow water
 3   a W W W W W W W W W W W W W W W W W a a a a     _  ice over deep water
 4   a W W W W W W W a L C C a a W W W W a a a a     L  lantern (a source of fire)
 5   a W W W W W W W a s C C s a w w w w a a a a     C  the shrine (capture zone)
 6   a W W W W W W W a L K a a a W W W W a a a a     K  Shrine Kindler
 7   a W W W W W W W W W m _ W W W W W W a a a a     S  Ice Sergeant   F  Ice Fisher
 8   a W W W W W W W W F _ S _ W W W W W a a a a     m  Ice Fisher with a Carbine
 9   a W W W W W W W W _ _ _ F W W W W W a a a a     P  Pike (walks on water)
10   a W W W W W W P W W _ _ W W W W W W a a a a     h  Shore Hand
11   a a s s s s s s L s s s s s s s s s s s a a
12   a a s h s s s s s s s s s s s s s h s s a a
13   a a a a a a a a D D D D D D a a a a a a a a     D  deployment (South Shore)
14   a a a a a a a a D D D D D D a a a a a a a a
15   a a a a a a a a a a a a a a a a a a a a a a
```

- **The ice** is twelve tiles: a two-wide causeway at columns 10 and 11 from the south shore (row
  10) to the island (row 7), with a four-by-two platform across its middle. All of it is over deep
  water.
- **The ford** is four tiles of shallow water on row 5, from the east bank to the island. It costs
  2 a tile and soaks whoever wades it.
- **Three lanterns:** one on the south shore at (8,11), two on the island. A fire caster beside one
  fires Fireburst, a five-tile plus, in place of Fireball.
- **Nothing on the board burns.** There is no grass.

## The encounters

### 1. Shore Hands (filler)

Two Easy thugs, 14 HP, who arrive at the deployment on round 2.

### 2. Pike (a strong solo who ignores terrain)

| | |
|---|---|
| **Lock** | A Water Walker with a Carbine: MOV 6 across deep water, 14 a shot, and no melee unit can follow him. On round 1 he crosses the lake and shoots whoever stands nearest the shore. In the AI-driven baseline he downed three units by himself. |
| **Tell** | He is standing on open water at the start. His card shows the Water Walker job and MOV 6. |
| **Key (board)** | He stands in the water, and open water carries a shock. A Zap into any water tile within three tiles of him reaches him. |
| **Key (verbs)** | He has to come within two tiles to shoot, which is Carbine counter range: a marksman he shoots at answers him. Overwatch on the shoreline punishes his approach. |
| **Window** | From his first shot. In both my runs he also ended a turn in steam my own fire had boiled off the lake, which soaked him: the Zap then did 15 and the steam finished him. |
| **Cost of brute force** | Without a counter or a shock he takes one unit every turn or two and nothing can reach him. |

### 3. The Ice Fishers (a hazard squad, the hazard present)

| | |
|---|---|
| **Lock** | A Sergeant, two Fishers and a marksman in Riveted Mail, holding the only dry road. DEF 6 against anything physical. The marksman keeps an Overwatch lane down the causeway. |
| **Tell** | They are standing on ice, and the tile card for ice lists the reaction: fire melts it. The queue row for a fire aimed at them says "goes under" and "drowns" before you commit. |
| **Key (board)** | Fire on the tile under one of them. It takes 5 from the hit and then everything else from the water: the unit is downed at 1 HP, sunk. From beside the shore lantern a Fireburst reaches the platform's near edge. Or melt the two tiles where the causeway meets your shore: the squad cannot leave its ice, and it is stranded for the rest of the mission. |
| **Key (verbs)** | A Freeze makes new ice wherever there is water, so the road you melted can be rebuilt where you choose. |
| **Window** | Any time. But see the cost. |
| **Cost of brute force** | Fighting them on the ice puts your own units on tiles the Kindler can melt. And every tile you melt is a tile of your own road gone. |

### 4. The Shrine Kindler (the hazard, brought by the enemy)

| | |
|---|---|
| **Lock** | Fire 3 in an Asbestos Shroud, a Sentry on the island. Anyone who ends a turn on ice within two tiles of where he can stand is melted through and drowned. The AI does this on purpose. He also walks out to haul sunk Fishers back onto the island. |
| **Tell** | The enemy-range view shows his reach over the last two rows of the causeway. If you watch him rescue a Fisher you have seen him leave the island. |
| **Key (board)** | Come by the ford. Shallow water cannot drown you, a soaked unit takes half from fire, and his Fireball has no answer to a unit standing next to him. |
| **Key (verbs)** | When he steps onto the ice to rescue someone, he is standing on ice: his shroud stops the fire and does nothing about the water. Melt it. |
| **Window** | At the ford, from the moment your first unit is beside him. On the ice, the turn after any Fisher sinks. |
| **Cost of brute force** | In my first run two wounded Fishers and the Kindler came back down a bridge Isaac had just frozen, downed him on it, and the Kindler melted the tile under his body. He died. |

## How it was built and checked

- Written by `ScenarioManager.save_scenario` (authored) from a scratch script. A second
  load-and-save writes the same bytes.
- Check board: no BLOCKS and no DEGRADES.
- The twelve suite files that read every mission were run one file at a time with this board on
  disk, and all pass (114 cases).
- **A correction.** The first commit of this board failed one of those suites and I committed it
  anyway by mistake: `law/test_every_mission_can_be_won_on_foot` requires every enemy to be
  reachable on foot, and Pike began on open water with no shore beside him. He now begins at
  (7,10), one tile off the south shore. That suite, the board lint suite, the load-integrity suite
  and the tile round-trip suite were rerun on the fixed board and pass.
- **Not checked:** the board has never been opened in the windowed game. Whether ice over deep
  water and plain ice can be told apart by eye, and whether Light Snow reads, are unknown.

## Runs

| Run | Build | What I did | Result |
|---|---|---|---|
| 1 | first draft: three Fishers bunched on the platform, Pike far west, a six-tile ford | one Fireburst from the shore lantern sank two Fishers on round 1; sank the Sergeant and the Kindler in turn; froze a bridge | **Victory, round 13,** Isaac dead (see the Kindler's card). Every enemy was at 1 HP by round 3: too easy up front, and eight turns of walking the ford at the end |
| 2 | **this board:** four Fishers spread out, one with a Carbine; Pike nearer; a four-tile ford | sank Fishers one at a time and stood at the causeway's foot | abandoned on round 3: the Sergeant came ashore, Celest walked into the Overwatch lane and went down, Isaac died |
| 3 | this board | melted the causeway's shore end on round 1; killed Pike through the water on round 2; walked round; took the Kindler at the ford | **Victory, round 9,** no deaths |
| fix | this board, Pike moved from (6,9) to (7,10) | one enemy turn only | Pike now opens by setting an Overwatch down the shore at column 7 instead of crossing to shoot. **The full runs above were played with him at (6,9).** I did not replay them |
| blunt | this board with Pike at (6,9), player side on the AI (Torv, Marco, Sara, Bram, Isaac) | | **Defeat.** Pike downed three of them. It killed Pike, both Shore Hands and one Fisher |

## What I am unsure of

- **The winning line never fights the squad.** Run 3 strands four guards on a floe on round 1 and
  ignores them. That is a "silly hazard" answer of the kind the encounter notes ask for, and it
  may also be an anticlimax: the board's biggest group ends the mission untouched. The marksman
  still covers half the shrine from the floe, which is all that is left of them.
- **Drowning is close to a kill button.** One Fireball on an iced tile does 5 and then sets the
  target to 1 HP, downed and sunk, whatever its armour. The enemy's rescues keep it from being
  final, and those rescues were the best moments of the runs, but the first cast of the mission
  removing two of four guards is strong.
- **The ford is a steam bath.** The Kindler's fire boils shallow water, and the steam scalded three
  waders for 2 or 3 each a turn. I did not plan that and I like it. It may be too much on top of
  the soak-and-half-damage trade.
- **Light Snow did almost nothing.** It took one point off each fire hit, which never mattered
  because the water does the damage.
- **Bram's Springspear needs loading before a Stab as well as a Spring,** which I learned twice at
  bad moments. Not this board's problem, but it shaped both wins.

## Waiting on alchemy that is not built

- **Ice a unit can stand on being told apart from ice over a ford.** If the ford could be iced too,
  the map would have two frozen roads, one that drowns and one that only wets, and reading which is
  which would be the lesson. Today a frozen shallow tile and a frozen deep tile print the same glyph
  in the Play API; I did not check the game's own look.
- **A raised earth causeway.** The island's west side has no approach at all. A carving that raised
  a walkable ridge out of shallow water would give Earth users their own road. Nothing is marked on
  the board for it; the west shore of the island, (8,4) to (8,6), is where it would land.
