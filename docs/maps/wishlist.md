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

## Units, gear and enemies

- **An enemy that throws water** (The Lime Kiln). #1649's note says to let the enemy teach a key by
  using it on you first. No enemy kit lays water on a tile the AI will aim at the ground, so nobody
  can slake the quicklime under the player. A "Quencher" with Splash, aimed by the AI at burning or
  quicklime ground, would do it.
- **A named heavy-armour enemy file.** Each board rebuilds "CON 12 in Riveted Mail" from the Bandit.
  A catalogue of enemy archetypes (bulwark, marksman, kindler, mender) would keep them consistent
  across boards.

## Objectives and mission rules

*(none yet)*

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
