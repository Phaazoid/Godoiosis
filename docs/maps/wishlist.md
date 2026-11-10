# Wish list: what a map wanted and could not have

**CLAUDE-AUTHORED, unreviewed.** Each entry is something a map design reached for that does not
exist today. They are ideas for future content and rules, not requests, and none is filed as an
issue. Newest at the bottom of each group.

Each entry says which map wanted it, what it would have done there, and what the map does instead.

## Alchemy and transmutations

- **Rain, or a Wet body, slaking quicklime** (The Lime Kiln). Today only a water *hit* slakes. If
  rain did, a drawn weather would turn the yard into a different fight; if a soaked unit stepping
  onto quicklime did, wading the drain would be a way to spring it. The map uses a clear sky and
  one Splash.
- **Brick that does something** (The Lime Kiln). Fire on clay soil sets Brick, and Brick is a
  permanent state with no effect. As +1 DEF footing, or as a tile gas cannot cross, a kiln yard
  could have a floor the player bakes into cover. The map has no clay.
- **A water carving that reaches three tiles** (The Lime Kiln). Splash covers two rows, exactly as
  far as a Zap reaches, so any place you can soak a target from you can also shock it from. That
  made it hard to build a spot where the steam is the *only* safe way to wet someone. A lobbed
  water flask (point aim, range 3, one tile) would open those layouts. The map uses a drain to
  carry the current.

- **Wind that moves gas** (Chaff). The board authors a strong east wind and it only draws. Gas that
  drifted a tile a round downwind would make "which side of the heap do I light" a real choice and
  would let a map put its smoke where the author wants it without placing a caster. The map relies
  on the squad walking into smoke that stays put.
- **A Smokescreen that needs no ash, or a carried pouch of it** (Chaff). On stone, sand or water the
  carving fizzles unless a heap, scorched ground or smoke is within a tile of the caster. On Chaff
  that meant the guest who carries it never cast it: wherever she could cast from, the fire had
  already made the smoke. A vial that counts as a source is on the Deep Alchemy list as unbuilt.
- **Something that splits a moving squad** (Chaff). Smoke in a squad's path packs it (bug log, S5).
  A carving or hazard that actually cuts a marching squad in two would be the tool the encounter
  notes describe: a raised wall across the middle of the formation is the obvious one.

- **A fire carving with more than two tiles of reach** (Meltwater). Every fire in the game reaches
  two tiles (two and a half on the diagonal). So "the enemy melts the ice under you" only works
  when he stands almost on top of the ice, and the player can only melt what is two tiles from
  shore. A lobbed fire at range 3 or 4, for one side or both, would let a lake be wider than a
  moat. The map keeps everything within two tiles of a bank.
- **Ice that weakens before it breaks** (Meltwater). Fire on ice is all or nothing: one hit, open
  water, a drowned unit. A cracked state (one more hit breaks it, or it breaks at the round's end)
  would give the victim a turn to move and the preview something to warn about.
- **Heat that melts ice at a distance** (Meltwater). A burning tile or a heat haze beside ice does
  nothing to it. If standing heat thawed adjacent ice at the round tick, a fire on the bank would
  be a slow fuse, and Stillness and Quickening would have a second use.

## Terrain and tiles

- **A bare loam ground: plain dirt** (The Lime Kiln, and every map after it). The only loam grounds
  are grass, tall grass and trees, which burn, and mud, which costs 2 to cross. There is no
  walkable, fireproof, ordinary earth that still holds ash (for Smokescreen) and water (for an
  Extract). Stone floor and sand hold neither. The Play API even prints the stone floor as "dirt".
- **A kiln mouth, forge or brazier tile** (The Lime Kiln). The lantern is the only lit prop. It
  works as a fire source but reads as a street lamp.
- **A low wall that blocks a swing but not a lob** (The Lime Kiln). Rock blocks everything. A
  parapet that stopped Splash and let Zap or a thrown flask over would let a designer separate the
  two reaches.

- **A barricade that fire opens** (Chaff). Fences burn, but a burnt fence is still a wall. A fence
  or brush wall that becomes walkable scorched ground would let fire cut a route as well as close
  one. The first sketch of Chaff had fenced fields the player burned through; the shipped board has
  open floor.

- **Ice that shows what is under it** (Meltwater). Ice over a ford and ice over a lake are the same
  to the Play API's board and, as far as I can tell without having looked, to the tile's art. A
  map about which ice is safe needs the player to be able to see the difference.

## Units, gear and enemies

- **An enemy that throws water** (The Lime Kiln). #1649's note says to let the enemy teach a key by
  using it on you first. No enemy kit lays water on a tile the AI will aim at the ground, so nobody
  can slake the quicklime under the player. A "Quencher" with Splash, aimed by the AI at burning or
  quicklime ground, would do it.
- **A named heavy-armour enemy file.** Each board rebuilds "CON 12 in Riveted Mail" from the Bandit.
  A catalogue of enemy archetypes (bulwark, marksman, kindler, mender) would keep them consistent
  across boards.

## Objectives and mission rules

- **Extract that lets a wounded unit be left for a cost** (Chaff). Every living unit must be in the
  zone, so one slow straggler decides the mission. That is the design, and it made a good ending,
  but a board cannot say "four of five is a win, five of five is the good ending".
- **A clock the player can buy time on** (Chaff). The round limit is a flat number. A limit that
  slipped by a round for each enemy leader killed, or stopped while a zone was held, would let a
  map reward the fight it stages instead of only taxing it.

## AI

- **A Sentry that steps out of scalding steam** (The Lime Kiln). The guards stood in thick steam
  for two rounds at their post. That is what makes the map work, and it is also not what a guard
  would do. If it changes, hazard squads at a post need a reason they cannot step away (a narrow
  post, or a zone that is all cloud).

## Authoring tools

- **A way to build a board from a script.** These maps came from a scratch script that reads a
  small text spec (rows of ground glyphs, a height grid, lists of states, zones and units) and
  paints through the brush's doors, then saves with the game's writer. It is not committed, under
  this run's scope. As a shipped dev tool it would make a board reviewable as a diff of its spec.
- **A `reload` on the Play API bridge.** After a board is rebuilt on disk, `load` serves the copy
  the process cached, so the bridge has to be restarted to see the new file.
