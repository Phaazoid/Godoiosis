# Verticality — What Elevation Does To The Rules

**Status: DECIDED (rules shape), WORKSHOP (numbers).** Produced by the design session the dev
requested on 2026-08-13 and ran on 2026-08-14 ([#218](https://github.com/Phaazoid/Godoiosis/issues/218)),
grill-style. Every ruling below is his; the rationale is recorded because almost none of it is
re-derivable from the code. Numbers (tolerances, drop damage, the 2D offset) are deliberately absent —
they are feel values and get knobs, not guesses (`CLAUDE.md` → the tuning rule).

**Canon checked through #340 (2026-08-16).**

The one-line version: **a cell has a height, height changes only via ramps, ramps are chokepoints
rather than tolls, and what height buys you is REACH — not damage, not to-hit.**

---

## The frame: platforms and ramps, not Z arithmetic

The dev's reframe, and it is the load-bearing one:

> *"for movement costs, we don't need to make a complicated Z value calculation — we just need to
> think about directionality of platforms/ramps."*

So the board is **contiguous same-height platforms connected by directional ramps**. Nothing in the
movement rules ever computes `abs(z_a - z_b)`; the only arithmetic is equality and ±1. Everything
below follows from taking that literally.

### Where height lives

**A per-cell store, serialized into `ScenarioData` beside `terrain_states`.** Two fields per cell:
`elevation: int` and `ramp_rise: Terrain.RampRise`.

> **AMENDED at build time (#257).** This originally read `ramp_axis: {NONE, NS, EW}`, which cannot
> say which side of the ramp is high — a ramp at height N with an EW axis climbs to *either*
> neighbour, and if both sit at N+1 the rule has no answer. `RampRise { NONE, NORTH, SOUTH, EAST,
> WEST }` is **the direction the ramp rises toward**: one field carries the axis *and* the high side,
> and "no sideways entry" collapses to a single question — does this step run along the rise axis?
> Built as `Terrain.RampRise` with `Terrain.rise_direction` / `Terrain.is_on_rise_axis` beside it.

**Not tileset custom data.** This was the first proposal and it is wrong: `walkable` / `move_cost` /
`terrain_type` / `terrain_name` are per-TILE (per atlas coordinate), not per-cell. Elevation as tile
data would need a distinct grass tile per level — 21 of them for a 20-level map — and a Tile Brush
palette that explodes. Per-cell also makes painting it a **brush mode** rather than a palette entry,
which is the shape #174 already established for Tile States.

**Its own store, not folded into `TerrainStateManager`.** That manager holds a *stack of enum states
with durations*; height is a scalar with different serialization and a different lifecycle. And the
lifecycle is not guaranteed static forever — [terrain.md](terrain.md)'s "attack the map" list already
carries **EARTH raising a destructible wall**, so nothing should be built on the assumption that
height never changes mid-battle.

**`walkable` keeps its own meaning and is not duplicated.** `walkable = false` answers *may anything
ever stand on this ground* (water, void, solid rock). Elevation answers *at what level does its
surface sit*. Two questions, two homes. A "wall" is therefore not a new concept — it is a tall column
with no ramp reaching it.

### A ramp's height is its LOW side [DECIDED]

A 45° ramp's surface spans two levels, but heights are ints and a unit standing on one needs a single
number for the tolerance check, the shove and the fall. **Low side** — a ramp is a floor tile at level
N that connects upward to N+1, and the climb happens at its top edge.

Rejected: **high side** (makes a ramp a third kind of thing rather than an annotated floor) and
**half-steps** (turns every comparison in the system into a float, for very little).

The visual midpoint stays purely presentational and already is — `UnitSprite3D.stand_at` is an
injectable `Callable` precisely so the walk demo could lower ramp cells without the component knowing
about boards. `BoardPicker`'s *"ramps count as full blocks"* is ray-intersection geometry, not a
statement about level, and does not conflict.

---

## Movement

`RulesService.movement_cost(cell, unit, board)` and `can_traverse(cell, unit, board)` are **cell**
questions. Every verticality movement rule is an **edge** question — *from where?* — so the rules
engine grows one:

- **`can_stand(cell)`** — unchanged, the existing cell-scoped answer.
- **`can_step(from, to)`** — new. Same height → ordinary terrain rules. Different height → legal only
  if one of the two cells is a ramp whose axis matches the step direction and whose high/low sides
  line up. **Ramps connect exactly ±1**, so a 5-tall cliff is a staircase of five ramp cells or it is
  not climbable at all.

  **BUILT in #257.** Because a ramp's own elevation is its LOW side, the climb happens when *leaving*
  it and the descent when *entering* it — so the two height clauses read opposite cells: `+1` is
  legal iff `from` is a ramp whose rise equals the step, `-1` iff `to` is a ramp whose rise opposes
  it. The sideways guard is **two clauses, one per cell**, and they are tested separately: the
  2026-08-12 stage-2 round found that a case covering only *leaving* a ramp sideways let the
  entering-guard mutant survive.

**Blast radius is small, which is why the movement half is slice 1.** `movement_cost` has exactly ONE
production caller (`compute_move_range`'s BFS) and it already holds `current_cell`. `can_traverse` has
three: `movement_cost`, `path_hops` (also a BFS holding the previous cell), and
`AITactics._standable_firing_cells` — and that third one asks a genuinely cell-shaped question
("could anyone stand here") and correctly does **not** change.

### No climb cost [DECIDED]

> *"Let's not actually add extra move cost to going up ramps right now."*

So `movement_cost` never *adds* anything for height; the `from` parameter exists purely to answer
*is this step legal*. The consequence is a good one: **verticality's movement tax is the detour, not
the climb.** Ramps are routing chokepoints, and a 20-level cliff city costs a mover exactly what flat
ground costs so long as ramps connect.

`path_hops` is deliberately **unweighted** ("how terrain connects, not what a move costs"), so a ramp
climb costs 1 hop for cohesion and AI routing regardless of anything added later. That is correct and
someone will eventually try to "fix" it — it wants a comment at the site.

---

## Squad range — already solved, build nothing

Dev ruling: *"anything that blocks line of sight (1 block tall) should block squad range, like we
already have it today with unwalkable terrain."*

**This falls out for free.** `SquadCohesion.field` is a `path_hops` walk over `can_traverse` — a
connectivity field, not a radius. The moment a 1-level step without a ramp is un-steppable, the
cohesion leash routes around a cliff exactly the way it routes around water today. Same mechanism, not
a lookalike; zero new code.

---

## Targeting — height buys reach [DECIDED]

**Per-attack, asymmetric vertical tolerance**, checked *alongside* Manhattan distance, never folded
into it. Each attack authors an up-tolerance and a down-tolerance; a sword might be 1 up / 2 down, a
carbine tighter, a lobbed shell looser.

### Why it is a separate check and not added to distance

The first proposal was "add the height difference to the distance cost". The weapon roster kills it.
`ManhattanRangePattern` defaults to `min_range = 1, max_range = 1`, and ChainSword, Kinetic Mace,
Springspear, TheJaw and Blowback all take the defaults. **The Carbine is `min_range = 2,
max_range = 2`** — and under the additive model a target one level up at Manhattan 1 becomes
1 + 1 = 2, landing *inside* [2,2]. The gun could shoot the man on the ledge directly above it but not
the one further along that same ledge. Mixing vertical distance into a horizontal budget that has a
*minimum* is incoherent.

The additive model also made *any* height difference a total melee barrier in both directions, since
almost everything is range 1. The dev rejected that outright: *"I don't like the idea of not being
able to melee up a slope."*

### Melee is IN the system [DECIDED]

> *"melee can be in the check too. We might want to edit some crazy melee attacks down the line.
> Let's keep the tool flexible."*

Melee is not exempted — it is authored with tolerances loose enough not to bite. **One mechanism,
content decides.** This is the same shape as `arc_clearance` below: a number on the attack, never a
category the code branches on.

### The aim, not the footprint

The vertical check attaches to the **aim** question (`Reach.can_hit_cell_from` /
`get_all_attack_cells_from`), not the **footprint** question (`get_affected_cells_from`). Whether a
blast covers a volume is a different question from whether the shot could be placed there. This
roughly halves how much of `Reach` has to learn about the board — and `Reach` is currently entirely
board-blind, so that matters.

### What this buys, all from one rule

- **Height advantage** — the high ground covers more than the low ground can answer.
- **Counter denial, with no new rule.** `SquadManager:384` is the counter-reach check; a unit two
  levels up with an up-tolerance-1 weapon below it simply generates no counter.
- **The AI sees it with zero AI-side wiring** — `AITactics` probes candidates through `Reach` and
  scores through the real `PlanResolver`. That satisfies #117's standing lesson and the integration
  contract in `CLAUDE.md`.
- **The "invulnerable ledge camper" becomes an authoring dial**, not a rules problem: a 1-level
  terrace is crossable by most melee, a 2-level one is a genuine barrier. Same power-gating argument
  as the shove kill — the level designer sets the frequency.

### `ResolvedOutcome.elevation_delta` — the wire for later [DECIDED, v1]

> *"it is important that we can track *if* attacks are happening up and down slopes so the wiring is
> there for later."*

The resolver stamps `elevation_delta` (target height − attacker height) onto each `ResolvedOutcome`.
No behaviour in v1; a future height-damage rule reads it, and the hover card can say "uphill"
immediately.

**It must be FROZEN, not re-derived** — the same reason `fired_attack` is stamped at declare time.
Units get shoved mid-pass, so re-deriving the delta later from live positions would give a different
number than the one previewed, which is a Law #2 break.

This is not pre-building a deferred seam ([`CLAUDE.md`](../../CLAUDE.md)'s counterweight rule): it was
explicitly requested, it is one field, and it is computed where the resolver already holds the board
and both cells.

---

## Line of sight — three consumers, three rules [DEFERRED past v1]

Dev ruling: *"I think these are going to be fundamentally different things, and a bit case by case."*
That is right, and **the mistake to avoid is building one shared LoS service they all call.** The
question only looks singular:

| Consumer | The question it actually asks | Answered by |
|---|---|---|
| **Squad range / cohesion** | can I *walk* there? | `path_hops` — already done, see above |
| **Flat-trajectory aiming** | is the profile between us clear? | a raycast (deferred) |
| **Lobbed aiming** | how high can I clear? | the same raycast, different threshold |

### `arc_clearance: int`, replacing the planned `arcs_over_obstacles: bool`

The dev's unification, and it deletes a flag before it was ever built:

> *"shots are just lobs who answer 'how high is too high?' with 1... But we can't lob fireballs over,
> say, 20 tile high walls."*

So clearance is **a number, not a category**. A gun clears nothing; a fireball clears some; nothing
clears infinity. No shot/lob classification, no second code path. The boolean is doc-only today
(named as "planned" in `CLAUDE.md` and [weapons.md](weapons.md)) — **both should now say
`arc_clearance: int`**, and no code is owed until evaluation lands.

**When it does land, measure clearance against the shot's LINE** (interpolated shooter→target), not
against the shooter's own height, with an **eye-height offset of 1**. Without the offset, standing on
a cliff edge blocks you from shooting down past your own ledge — technically defensible, infuriating
in play.

### The cost of deferring it, stated honestly

**V1 lets a gun shoot through a cliff at a same-level target.** There is no cheap approximation that
fixes this — a target one level up at three tiles is a *legal* shot, and only a wall between should
stop it, so it genuinely is a profile raycast. The mitigation is not code:

> **Author v1 maps as terraces and slopes, not as sheer walls with things behind them.**

That belongs in the slice-2 ticket, not in a feel-check surprise.

---

## Falls, shoves and tumbles [DECIDED]

### Two kinds of edge

- **A vertical drop** deals **fall damage**, scaled by height fallen and modified by weight
  ([#120](https://github.com/Phaazoid/Godoiosis/issues/120)).
- **A void** — chasm, airship edge, train side — is **removal**, not damage. This is
  [#116](https://github.com/Phaazoid/Godoiosis/issues/116)'s original kill doctrine, intact.

These reconcile rather than compete: a void is a drop with no floor. The cliff city gets both —
terraces that hurt, an outer edge that removes you — and #116's power-gating argument survives
untouched, because the level designer decides which edges exist.

### Shoves

- **You cannot be pushed uphill.** A shove that would climb stops dead. High ground braces you.
- **Only vertical drops give fall damage.** Slopes never do.
- **A shove onto a descending ramp becomes a TUMBLE.**

### The tumble rule

> A shove that steps onto a descending ramp keeps descending while the next cell is another ramp
> continuing down, and ends on the first flat or level cell it can legally enter. A wall, a rise, or
> an occupied cell stops it where it stands. No fall damage.

```
shove →
  F3   R2   R1   R0   F0        one unbroken flight: tumbles F3 → R2 → R1 → R0, ends on F0
  F3   R2   F2   R1   R0  F0    landing at F2 catches it: ends on F2, never reaches R1
```

**A landing stops the tumble** (dev: *"it makes visual sense for flat tiles to stop a tumble"*), and
that is the point — it hands the level designer the dial. One unbroken flight down a cliff-city
terrace is a genuine hazard; a landing halfway makes it survivable. Verticality's danger stays a
map-design decision rather than a number anyone has to balance.

Two consequences, both ruled the conservative way:

1. **The tumble is free — it does not spend knockback distance.** Otherwise a 1-knockback weapon
   could never push anyone down a flight, which is the whole image. Knockback moves its N cells
   normally; if a step lands on a descending ramp, the slide is a bonus, and the tumble **ends** the
   shove rather than resuming the remainder.
2. **The tumble stops at a lip, it does not launch you off it.** If a flight bottoms out at a sheer
   drop, the unit stops on the lip. Fall damage stays restricted to shoves that push a unit
   *directly* over a vertical edge, so the two mechanics never compound into a two-stage prediction
   on day one. Tumble-then-plummet is a fine later addition once the base case has been felt.

Structurally this is cheap: `PlanResolver._resolve_knockback` already publishes `knockback_from` /
`knockback_to` and threads the new position into the hypo, so a tumble is a longer `knockback_to`. No
new channel, and the queue preview shows the landing cell for free.

The existing declared placeholder at that call site — a shove asks the CELL-level `is_walkable`, never
the per-unit `can_traverse`, so a Waterwalker is not shoved onto water — **stays declared and stays
correct**. Being thrown is not walking.

---

## Map scale and authoring [DECIDED]

**No cap on a map's total Z span.** The dev's archetypes, worth using as authoring guidance:

| Archetype | Span |
|---|---|
| Relatively flat | 1–2 levels across the map |
| More interesting | up to ~5 |
| Truly vertical (the cliff city) | up to ~20 |

The earlier proposal to cap at 3 was wrong, and instructively so: it conflated a map's **total span**
with the tallest single **face** that has to be drawn. A 20-level cliff city whose terraces each sit
1–2 above their neighbour needs the same wall art as a 3-level map. And even face height stops
mattering once the 2D wall is a **three-piece autotile — top cap / repeatable middle / base** — after
which any face height is free.

Two costs that *do* scale with span, neither of them art:

1. **2D sprite displacement.** At 20 levels a per-level Y offset stacks into a large visual shift and
   the sprite-overlap problem gets severe. That offset is a feel value, so it ships as an `@export`
   knob and tall maps run a compressed one.
2. **Fall damage.** A 20-level drop should be lethal, which the drop/void split already handles.

---

## The 2D bill

Dev ruling, 2026-08-14 on #218: elevation is **not a 3D-only feature** — the flat 2D view has to
render and play it, and the cost is *"new sprites to represent height differences."* This sharpens the
2026-08-12 standing ruling (*"a Z level is just a variable"*, FFT lineage as evidence) from *"2D
survives elevation"* to *"2D renders elevation, and here is the bill."*

1. **Wall-face autotiles** — three-piece (cap / repeatable middle / base) so face height is free.
2. **Ramp sprites**, per axis.
3. **Per-level sprite Y-offset** for units, plus a drop shadow to anchor them. **A knob, not a
   constant.**
4. **Hover disambiguation — not art.** Offsetting a sprite upward makes a high unit overlap the cell
   *above* it, so the 2D board must separate "cell under the mouse" from "sprite under the mouse".
   That is a `HoverPresenter` change and it is the hidden line item.

---

## Build slices [APPROVED]

Split so each is one reviewable diff and one feel-check, per the bite-sized-parts rule.

1. **Store, `can_step`, 2D face rendering.** Movement only — complete and playable on its own. No
   climb cost, so `movement_cost` gains the `from` parameter purely for legality.
   **NARROWED and BUILT as [#257](https://github.com/Phaazoid/Godoiosis/issues/257):** the rules and
   store half shipped with a throwaway F5 readout instead of real rendering, because wall-face and
   ramp art is gated on a tileset choice that has not been made. The 2D render — wall autotiles,
   ramp sprites, per-level sprite Y-offset, and the `HoverPresenter` sprite-vs-cell disambiguation —
   became its own ticket.
2. **Height → reach.** Per-attack asymmetric tolerances in `Reach` (aim methods only), plus
   `ResolvedOutcome.elevation_delta`, plus the "in range but blocked" preview treatment.
3. **Falls.** Drop damage, void removal, the tumble, the no-push-uphill rule. Closes the
   #116 / #120 interlock.

The dev-tools painting ticket (below) **landed out of order, as #260** — slice 1's store shipped with
only a throwaway readout, so nothing could author a terrace for slices 2 and 3 to be felt on. Then
3D-native authoring, the issue the dev said would follow
[#231](https://github.com/Phaazoid/Godoiosis/issues/231): filed and **BUILT as
[#285](https://github.com/Phaazoid/Godoiosis/issues/285)**, once #273 gave it a board that renders
height to paint onto.

### The preview must keep telling the truth

Axiom 4 and Law #2 apply throughout, and one collision is worth naming now: the attack reach layer is
documented as inviolable — *"drawn once on entering the mode, never filtered or re-tiled"* — but it
must not paint cells that cannot be hit. **Both survive if membership never changes and blocked cells
draw in a distinct state.** Precedent exists: that layer already forks colour red/green off
`AttackData.heals` without touching membership. "In range but vertically out of reach" is the same
move.

---

## Dev tools [BUILT as #260]

Kept deliberately minimal for now (dev): **scroll wheel sets the level the brush places at, with a
dedicated button to reset it to 0.** Painting textures onto wall faces and other authoring niceties
come later and do not gate anything.

**BUILT 2026-08-15 ([#260](https://github.com/Phaazoid/Godoiosis/issues/260)), then MERGED INTO THE
TERRAIN BRUSH 2026-08-16 ([#340](https://github.com/Phaazoid/Godoiosis/issues/340)).** #260 shipped it
as a fourth `TileBrushTool.PaintMode`, **ELEVATION** — a brush *mode* rather than a palette entry,
which is the shape the per-cell store was chosen for. That half is unchanged and still right: a
per-*tile* elevation would need one grass tile per level. What #340 reversed is the **mode**. The
dev: *"I want the elevation brush and the tile brush to not be separate. Ramps are tiles, and tiles
should be paintable at any elevation."* Height was never a different QUESTION from which tile, only a
different STORE, and a mode per store made authoring a raised cell two gestures. So the level and the
rise are now always-live rows on the TERRAIN brush, one click writes tile + level + rise, and
**raising a cell means repainting it at a new level** — there is no height-only gesture. Two
consequences fall out: a paint on virgin board now CREATES the ground it raises (the old groundless
refusal is answered by ordering — tile first, then height), and a ramp wears the tile painted on it
(*Ramps wear their ground* below). One click still writes both height fields, because
`BoardHeights.set_cell` takes both and a cell is one answer; two brushes would be two ways to author
one thing. The wheel is read **first** in `DevController.handle_tile_brush` and returns, so a notch
mid-stroke changes the level without ending the stroke, and it is gated on `event.pressed` because
Godot emits a press *and* a release per notch. Four rulings worth keeping:

- **Negative levels are reachable, deliberately.** The dev: *"if I start designing a level and want a
  dip, without allowing negatives, I would have to shift everything up. no bueno."* Nothing in
  `can_step` cares — its only arithmetic is equality and ±1, which is symmetric about zero. The 3D
  PICKER did care, until [#294](https://github.com/Phaazoid/Godoiosis/issues/294): a column one
  deep tops out at level `0`, which was also its "there is no column here" answer, so a dip read as
  flat inside the authoring apron and was unclickable outside it. `BoardPicker.NO_COLUMN` separates
  the two — **a level is a number, not a truth value**, and nothing may gate on `level > 0`.
- **Elevation goes with the ground.** `BoardHeights.prune_groundless` runs at both sites the tile-state
  sweep does (brush erase, `resize_map`), because a height under no tile is invisible junk that
  resurrects the moment ground is repainted there. The predicate is a **parameter**, not an injected
  `ground_source` field like `TerrainStateManager`'s: that sibling needs one because attacks deposit
  states from many call sites, while this store has one writer and one pruner.
- **The readout lights itself.** Arming the brush that carries a level shows `HeightDebugOverlay` —
  painting height into an invisible store is blind. Its `visible` is **derived** from two named flags
  (F5, and the brush) rather than assigned by either, so leaving the mode cannot switch off a readout
  F5 asked for. That brush is TERRAIN since #340; the rule is unchanged, only which mode owns it.
- **Painting was a 2D-view job until [#285](https://github.com/Phaazoid/Godoiosis/issues/285)
  (2026-08-15)**, because the readout is a child of the flat grid and nothing rendered elevation in
  3D. #273 removed the second half of that, and #285 the first. See *Painting it in 3D* below.

Ramp painting is one 5-entry picker over `Terrain.RampRise`, not an axis plus a direction — the
single field carries both, which is exactly why #257 replaced the sketched `{NONE, NS, EW}`. **Z and
C turn it**, the Q/E detent idiom applied to authoring (dev ask, same day: a menu trip per direction
is the wrong cost for something you change constantly). The cycle is **compass order, not enum
order** — turning has to read as turning, where the enum declares N/S then E/W — and `RISE_CYCLE` is
one list serving both the picker's rows and the keys, pinned against the enum so a new direction
cannot ship missing from either.

**Terrain-tile orientation on the same keys is DEFERRED, and not for cost.** The dev asked for it in
the same breath (*"voxel direction is about to matter"*), and the painting half is nearly free —
`set_cell` already takes an `alternative`, and `TileMapLayer.tile_map_data` serializes it. Two things
put it in the render slice instead: it would settle
[#263](https://github.com/Phaazoid/Godoiosis/issues/263)'s open question (*where a facing comes
from*) by fait accompli, that issue having explicitly listed the alternative-tile flags as the
candidate to *investigate first*; and `BoardMirror.item_for_tile` returns no item for any
`alternative != 0`, so a rotated tile silently falls back to its generic Kind block and loses its art
in the view the game boots into.

**The palette absorbed elevation as [#340](https://github.com/Phaazoid/Godoiosis/issues/340)
(2026-08-16)**, and both questions this section had parked were answered by the dev rather than
stumbled into. Recorded here because the answers are not what the earlier sketch (*"Ramp will just be
another terrain"*) assumed:

1. **Ramp rise vs tile orientation — `Terrain.RampRise` on `BoardHeights` is AUTHORITATIVE, and the
   tile-orientation candidate is RETIRED.** A ramp is *not* a palette entry. Two alternatives were
   priced and declined: a `PropShape.RAMP` column (the `prop_shape`/`wall_edges` precedent) and four
   tiles per ramp terrain with the facing baked in like `wall_edges`. Both put the direction on the
   TILE, which is wrong for a ramp — direction varies per *placement*, and the ramp wedge is already
   the one thing in the mirror that carries a runtime yaw. So Z/C keep turning a per-cell rise, and
   `RulesService.can_step` is untouched.
2. **Yes — a terrain click writes the height too, with no "texture only" escape.** The consequence
   this section predicted is real and shipped: **repainting grass over a terrace flattens it to the
   brush's level.** That is the merge working as asked (a tile is painted AT a height), and it is the
   one part of #340 that is a feel call rather than a code one — the escape hatch, if it is ever
   wanted, is a "texture only" toggle on the brush, not a second mode.

**Ramps wear their ground (#340).** A ramp used to render as `dirt_ramp`, one hardcoded procedural
wedge, whatever was painted under it — so a stone ramp read as dirt. This is the visible half of
*"tiles should be paintable at any elevation"*: `gen_lookdev_assets.gd` now emits a wedge variant per
**FLAT** tile alongside its block, wearing that tile's own atlas UV, and
`BoardMirror.ramp_item_for_cell` picks it by name exactly as `item_for_cell` picks the block.
Measured cost: 293 variants, meshlib 325 → 618 items and 1.35 → 1.85 MB. Two rules hold it together:

- **Only FLAT tiles get a variant, and only flat tiles may slope.** The dev: *"only tiles that are
  flat, not things like rocks, lanterns, etc. grass, mud, etc."* A rock has no top face to tilt. The
  gate is `GridUtils.stands_up_of` — the existing `prop_shape` derivation, not a new predicate — and
  it lives in `TileBrushTool.selected_rise()` so the GHOST reads it too; gated at the paint site
  instead, the preview would show a sloping rock the click then refuses.
- **`dirt_ramp` stays as the fallback, not as dead scaffolding.** The cases `item_for_tile` already
  documents (empty cell, rotated alternative, multi-cell art) reach it, and so does a standing prop
  painted onto a cell that already slopes. Without it those cells render as a hole.
- **TUFT is excluded, deliberately and provisionally.** `stands_up_of` reads a flowery grass tuft as
  standing, so it refuses a rise despite being walkable ground. Its plants would need planting on a
  tilted face via #281's `BoardSpace.surface_transform` — real work, not an oversight.

### Painting it in 3D [BUILT as #285]

**BUILT 2026-08-15.** The premise the issue was filed on turned out to be half stale: painting
elevation from the 3D view **already worked**, because `battle3d` routes to `handle_tile_brush` on
`brush_armed()` alone, `_paint()` is not mode-aware, and the injected `cell_source` is the picked
*column*, which `BoardPicker` already resolves against column tops. What was missing was the
feedback and one binding. Four rulings, all the dev's:

- **A click paints the brush's level, ABSOLUTELY** — the 2D model previewed in 3D, not a
  voxel-editor stack and not Minecraft's clicked-face rule. Two reasons beat the alternatives.
  The wheel stays the *one* authority for "what level", where a relative click would make the
  cursor a second one; and `_paint()` re-fires on every mouse-**motion** event while held, so a
  relative `+1` would run away down a drag, while an absolute level drag-paints a terrace
  idempotently. (The face rule was cheap, not costly — `BoardPicker`'s DDA already distinguishes a
  top hit from a cliff hit and knows which side it crossed. It was declined on feel, not price.)
- **The ghost is the block that would become the column's new TOP** — the cell's own art, at the
  level the click would produce; the **wedge at `level + 1`** when a rise is set, mirroring
  `_write_column`'s own rule. Raising a cell keeps its texture, so the preview resolves its mesh
  off the real grid via the same `item_for_cell` call the board uses.
- **A groundless cell shows NO ghost** — *until #340 reversed it.* The elevation brush could not
  create ground, so a click over a hole was a silent no-op and the ghost stated the refusal in
  advance. The merged brush paints the tile first, so that click is now a real paint and the ghost
  has to show it. The rule it enforced (*elevation goes with the ground*) is intact: erase still
  takes the height with the tile.
- **The wheel is the brush's only in TERRAIN mode.** Zones and Tile States never read it, so camera
  zoom is untouched there; while the terrain brush is armed, `Ctrl+wheel` zooms.

Two structural notes worth keeping. **The ghost answers what a click would PRODUCE**
(`DevController.brush_ghost` returning a `BrushGhost`), replacing a TERRAIN-shaped predicate plus a
separate layer getter — a preview carrying a level cannot be described by a bare cell, since the
level is the brush's. (#285 made that answer per-MODE; #340 collapsed it back to one branch when the
modes merged, and the art now comes off the tile-pick layer, because the paint writes a tile too.)
And **the wheel suppression is DECLARATIVE, not
a consume**: the camera rig is a *child* of `battle3d`, so it sees `_unhandled_input` first and
`set_input_as_handled()` in the parent lands after the zoom has already happened (measured — the
obvious fix is not the one that shipped). `battle3d` stands `CameraRig3D.wheel_zoom_enabled`
down every frame, the same way it borrows the orbit button, and drives the `Ctrl+wheel` notch
itself.

---

## Deferred, and why each is deferred rather than dropped

- **LoS evaluation** (`arc_clearance`, the profile raycast, the eye-height offset) — the model is
  decided, only evaluation is deferred. Mitigated by the map-authoring constraint above.
- **Height → damage.** The dev wants it eventually — *"there might be cases where it can affect damage
  as well, but we can shelve that for a later grill session."* `elevation_delta` is the wire it will
  attach to. Likeliest first case: a heavy melee weapon swung downhill, since falling damage already
  establishes height-as-force in the fiction.
- **3D blast extent.** *"A fire ball can be lobbed, and create a 3D explosion radius where it lands."*
  Explicitly **not** part of this arc — recorded as a supported direction. On a heightmap it needs no
  volume math: it is one more authored number, "the blast covers cells whose surface is within V of
  the impact point," so a fireball on a terrace does not catch the men on the plateau above.
- **Terrain interlocks** — water flowing downhill, fire climbing, fog settling in low ground. A rich
  vein and a separate project; see [terrain.md](terrain.md).
- **30° two-tile slopes** — a presentation experiment noted on #176. If adopted, traversal and the
  ramp-height ruling above must be extended to cover them; everything here assumes 45°, one cell per
  level.
- **Height-modified LDR / cohesion.** Left as pure connectivity, which already behaves correctly.

---

## Sources & cross-refs

Design session [#218](https://github.com/Phaazoid/Godoiosis/issues/218) (2026-08-14). Code:
`RulesService` (`movement_cost` / `can_traverse` / `path_hops`), `SquadCohesion`, `Reach`,
`ManhattanRangePattern`, `PlanResolver._resolve_knockback`, `ScenarioData`, `TerrainStateManager`.
See [terrain.md](terrain.md) (the tile model and the state store), [weapons.md](weapons.md) (patterns
as pure geometry, `arc_clearance`), [presentation-effects.md](presentation-effects.md) (the Triangle
Strategy / FFT reference shelf), [philosophy.md](philosophy.md) (Axioms 3 and 4),
[resolution-pipeline.md](resolution-pipeline.md) (where `elevation_delta` is stamped), and
[`CLAUDE.md`](../../CLAUDE.md) (the three Laws, the tuning rule, the version-label rule).
Related issues: [#116](https://github.com/Phaazoid/Godoiosis/issues/116) (shove/fall),
[#120](https://github.com/Phaazoid/Godoiosis/issues/120) (weight),
[#176](https://github.com/Phaazoid/Godoiosis/issues/176) (the board that renders it),
[#117](https://github.com/Phaazoid/Godoiosis/issues/117) (AI catch-up),
[#231](https://github.com/Phaazoid/Godoiosis/issues/231) (dev tools in 3D).
