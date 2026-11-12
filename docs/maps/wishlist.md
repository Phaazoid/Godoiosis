# Wish list: what a map wanted and could not have

**CLAUDE-AUTHORED, unreviewed.** Each entry is something a map design reached for that does not
exist today. They are ideas for future content and rules, not requests, and none is filed as an
issue. Newest at the bottom of each group.

Each entry says which map wanted it, what it would have done there, and what the map does instead.

## Alchemy and transmutations

- **Rain, or a Wet body, slaking quicklime** (The Lime Kiln). Today only a water *hit* slakes. If
  rain did, a drawn weather would turn the yard into a different fight; if a soaked unit stepping
  onto quicklime did, wading the drain would be a way to spring it. The map uses a clear sky and
  one Splash. *(The rain half is built by #1660, 2026-11-11: the rain strikes the ground with water
  at each round's end. A Wet body stepping onto quicklime still does nothing.)*
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
  be a slow fuse, and Stillness and Conflagration would have a second use.

- **Thunderstone that carries a current** (The Glass Walk). Fused sand is a source for an Extract
  and nothing more. As a conductor, a line of it would be a fuse the player lays across a floor.
- **A Zap that can be aimed at a stone to jump from it** (The Glass Walk). The stepping-stone walk
  costs a turn a stone. A carving that drew from one thunderstone and struck from the next would
  make a field of stones a network instead of a path.

- **A time mark whose shape can be turned** (Cinder Row). Stillness and Conflagration cover the two
  rows north of the aimed tile, three wide, whichever way the caster faces. Every yard on Cinder Row
  is north of the street for that reason. A circle around the aimed tile, or a shape that turns
  with the cast, would let a fire be held from any side.
- **Stillness that lasts as long as the caster stands there** (Cinder Row). Two rounds, then recast.
  A held fire that stays held while Isaac spends his action on it each turn is the same cost and a
  clearer picture: he is the one holding it.
- **Time marks on something other than heat** (Cinder Row). `Still(X)` parses for any substance and
  only the heat ones ship. Smoke, steam, a soaked or chilled body, a downed unit's clock.

- **Raised earth: a wall for a round or two** (The Salt Stair, and the dev's own example). Behind
  your own unit it is a backstop against a shove. Across a squad it cuts the cohesion path. Under a
  ledge it is a step. The Salt Stair has two fixed rocks doing the first job; the note says where
  the carving would replace them.
- **A pull** (The Salt Stair). Push and Pull are both verbs, and only Push ships (Gust). A carving
  that drags a unit two tiles toward the caster would let the player haul a Warden off his ledge
  from the side, and would give the enemy a way to drag a unit onto the spine.
- **Wind as a rule** (The Salt Stair, Chaff). A tile added to shoves and gas going downwind.

- **A carving that moves or buries a vein** (The Lodes). Every answer to a vein-bound caster today
  is "move the caster". Moving the vein is the other half.
- **A vein that does something when nobody stands on it** (The Lodes). The alkahest vein was worth
  one cast and then sat behind the lines. A vein that slowly charged a tile, or that a unit could
  tap for a vial's worth once, would be worth holding.

- **A carving that dries a body** (Stormgate). In a storm everyone is a conductor. Chilled takes
  Wet off as a side effect of a 14-point hit. A cast that dries three of your own units would be
  the direct answer to the weather, and the reason to bring a fire or air caster to a rain map.
- **A Zap the caster can shape** (Stormgate). Dorian never cast: every target had an ally in the
  chain. A Zap that stops at the first body, or one that skips bodies the caster names, would let
  the board's own carrier do something in the map built around it.

## Terrain and tiles

- **A tile that breaks a chain** (Stormgate). Duckboards, a rubber mat, a roof: one tile where a
  Wet body does not conduct. It would give "where do I stand" an answer other than "alone".

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

- **A ledge a unit can be shoved off and survive** (The Salt Stair). A fall does 2 a level and a
  hole kills. There is nothing between: a drop into a pit the unit must climb out of, or a ledge
  with a long fall that downs. The board had to choose between a tickle and a death.
- **A rail or parapet tile** (The Salt Stair). Something that stops a shove and can be walked past
  on the other axis, so a safe tile is a place on a path and not a dead end beside a rock.

## Units, gear and enemies

- **An enemy that throws water** (The Lime Kiln). #1649's note says to let the enemy teach a key by
  using it on you first. No enemy kit lays water on a tile the AI will aim at the ground, so nobody
  can slake the quicklime under the player. A "Quencher" with Splash, aimed by the AI at burning or
  quicklime ground, would do it.
- **A named heavy-armour enemy file.** Each board rebuilds "CON 12 in Riveted Mail" from the Bandit.
  A catalogue of enemy archetypes (bulwark, marksman, kindler, mender) would keep them consistent
  across boards.

- **A way to see an enemy's job before the first blow** (The Champions' Yard). Iron Will, Crisis
  and Brace each changed a fight completely and none of them is on the line the Play API prints
  for a unit. If the info card shows them, good; if not, each is an ambush.
- **A carving that sets a body alight** (The Champions' Yard). Iron Will caps a hit at 6; a burn
  that ticks is the answer that is not a hit. Today only a tile burns, and only fuel tiles.

## Objectives and mission rules

- **Extract that lets a wounded unit be left for a cost** (Chaff). Every living unit must be in the
  zone, so one slow straggler decides the mission. That is the design, and it made a good ending,
  but a board cannot say "four of five is a win, five of five is the good ending".
- **A clock the player can buy time on** (Chaff). The round limit is a flat number. A limit that
  slipped by a round for each enemy leader killed, or stopped while a zone was held, would let a
  map reward the fight it stages instead of only taxing it.

- **A third side that fights both** (the planned Three Banners). `Team.is_enemy` makes PLAYER and
  ALLY hostile to ENEMY and nothing else; NEUTRAL and OTHER fight nobody. A three-way battle where
  the player turns two enemy groups' fire and gas on each other cannot be built. The turn cycle
  already supports the extra faction; only the hostility table is missing.
- **An objective for the escort to do something at the end** (Cinder Row). The Chandler walks to a
  zone. A unit that must reach a tile and spend an action there (light a beacon, open a gate) would
  give the last round a beat.

- **Capture that has to be held, or that a living defender blocks** (The Lodes). Capture is one
  action from any free tile of the zone, and nobody takes it back. A fast unit can claim a guarded
  site without fighting. The Lodes works round it by making each zone the one tile its keeper
  stands on. A zone that cannot be claimed while a hostile stands in it would let zones be shapes
  again.
- **A downed unit that does not hold a capture tile** (The Lodes). A keeper's body blocks his tile
  for three rounds after he falls. Twice the mission waited on a bleed-out.

- **A defended point that is lost at the end of a round, not on the step** (Stormgate). An enemy
  that ends one move on the gate ends the mission, even with every other enemy down. "Lost if an
  enemy holds it at the round's end" would give the player one turn to throw him off it.
- **Allies the player can speak to** (Stormgate). The militia are AI-run and cannot be told to
  step out of a line or out of a puddle. One order a turn to an allied squad (hold, fall back,
  spread out) would make them part of the plan instead of part of the board.

- **Weather that changes the ground** (The Drowned Orchard). Rain that damps or stops a grass
  fire. Snow that freezes shallows after a few rounds. A drawn weather would then decide which key
  exists on a board, not only which one hits hardest. *(Built by #1660, 2026-11-11: rain puts a
  fire out at the round's end, and snow freezes all open water from the end of round 3.)*
- **A hazard that hurries its victims** (The Drowned Orchard). The safe answer to a posted squad on
  fuel is to light it and end the turn a dozen times. Fire that spread two tiles a round in dry
  air, or a posted squad that broke and ran for water when its post caught, would turn the wait
  into a chase.

- **A count of the answers before the order is aimed** (The Long Dark). An attack on one of three
  units standing together drew three reactions. The ranges view shows who can strike a tile next
  turn; it does not show who will answer a blow struck from it now.
- **A body that cannot be healed while it is down, or that stands when it is** (The Long Dark; bug
  log B3). A healed, downed, clockless body is a wall nobody chose to build.

- **A wounded unit that can be carried** (The Long Dark, The Saps). Extract waits for the slowest
  unit, and a unit with a leg off moves two tiles a round. Nine rounds of one mission were that
  walk. A sound unit carrying a wounded one at its own pace, at the cost of its action, would
  make the last stretch a decision instead of a wait.
- **A road choice the player is shown** (The Long Dark). The board has two roads and nothing on
  the pre-mission screen says so. A line on the mission card, or a look at the whole board before
  deploying, is what would make it a choice.

## AI

- **A posted squad that leaves a burning post** (The Drowned Orchard, The Lime Kiln). Not to
  attack: to live. Today it either stands in the fire or charges through it.

- **A Sentry that steps out of scalding steam** (The Lime Kiln). The guards stood in thick steam
  for two rounds at their post. That is what makes the map work, and it is also not what a guard
  would do. If it changes, hazard squads at a post need a reason they cannot step away (a narrow
  post, or a zone that is all cloud).

- **A watch that can be told what to wait for** (The Marshal's Charge). "The first enemy that is
  not down", or a named unit. Two Overwatch shots meant for a fire caster went into a pike that
  was shoved into the lane.
- **A fire the AI respects** (the dropped Fire Wall board). If a squad would not end a move on a
  burning tile at all, a line of fire would be a two-round wall today, and half of this list's
  requests for raised earth would already have an answer.

## Authoring tools

- **A way to pick the weather when testing a drawing board.** I built three scratch copies of The
  Drowned Orchard with one weather locked in each. A `weather` argument on the Play API's `load`,
  and a dropdown beside Restart in the game, would do the same without a second file.

- **A way to build a board from a script.** These maps came from a scratch script that reads a
  small text spec (rows of ground glyphs, a height grid, lists of states, zones and units) and
  paints through the brush's doors, then saves with the game's writer. It is not committed, under
  this run's scope. As a shipped dev tool it would make a board reviewable as a diff of its spec.
- **A `reload` on the Play API bridge.** After a board is rebuilt on disk, `load` serves the copy
  the process cached, so the bridge has to be restarted to see the new file.
