# Verticality — What Elevation Does To The Rules

**Status: DECIDED (rules shape), WORKSHOP (numbers).** Produced by the design session the dev
requested on 2026-08-13 and ran on 2026-08-14 ([#218](https://github.com/Phaazoid/Godoiosis/issues/218)),
grill-style. Every ruling below is his; the rationale is recorded because almost none of it is
re-derivable from the code. Numbers (tolerances, drop damage, the 2D offset) are deliberately absent —
they are feel values and get knobs, not guesses (`CLAUDE.md` → the tuning rule).

**Canon checked through #581 (2026-08-27).**

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

> **RE-SHAPED at build time ([#427](https://github.com/Phaazoid/Godoiosis/issues/427) slice 1,
> 2026-08-23).** The store is now **four corner heights per cell**, `Vector4i(NW, NE, SE, SW)`,
> serialized as one sparse `corner_heights` field. `elevation` and `ramp_rise` survive as **derived
> views** — `elevation_at` is the lowest corner, `ramp_rise_at` reads which corner pair is high — so
> every rule and every renderer below still asks exactly the questions it always asked. That is what
> let the model change without a structural edit anywhere in `RulesService` or the 3D stack.
>
> Corners are per-TILE, **not a shared vertex grid**: two neighbours may disagree about the edge they
> meet on, and that disagreement IS a cliff. A shared grid could not express two flat cells at
> different heights at all.
>
> `ramp_rise_at` was TRANSITIONAL, and the transition is done. Corner slopes are shapes `RampRise`
> cannot name, so through slices 1–2 a corner pattern `push_error`ed rather than quietly reading flat
> — a migration checklist, not a rule, and it found every un-migrated reader. Slice 3 walked the last
> of them and it answers NONE now: the surviving callers genuinely mean "is this one of the four
> cardinal ramps?", `is_ramp` asks the CLIMB instead, and `is_legal_corners` is what refuses ground
> that should not exist.

> **CORNER FORMS, slice 3 (2026-08-23) — a cell's shape is a MASK.** Which corners are raised, plus
> how far. Sixteen masks: `0` is flat, four singles are **outer corners**, the four **adjacent**
> pairs are exactly the cardinal ramps `RampRise` already names, the four triples are **inner
> corners**, and the two **opposite** pairs are the saddles the dev refused. `15` is unreachable —
> the mask names corners strictly above the cell's own low one, and a cell always has one — so flat
> has exactly one spelling. It is [#263](https://github.com/Phaazoid/Godoiosis/issues/263)'s dividend
> a second time: a wall facing became a mask of EDGES and the corner fell out for free; here the
> cardinal ramp stops being its own kind of thing.
>
> **A form is a mask plus a climb, so a cell has at most TWO distinct corner heights.** That is the
> RCT model the reframe asks for, and `Terrain.is_legal_corners` refuses everything outside it: a
> third height, a climb over `UNITS_PER_LEVEL` (the 45° cap, needing no constant of its own because
> that IS the unit), and the two saddle masks. Deliberately a PREDICATE and not a lint tier — nothing
> could author an illegal shape while it shipped, and a check wired to an unreachable surface is a
> check that cannot fire ([#390](https://github.com/Phaazoid/Godoiosis/issues/390)). Slice 4 built
> the first thing that COULD, and the payoff is that it obeys this predicate instead of restating it:
> the tool asks, and is structurally unable to author bad ground rather than merely unlikely to.
>
> **The surface between the corners is TWO TRIANGLES, and which diagonal splits them is real
> geometry.** `Terrain.height_at_uv` joins the two EQUAL corners, giving every legal form a flat half
> and a sloped half — the RCT shape; the other diagonal turns an outer corner into a hip roof. **The
> mesh generator calls that same function** rather than reimplementing its rule, because both
> triangulations meet all four corners and only a point INSIDE can tell them apart: disagree, and a
> unit crossing a corner cell floats or sinks by up to a quarter of the climb.
> `tests/law/test_cap_mesh_matches_the_surface.gd` samples each drawn triangle at its own centroid,
> which is where a wrong diagonal shows.
>
> **`height_at_uv` IS THE ONE SURFACE, and slice 3 shipped a second answer beside it anyway** —
> corrected after slice 4, found in play. `BoardSpace.lie_on` described a cell with a single
> `Transform3D`, i.e. a PLANE, taking its height from the corners' MEAN
> (`Terrain.centre_height_of_corners`). On a planar form the mean IS the surface at the centre; on a
> corner form the two differ by a quarter of the climb, so `surface_point` (where a unit, a flame or
> a prop stands) and `surface_height_at` — which already read `height_at_uv` — disagreed about the
> same cell. The mean is deleted; `lie_on` reads the surface.
>
> **And no transform can describe a corner cell at all**, which is the other half of the same
> mistake. Four non-coplanar points, and an affine transform maps a plane to a plane: the best-fit
> plane CROSSES the ground by a quarter of the climb at every corner, alternating sign — an eighth of
> a cell on the gentle slope against a `fill_lift` of 0.02, which is why it read as z-fighting on the
> tile's flat half and as arrows cutting through it. So **`lie_on` returns an identity basis on a
> non-planar form** rather than a tilt it cannot honour, `Terrain.is_planar_form` is the question, and
> **the FOLD lives in the marker's MESH** (`BoardOverlays._surface_mesh`): four vertices at their true
> heights, split on the diagonal `height_at_uv` splits on, cached by the cell's shape. Planar cells —
> flat ground and every cardinal ramp, i.e. nearly every cell on every board — keep the one shared
> `PlaneMesh` and are bit-identical to before.
>
> **THE Z-FIGHT HE ACTUALLY REPORTED WAS A DIFFERENT BUG, and this one is worth separating from the
> paragraph above.** Corner-cell markup was genuinely wrong and is genuinely fixed — but it was not
> what he was looking at, and the report came back unchanged on a build that carried the fix. The
> cause was in the CAP MESH: `_form_mesh` puts each top-face corner at `lo + height * ROW_HEIGHT`,
> so an **outer** corner — three corners at the low height — has a whole top triangle lying on `lo`,
> the mesh's own floor. `BoardMirror._write_column` then places that cap on a column whose top block
> reaches exactly the cell's surface, which is the same plane: two upward-facing, identically
> textured faces, coplanar to the float.
>
> **A CAP DRAWS NOTHING IN ITS OWN FLOOR PLANE**, and getting to that wording took two passes. The
> first said *"only what rises ABOVE the block it caps"* and removed the flat top triangle — correct,
> insufficient. That plane holds THREE cap faces, and removing one just handed the area to the next:
> the **bottom quad**. Being back-facing it rasterises to no pixels at all, so where it took the depth
> test you saw **straight through the board** — the shimmer became holes, photographed and measured at
> exactly the background colour. The symptom changing is what said the rule was about the PLANE and
> not about any one face in it.
>
> All three are now declined: the side wall of an edge whose corners are both low (always skipped —
> the oldest of the three, and the one the others were derived from), the flat top triangle, and the
> bottom quad. The cap is an open shell whose opening is exactly the footprint the block's top face
> covers, which is why no angle can see inside; and meshlib items carry no collision shape and no
> navmesh, so nothing but the rasteriser ever reads this geometry.
>
> **That last argument became LOAD-BEARING in #559, when `_mat()` stopped drawing back faces.** It was
> written while every generated material was `CULL_DISABLED`, so an opening that *was* exposed would
> merely have shown the cap's own inside surface — opaque, odd, harmless. Under `CULL_BACK` the same
> exposure shows the sky through the board. Nothing about the geometry changed; what changed is that
> "no angle can see inside" went from comfortable to the only thing standing between a cap and a hole,
> so it is now a law rather than a comment — `tests/law/test_a_cap_opening_lies_on_the_block_top.gd`
> requires every boundary edge to lie in the block-top plane and inside the cell, and requires the
> shell to still be OPEN, since a case that passes vacuously the moment the bottom quad returns would
> guard nothing. The block beneath a cap stays load-bearing, and #559 kept a ground block's TOP face
> at its full extent for exactly this reason.
>
> Which form suffers is the whole tell, and it matches the report exactly: a WEDGE's low side is an
> EDGE with no area, so wedges never fought; an INNER corner's flat triangle is at its HIGH plane,
> where nothing else is drawn, so it must survive (a guard widened to "skip every horizontal
> triangle" punches a hole through three quarters of every inner corner). Outer corners only.
>
> **The law needed a correction of its own: it must skip DEGENERATE triangles.** Every cap has one — a
> wall whose first corner is at the floor gets `floor_here` equal to `top[i]`, so the quad's first
> triangle has two identical vertices, zero area, all three heights at the floor. The first draft
> counted those and reported six offenders on geometry that was already right.
>
> An epsilon lift on the flat half was rejected: it would make the drawn cap disagree with
> `height_at_uv`, which is the one law slice 3 rests on, and the flame already taught this project
> twice ([#243](https://github.com/Phaazoid/Godoiosis/issues/243) /
> [#298](https://github.com/Phaazoid/Godoiosis/issues/298)) that coplanarity is fixed by geometry and
> never by a number.

> Two things that had to be threaded and are worth knowing. A SPRITE marker's surface comes from
> `OverlayMirror`, not from a heights lookup, so the cell's shape travels in the marker entry
> **alongside** its basis — not instead of, because the knockback drop pointer supplies an
> orientation of its own and lies on nothing, so "how this is oriented" and "the ground it lies flat
> against" are two questions and an absent shape means airborne. And the generalisable one: the
> renderer's END of that key was pinned while its SOURCE was not, so a mutant deleting it passed the
> whole mirror suite — [#103](https://github.com/Phaazoid/Godoiosis/issues/103)'s shape, caught only
> by falsifying.
>
> Corner cells were authorable only by hand-built fixture for one slice — a declared gap, closed by
> the tool below. The 2D view's sprite forms stay with
> [#266](https://github.com/Phaazoid/Godoiosis/issues/266) as a declared
> [#292](https://github.com/Phaazoid/Godoiosis/issues/292) asymmetry: the hidden 2D authority is
> corner-aware, so parity of RULES is never broken, only of costume.

> **THE CORNER TOOL, slice 4 (2026-08-23) — and #427 closes.** The Tile Brush gains a fourth mode,
> and it does NOT replace the one it sits beside: *"we would want to keep the version of the tool we
> have now, but also have a corner mode. Different tools for different situations"* (dev). The cell
> brush paints a whole tile AT a height and can still author a deliberate cliff between neighbours;
> corner mode drags the POINT four cells share.
>
> **Absolute, not relative.** The wheel picks a height and every point the drag touches goes to it,
> exactly as the cell brush places a level. `DevController._paint()` re-fires on every mouse-motion
> event while the button is held, so a relative `+1` would run away down a stroke where an absolute
> value drag-paints idempotently — the doctrine this doc already records for the cell brush, one
> gesture along. Right-click pulls the point back DOWN to the board floor, as far as the clamp will
> legally let it: the corner reading of "take it away", and symmetric with paint rather than a second
> gesture, since both write one height into one point.
>
> **One ring, clamped.** A drag writes the point's corner in all FOUR touching tiles, so the surfaces
> stay welded — which is what kills the cut-off gap between neighbours that opened this ticket.
> Anything that would make a touched tile illegal is CLAMPED, never cascaded outward:
> `Terrain.corner_toward` walks from the target toward the corner's CURRENT height until
> `is_legal_corners` passes, which terminates by construction because the cell is already legal, so
> the worst case is the corner not moving at all. The consequence is the ruling working as intended
> rather than a shortfall: **a corner stops rising once its own tile would break**, so a tall hill
> takes several strokes across neighbouring points instead of one drag that reaches across the board.
> With the 45° cap at `UNITS_PER_LEVEL` the only height strictly between two legal ones is
> equidistant from both, so "nearest" is genuinely ambiguous there and standing still wins.
>
> **A vertex is `Terrain.VERTEX_CORNERS` and nothing else knows the mapping.** `Vector2i(x, y)` is
> cell `(x, y)`'s NW corner, `(x-1, y)`'s NE, `(x, y-1)`'s SW and `(x-1, y-1)`'s SE. Corners stay
> per-TILE — the store is untouched, and this is still not a shared vertex grid — a vertex is what
> the TOOL addresses. `BoardHeights.set_vertex` is the weld and takes the ground predicate as a
> parameter, on `prune_groundless`'s own justification: a point dragged at the board edge would
> otherwise leave heights in cells that have no tile (#245), and the store cannot reach the grid to
> ask. `Terrain.CORNER_COMPONENTS` bridges a corner BIT to its `Vector4i` component once — the write
> direction of `corner_mask`'s read, and a hand-written `match` at any write site would be a quarter
> of every drag landing silently on the wrong corner.
>
> **The pointer's answer changes halfway ACROSS a cell**, so `battle3d._update_pointer` computes the
> vertex ABOVE its cell early-out. That is [#471](https://github.com/Phaazoid/Godoiosis/issues/471)'s
> law exactly: an early-out is a copy of the render key on the INPUT side, so it has to compare every
> input the answer depends on, and below it the marker would stick to whichever corner the cursor
> first entered the tile by. The sub-cell half is recovered by dropping the same ray onto the picked
> cell's top plane — exact on flat ground, which is what a hill is built out of, and APPROXIMATE on a
> slope by declared choice: the marker shows the answer before any click commits it, and the
> alternative is a per-form ray/triangle intersection in the hot pointer path for a dev tool.
>
> **The preview is a POINT, not a block.** `BrushGhost` gains a declared `Kind` rather than letting a
> renderer infer the mode from an unset `source` — "which kind of preview is this" is a fixed
> vocabulary, and reading it off a field's emptiness is the second-answer shape. The 3D marker is a
> small cube on the vertex at the height the click would set (`BoardMirror`, sharing the ghost NODE
> so only one preview can ever be live); the flat view draws nothing, exactly as it draws nothing for
> a height, and reads the KIND *before* the source — a source compare alone matches `null` against a
> ghost layer that has never been built and paints a tile at the origin.
>
> **Z / X / C stand down in corner mode, and that split the one predicate that gated them.** The
> level row is visible here and the rise and climb rows are not, so `DevController._elevation_brush`
> (the wheel) now answers for two modes while `_shape_brush` (the shape keys) answers for one. They
> were one function only because the two rows had always appeared together; the rule underneath —
> *a control only moves a brush you can SEE* — is unchanged, and `tests/dev/test_height_brush.gd`
> now derives both sweeps from the rows' own visibility rather than hand-listing "the other modes",
> which is what went stale the moment a fourth mode landed.

> **The MIRROR re-metered to match, slice 2 (2026-08-23).** A GridMap row was one whole level, which
> is simply unable to draw a half — so `BoardSpace.ROW_HEIGHT` is `CELL_SIZE / UNITS_PER_LEVEL` and
> the mirror's vertical index counts **one row per height unit**. A mirror cell is no longer a cube.
> `BoardSpace.top_row_of` is the ONE conversion from a rule height to a drawn row, and it replaced
> `Terrain.level_of` at every site that places geometry; `level_of` survives only where a rule
> genuinely counts whole LEVELS, which is fall damage.
>
> A ground slab is still one LEVEL deep, i.e. `UNITS_PER_LEVEL` rows — which is why every world
> position, every camera bound and the whole LookDev diorama sit exactly where they did. The block
> meshes halved and each flat tile gained a gentle wedge; a 45° wedge is one item spanning two rows,
> so the row above it holds an **invisible filler**, because `BoardPicker` reads a column's height
> from which rows are OCCUPIED and a wedge that declared only its base would be clickable to
> mid-slope.

> **AMENDED at build time (#257).** This originally read `ramp_axis: {NONE, NS, EW}`, which cannot
> say which side of the ramp is high — a ramp at height N with an EW axis climbs to *either*
> neighbour, and if both sit at N+1 the rule has no answer. `RampRise { NONE, NORTH, SOUTH, EAST,
> WEST }` is **the direction the ramp rises toward**: one field carries the axis *and* the high side,
> and "no sideways entry" collapses to a single question — does this step run along the rise axis?
> Built as `Terrain.RampRise` with `Terrain.rise_direction` / `Terrain.is_on_rise_axis` beside it.
>
> **SUPERSEDED by [#427](https://github.com/Phaazoid/Godoiosis/issues/427) slice 3.** `RampRise`
> survives as the *authoring* vocabulary — the brush paints cardinal ramps and `corners_of_ramp`
> composes them — but it is no longer the universal *reading*: a cell's form is a **mask of raised
> corners** plus a climb, of which the four cardinal ramps are the four adjacent-pair masks.
> `is_on_rise_axis` is **deleted**, because comparing the shared edge answers it (see the movement
> section below), and `rise_of_corners` answers `NONE` for a corner form rather than erroring.

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

> **The half-step rejection was ANSWERED, not overturned ([#427](https://github.com/Phaazoid/Godoiosis/issues/427)
> slice 1, 2026-08-23).** Half elevations exist now, and no comparison became a float: the UNIT was
> re-based instead. One elevation unit is half a level, `Terrain.UNITS_PER_LEVEL` is 2, and a 45°
> ramp climbs 2 — dev, 2026-08-23: *"our current 45 degree angle platforms will now just hop 2 levels
> instead of one."* Every height compare is still an integer compare; the "for very little" half is
> what changed, since the RCT-style ground the ticket is aimed at needs the gentler slope.
>
> **A ramp's height is still its LOW side, and that ruling is now load-bearing twice over** — it is
> also the reason `elevation_at` can be the corners' MINIMUM and every existing caller keep working.
>
> Two consequences the dev ruled the same day, both of which the re-base delivers without a clause of
> their own: a sheer HALF-level edge **blocks** movement and melee (it is not `UNITS_PER_LEVEL`, so
> `height_step_ok` refuses it exactly as it refuses three), and a half-level drop deals **no fall
> damage** (`FallRules` charges per whole level).

> **Slice 2 made the gentle slope REAL (2026-08-23).** A ramp's steepness is authored per cell now:
> `Terrain.corners_of_ramp` takes a `climb`, `climb_of_corners` is its derived twin beside
> `rise_of_corners`, and the two authorable values are **1** (half a level over one cell, `atan(1/2)`
> = **26.6°** — the RollerCoaster Tycoon slope the dev remembered as 30) and **`UNITS_PER_LEVEL`**
> (the 45° ramp that has always existed). Their twin is a **half-level platform**: the two are
> inseparable, since a gentle ramp from height 0 arrives at height 1 and something has to stand there.
>
> **`height_step_ok` stopped comparing against a constant.** The `abs(delta) != UNITS_PER_LEVEL`
> clause is deleted rather than widened — a step connects when the ramp on the appropriate side
> climbs *exactly* that much along it. The blocking ruling above survives untouched by that (flat
> ground climbs 0, so a sheer 1-unit edge is refused because 0 ≠ 1), and a 45° ramp still refuses a
> half-level edge for the same reason, which is the half a single case cannot see.
>
> `PlanResolver`'s two landing rules ask the same question: a flight slides onto a descending ramp
> for free when the drop equals **that ramp's** climb, and a tumble continues when the next ramp's
> high edge meets this cell's base.

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
  line up. **Ramps connect exactly their own CLIMB** (±1 level until #427 slice 2 made steepness
  authored), so a 5-tall cliff is a staircase of ramp cells or it is not climbable at all.

  **BUILT in #257.** Because a ramp's own elevation is its LOW side, the climb happens when *leaving*
  it and the descent when *entering* it — so the two height clauses read opposite cells: `+1` is
  legal iff `from` is a ramp whose rise equals the step, `-1` iff `to` is a ramp whose rise opposes
  it. The sideways guard is **two clauses, one per cell**, and they are tested separately: the
  2026-08-12 stage-2 round found that a case covering only *leaving* a ramp sideways let the
  entering-guard mutant survive.

  > **REPLACED by ONE COMPARISON in [#427](https://github.com/Phaazoid/Godoiosis/issues/427) slice
  > 3.** `height_step_ok` now asks whether the two cells' shared EDGE has the same two corner
  > heights read from either side (`Terrain.edge_of_corners`). Both height clauses, both sideways
  > guards and the climb arithmetic all fall out of it, so `is_on_rise_axis` was deleted rather than
  > widened — a rule that falls out of the geometry needs no clause standing beside it. Three
  > consequences worth stating:
  >
  > - **Walking ACROSS a continuous slope is now legal** (dev, 2026-08-23: *"let's allow it. I'll
  >   feel test that afterwards"*). Two adjacent ramps rising the same way genuinely meet along the
  >   edge between them, so a unit may cross as well as climb. Provisional, to be judged in play.
  > - **A ramp is enterable strictly from its LOW side.** The old rule compared the two cells' low
  >   corners, so a unit standing on flat ground could step onto a ramp's HIGH edge a level above
  >   it; the edge comparison refuses that. Not a ruling — a bug the restatement removed.
  > - **One cell can answer differently per side**, which is what corner forms need and what no
  >   `(elevation, rise, climb)` triple could ever express.

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

## Targeting — height buys reach [BUILT as #258, 2026-08-20]

**A per-attack vertical rule**, checked *alongside* Manhattan distance, never folded into it. A
ranged attack authors an up-tolerance and a down-tolerance (a lobbed shell looser going down than
up); melee authors the STEP rule instead (below) — the tolerance illustration this section used to
give for a sword did not survive play.

**BUILT as [#258](https://github.com/Phaazoid/Godoiosis/issues/258), REWORKED in review the same
day:** each attack authors its **vertical rule** — `AttackData.VerticalRule.MELEE` for melee (below),
`RANGED` with `up_tolerance` / `down_tolerance` for everything else (`-1` = unlimited, the
default — so a flat board and every heights-less fixture behave exactly as before, the slice-1
contract) — and every point aim must also have a **clear sight trace** (the sight line, below). The
one gate is `Reach.vertical_aim_ok`, and `Reach.can_hit_cell_from` conjoins it with membership — it
takes the `BoardContext` as a REQUIRED parameter (the `movement_cost` precedent: an optional would
give one question two answers). Starter content: melee mains are MELEE; Fireball is 3 up with
`arc_clearance = 3` (clears 1/2/3-walls to the far side, dies on a 4 — the dev's asked-for shape);
guns and the other carvings RANGED-unlimited with clearance 0.

### Lobs vs guns need no second mechanism [DECIDED 2026-08-20]

The dev's observation — *a gunshot just needs line of sight, so it can be shot up an angled ramp;
a lobbed shot can only clear so many tiles in vertical height, so shooting one up a ramp can be
stopped short by the terrain* — is expressed entirely by the two numbers the design already has:

- **Up-tolerance IS the lob's climb ceiling.** A lob fired up a ramp is "stopped short" because the
  terrain carries targets above the ceiling it can reach.
- **A gun authors `-1`** — its only real constraint is the sight trace (`arc_clearance` 0: can't
  shoot through or over walls, any angle fine). This inverts the old illustration ("a carbine
  tighter"): the Carbine ships unlimited. *(Written when the trace was still deferred; it shipped
  the same day — see the line-of-sight section.)*

### Directional spreads are EXEMPT in v1 [DECIDED 2026-08-20]

A ForwardWide/ForwardLine aim is a *direction*, so "is this cell too high" is a question about which
cells the spread covers — the footprint / 3D-blast-extent question, which this doc already defers.
`vertical_aim_ok` returns true for any directional attack (aims, counters, the overlay's blocked set
alike), declared rather than silent. When blast extent lands, that is where a spread's per-cell
height rule belongs.

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

### Melee is IN the system — and its rule is the STEP [REVISED 2026-08-20]

> *"melee can be in the check too. We might want to edit some crazy melee attacks down the line.
> Let's keep the tool flexible."*

Melee is not exempted — it lives in the same gate. But the first build's "authored with tolerances
loose enough not to bite" did not survive play: **tolerance numbers cannot say what melee is.** The
dev, reviewing the build: *"Melee units should have to be on the same step, or on a facing half
step to hit each other. If a unit is next to another unit but on different elevations, melee
attacks shouldn't be queuable."* A sheer 1-level edge is melee-illegal in BOTH directions — which
`1 up / 2 down` wrongly allowed — while the ramp's half step stays legal, which `0 / 0` would
wrongly forbid. So melee authors `VerticalRule.MELEE`: same elevation at any range, or an adjacent
edge that is ramp-connected — judged by `RulesService.height_step_ok`, the height core extracted
from `can_step` so melee and movement can never disagree about which edges connect. (The sideways
guards stay movement-only: swinging past a ramp's side is not walking onto it. **#427 slice 3 made
that moot** — the guards are gone and the shared core is now the whole rule, so melee and movement
answer identically with nothing left to keep movement-only.) Bare fists are
STEP too — punching is melee. The earlier melee worry ("I don't like not being able to melee up a
slope") is exactly what the half step preserves.

### The aim, not the footprint

The vertical check attaches to the **aim** question (`Reach.can_hit_cell_from` /
`get_all_attack_cells_from`), not the **footprint** question (`get_affected_cells_from`). Whether a
blast covers a volume is a different question from whether the shot could be placed there. This
roughly halves how much of `Reach` has to learn about the board — and `Reach` is currently entirely
board-blind, so that matters.

### What this buys, all from one rule

- **Height advantage** — the high ground covers more than the low ground can answer.
- **Counter denial, with no new rule.** `SquadManager.can_counter` is the counter-reach check (it
  now takes the board, threaded down from `resolve_plan`); a unit two levels up with an
  up-tolerance-1 weapon below it simply generates no counter. Pinned by the ledge cases in
  `tests/squad/test_counters.gd`, falsified against the board being dropped.
- **The AI sees it with zero AI-side wiring** — `AITactics` probes candidates through `Reach` and
  scores through the real `PlanResolver`. That satisfies #117's standing lesson and the integration
  contract in `CLAUDE.md`.
- **The "invulnerable ledge camper" becomes an authoring dial**, not a rules problem: a 1-level
  terrace is crossable by most melee, a 2-level one is a genuine barrier. Same power-gating argument
  as the shove kill — the level designer sets the frequency.

### `ResolvedOutcome.elevation_delta` — the wire for later [BUILT, #258]

> *"it is important that we can track *if* attacks are happening up and down slopes so the wiring is
> there for later."*

The resolver stamps `elevation_delta` (target height − attacker height) onto each `ResolvedOutcome`.
No behaviour in v1; a future height-damage rule reads it, and the hover card can say "uphill"
immediately.

**It must be FROZEN, not re-derived** — the same reason `fired_attack` is stamped at declare time.
Units get shoved mid-pass, so re-deriving the delta later from live positions would give a different
number than the one previewed, which is a Law #2 break. Built exactly so: the stamp reads the frozen
`origin_cell` against the THREADED hypo position (the same pair `_resolve_knockback` uses), and the
queue row already prints an `uphill`/`downhill` token off it. Pinned by
`tests/law/test_elevation_delta.gd`, whose shove-then-hit case is falsified against the live read.

This is not pre-building a deferred seam ([`CLAUDE.md`](../../CLAUDE.md)'s counterweight rule): it was
explicitly requested, it is one field, and it is computed where the resolver already holds the board
and both cells.

---

## Line of sight — three consumers, three rules [BUILT for aiming, 2026-08-20]

Dev ruling: *"I think these are going to be fundamentally different things, and a bit case by case."*
That is right, and **the mistake to avoid is building one shared LoS service they all call.** The
question only looks singular:

| Consumer | The question it actually asks | Answered by |
|---|---|---|
| **Squad range / cohesion** | can I *walk* there? | `path_hops` — already done, see above |
| **Flat-trajectory aiming** | is the profile between us clear? | `Reach.sight_trace` (clearance 0) |
| **Lobbed aiming** | how high can I clear? | the same trace, arced by `arc_clearance` |

### `arc_clearance: int`, replacing the planned `arcs_over_obstacles: bool`

The dev's unification, and it deleted a flag before it was ever built:

> *"shots are just lobs who answer 'how high is too high?' with 1... But we can't lob fireballs over,
> say, 20 tile high walls."*

So clearance is **a number, not a category**. A gun clears nothing; a fireball clears some; nothing
clears infinity (which is why the field has no unlimited sentinel). No shot/lob classification, no
second code path.

### The drawn path IS the rule [DECIDED + BUILT 2026-08-20]

The deferral did not survive its first real board — the day the tolerance half shipped, the bug
reports showed a Carbine shooting through a 3-high wall and a Fireball lobbed over a 4-high one. The
dev's ruling on how to build it reshaped the model from "raycast plus threshold" into a readout:

> *"I think we need to literally have a line drawn (we can represent it as a bead in game) between
> the player and their target. If the bead can find the target, the shot is valid. If not, not
> valid."*

"Bead" as in *having a bead on someone* — an aim, not dots (dev clarification, same day): the
readout is a **laser sight line**. So there is ONE trajectory, and both the gate and the drawn line
evaluate it (`Reach.sight_trace`; the constant `Reach.EYE_HEIGHT` and the arc term live nowhere
else):

```
h(t) = lerp(elev_origin + EYE, elev_target + EYE, t) + arc_clearance * 4t(1 - t)
```

- **Endpoints at the SPRITE'S CENTER** (EYE = 0.5 — dev: the line "should originate from the center
  of the sprite rather than the top") — the #218 offset's purpose survives: standing ON a cliff
  edge, your own shot down clears. Standing one cell BACK from a tall edge, your own lip can occlude
  a steep shot — real lip occlusion, step forward to shoot. A target standing on a far lip is
  silhouetted and shootable; a step back and it is covered.
- **A gun (clearance 0) is a straight laser; a lob's line visibly arcs**, peaking `+clearance`
  mid-flight — so what a fireball can clear is literally drawn, not inferred (the straight look is
  reserved for guns by construction).
- **Blocked at the first crossed cell whose column reaches the line — touch = blocked.** A line that
  grazes a wall-top visibly dies there, and a 1-high wall stops a flat shot (the dev's standing
  "anything 1 block tall blocks line of sight"). The crossed cells come from
  `GridUtils.cells_crossed` — supercover, endpoints excluded, corner-ties take BOTH cells, so a
  shot can never thread a diagonal seam between two walls.
- **Terrain only; units never block** — they move every turn, so a unit-blocked preview could not
  stay truthful (Law #2).
- **The readout**: `HoverPresenter` computes the trace once per hovered aim and stores it on
  `OverlayManager` (`show_sight_trace`, with `sight_trace_version` as the mirror's #308-style
  change signal); `SightTrace2D` draws the polyline flat, `OverlayMirror` lifts the same points
  into the diorama at their true heights (`BoardOverlays.Layer.SIGHT_TRACE`, the sink's LINE kind).
  **Only ranged point aims draw it** (`Reach.draws_sight_trace`): melee is "visually obvious
  anytime" (dev) — STEP attacks and bare fists show no line, though the gate still judges their
  trace — and a directional spread has no single line. Pinned by
  `tests/weapons/test_sight_trace.gd` — including the law that the gate and the trace can never
  disagree — falsified against a wrong eye height and against the version bump being dropped.

**Stale-content trap, paid once the day this shipped:** a scenario snapshot EMBEDS carving copies,
and `.tres` omits defaulted fields — so a board saved before `arc_clearance` existed loads its
embedded Fireball with clearance 0 and lobs it flat (plus `up_tolerance` unlimited). That was the
"lob can't clear a 1-wall" bug report in its entirety; the fix was content (patch the embedded
copy), not rules. Boards saved before an `AttackData` field existed need a re-save to pick it up.

---

## Falls, shoves and tumbles [BUILT as #259, 2026-08-20]

### Two kinds of edge

- **A vertical drop** deals **fall damage**, scaled by height fallen and modified by weight
  ([#120](https://github.com/Phaazoid/Godoiosis/issues/120)).
- **A void** — chasm, airship edge, train side — is **removal**, not damage. This is
  [#116](https://github.com/Phaazoid/Godoiosis/issues/116)'s original kill doctrine, intact.

These reconcile rather than compete: a void is a drop with no floor. The cliff city gets both —
terraces that hurt, an outer edge that removes you — and #116's power-gating argument survives
untouched, because the level designer decides which edges exist.

### The shove is AIRBORNE [REVISED at build, 2026-08-20 — supersedes the step-wise text below]

> *"The drop occurs where the shove would move the unit to. This means you could potentially blow
> allies over holes to safety. Also, when a unit lands, if they land on a slope, they tumble down
> that too."* — dev

So a shove is **one flight, one landing** (`PlanResolver._knockback_landing`):

- **The flight** travels the knockback distance at the unit's STARTING elevation. A cell higher
  than that **braces** it ("you cannot be pushed uphill" — the flight stops before it); a **VOID
  cell is flown over**; walls, bodies and off-board stop it exactly as before. **WATER CATCHES it**
  ([#116](https://github.com/Phaazoid/Godoiosis/issues/116), 2026-08-26): the flight ENTERS the
  first cell the unit cannot stand on and stops *in* it, where it used to stop dry on the bank —
  deliberately not the void's fly-over, because a hole cannot catch you and a lake can, and stopping
  at the water's edge is what keeps the body inside a rescuer's reach. The stop question is
  per-unit now (`RulesService.drowns_in` / `can_traverse`), which is why a Waterwalker is shoved
  *onto* the water and stands there rather than being braced by ground it walks on every turn.
- **The landing** resolves wherever the horizontal travel ends — distance spent *or* blocked early.
  Ending on a VOID (blown onto it, or halted mid-flight over it) = **removed**. Ending in **deep
  water** = the water takes whatever the blow and the fall left, so the unit goes DOWN on the
  ordinary clock and a rescue can haul it out (`terrain.md` → *Water — shallow vs deep*). Ending
  lower =
  **fall damage** for the full levels dropped — `FallRules.damage_for`, which **bypasses DEF**
  (dev: armor does not stop gravity; it joins the total after mitigation, before the Iron Will cap
  so the cap stays absolute) and carries the #120 weight term (inert until gear has mass). Ending
  on the doc's original tumble entry (a connected descending ramp — its high edge meets the flight
  level) = a free tumble, no fall. **Ending on any other ramp tumbles too**, down the slope's OWN
  downhill — after paying the drop, and possibly bending the shove's path once, which is why
  `ResolvedOutcome.knockback_path` now carries the full trail the preview draws.
- One visible consequence of airborne, worth knowing when authoring: a knockback-1 shove onto a
  descending ramp tumbles free, while a longer shove **flies over** the same ramp and pays fall
  damage where it comes down. Both canon examples below still reproduce verbatim (pinned in
  `tests/law/test_falls.gd`).

**The shove is ANIMATED and the trail is HONEST (review rework, 2026-08-20, two rounds):** the
target slides the resolver's own `knockback_path` (`MovementComponent.slide_along_path`, facing
held — being moved is not moving), and in 3D its height rides `knockback_landing_index`, the
resolver's flight/tumble split: launch height while airborne, then **slaved to the surface under
the sprite** (`BoardSpace.surface_height_at`, the ramp-aware plane — a tumble STICKS to the
slope; an eased height cannot track a many-cells-per-second slide and floats, measured). The
preview trail obeys the same split — flown cells draw in the air at launch height, and every break
in the trail's own surface hangs a **drop pointer** ("in the air until he would drop, then point
straight down" — dev), the rule for which is
[#431](https://github.com/Phaazoid/Godoiosis/issues/431)'s and is stated in full below. A VOID cell
renders as **no column at all** in 3D: the pit is the absence of the block.

**The fall is a BEAT of the slide, and it happens where the pointer hangs
([#472](https://github.com/Phaazoid/Godoiosis/issues/472), 2026-08-22).** A segment whose entry
edge breaks is travelled in two halves with the drop between them — fly sideways, turn ninety
degrees, fall, carry on — so the playback takes exactly the fall its own trail draws. **The trigger
is #431's rule and nothing else**: `BoardSpace.surface_height_at_edge` is the one spelling of "how
high is this cell's surface at the edge it meets its neighbour on", and both `_append_drop` and
`MovementComponent._edge_drop` read it. Asked per EDGE rather than per landing, which is what lets
a cliff-then-tumble-then-lip shove fall at **both** breaks; a landing-shaped answer could express
only the first, which is the same reason #431 deleted its flag.

This REPLACES the flat-landing-only promise this paragraph used to carry ("a flat landing keeps
fly-then-fall via the post-slide ease"), and the ease with it. It was never true of a RAMP landing:
the mirror began ground contact on any ramp landing, on the theory that a ramp's high shoulder
meets the flight level — which holds only at a drop of exactly 1 down a matching slope, the one
case `_knockback_landing` zeroes. Every other ramp landing snapped by the difference, in one frame,
halfway through the final flight segment; through the pitched camera that reads as the unit
skipping forward along its travel, which is how it was reported. Two of the dev's own boards
isolated it and are reproduced as `tests/presentation/test_shove_fall.gd`. Rate is
`MovementComponent.SHOVE_FALL_SPEED`, in cells per second, on the Game tab beside the slide speed.

### The drop pointer [#431, 2026-08-21 — SUPERSEDES the "a fall onto a RAMP draws no pointer" line this section used to carry]

**A trail cell drops when the two surfaces meeting at the EDGE it was entered by are not at the
same height.** That is the whole rule, and nothing else is asked — no "did this shove fall" flag.
The heights the trail is already drawn at answer it, and `BoardSpace.surface_height_at` carries
what makes it work: a ramp's plane meets its neighbour's exactly at the shared edge, so a slide
reads continuous and draws nothing with no ramp case anywhere. The flag it replaced was a second
seam for a fact the geometry held (Law #4), and it went stale the moment the tumble learned to
plummet — stamped on the ONE cell a flight ended on, it could not express a second drop at all.

Consequences the flag version got wrong and this one gets right for free: a fall onto a ramp DOES
draw (reversing the older ruling — the unit fell, and that is the vertical story), a pure slide
onto one does not, and a cliff-then-slide-then-plummet draws at **both** breaks.

The geometry, all of it dev-ruled in play across four rounds:

- It starts falling **at the edge**, never further into the tile. The flat arrow it lands on begins
  at the back of its tile, so a fold placed anywhere inward leaves that much shaft sticking out
  behind the foot — worse on a slope, where the tile's centre is half a level under its top edge.
- Both ends join the plane the neighbouring arrow is **DRAWN** in, not the surface under it — the
  sink lifts every marker clear of the ground, and joining the surface instead put a seam on every
  ramp landing. `OverlayMirror._ribbon_point` is that one question. Since
  [#432](https://github.com/Phaazoid/Godoiosis/issues/432) the layer lift is a **constant, straight
  up**, so the drawn plane is the surface plus it on a slope exactly as on the flat and
  `_ribbon_point` is a plain surface read again. Until then it rode the surface *normal*, and a
  ramp's normal leans, so the slope's arrow was displaced downhill out of its own cell and anything
  joining it had to ask where it had been drawn rather than where the ground was.
- **The pointer takes no layer lift at all** (`lift_dir` ZERO): its ends are already the
  neighbouring arrows' own drawn points, so lifting it again would double the clearance and float
  it off the join it exists to make. Lifting it along its own normal — which for a vertical quad is
  sideways — broke that join twice, and then needed `no_depth_test` to survive the z-fight that
  left, which turned the pointer into an x-ray visible through platforms the camera had panned
  behind. Standing clear of the cliff face is a separate, far smaller epsilon (`WALL_CLEARANCE`).
- **One quad, never a cross.** The rig's pitch is fixed at 40°, so a vertical quad across the trail
  never goes edge-on — its width bottoms out at 64% and no camera-facing pick is needed.

**A void removal drops the full plummet.** `MovementComponent.VOID_PLUMMET_CELLS` is one distance
with two readers — the pointer's length and the fall the sprite actually takes — because a preview
promising a shorter drop than playback shows is a Law #2 divergence. The fall itself is
`MovementComponent.plummet()`, awaited by `AttackAction.execute` before `die()`, so a unit shoved
into a hole falls a long way instead of vanishing at the lip. It is 3D-ONLY by construction (the
flat board has no height to fall through), a declared [#292](https://github.com/Phaazoid/Godoiosis/issues/292)
asymmetry, and `play_session`'s hand-copied twin deliberately skips it. Both the depth and the
duration are Game-tab knobs beside *Shove slide speed*.

**A void removal is the KILLED rung plus `ResolvedOutcome.removed`.** KILLED so every reader lights
up unchanged — the AI counts it a removal, the queue shows KILL, `lifecycle_for` threads DEAD; the
flag exists because execution needs its own door (a 0-damage `take_damage` cannot kill an ACTIVE
unit), so **both** executors — `AttackAction.execute` and `play_session._apply_attack`, the
hand-mirrored twins — call `Unit.die()` on it. A removed target publishes no projected knockback
and draws no landing ghost: its sprite stands where it is, the trail alone says where it goes, and
nothing on a chasm cell is pickable. `Terrain.Kind.VOID` (append-only) is the authored vocabulary;
the two `hole` tiles carry it, and the headless no-tile sentinel renamed to `"offmap"` to free the
word. Counter shoves are previewed too since this slice (`_preview_plan_effects` walks
`plan.counters` — a gap, closed).

### Shoves — the original rulings (all intact under the airborne model)

- **You cannot be pushed uphill.** A shove that would climb stops dead. High ground braces you.
- **Only vertical drops give fall damage.** Slopes never do.
- **A shove onto a descending ramp becomes a TUMBLE.**

### The tumble rule [the "no fall damage" clause was REVERSED at build — see consequence 2 below]

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
2. ~~**The tumble stops at a lip, it does not launch you off it.**~~ **REVERSED at build
   (2026-08-20): the tumble PLUMMETS past a lip.** The original ruling was deliberately conservative
   — keep fall damage to shoves that push a unit *directly* over a vertical edge, so the two
   mechanics never compound into a two-stage prediction on day one, and add tumble-then-plummet
   later once the base case had been felt. It was felt, and the addition landed in the same arc.
   A downhill step below the ramp's base now accumulates `fall_levels`, steps into the lower cell,
   and **keeps whatever descent waits below** (another ramp tumbles again, a flat cell catches it) —
   dev: *"continue whatever descent awaits them."* One shove can therefore break its surface more
   than once, which is what the drop pointer's per-edge rule above exists to draw. Pinned by
   `test_the_tumble_plummets_past_a_lip` and `test_a_plummet_landing_on_a_ramp_tumbles_again`.

Structurally it landed close to the prediction: the knockback stage still publishes
`knockback_from`/`knockback_to` and threads the hypo — but the landing had to be computed BEFORE
the lethality rung is named (fall damage can change it), so `_resolve_knockback` split into a pure
`_knockback_landing` called off a *provisional* rung (a hit that alone kills still shoves nothing)
with the *final* `predict` feeding the Will-spend stage; and the trail gained
`knockback_path`, since a landing tumble can bend a shove once.

The declared placeholder that used to live at that call site — a shove asks the CELL-level
`is_walkable`, never the per-unit `can_traverse`, so a Waterwalker is not shoved onto water — is
**REPEALED as of [#116](https://github.com/Phaazoid/Godoiosis/issues/116) (2026-08-26)**. It was
correct while water STOPPED a shove: bracing a Waterwalker against water braced everyone. Water
SWALLOWS now, and the cell-level question would drown a unit that walks on water — so the shove asks
`RulesService.drowns_in` and `can_traverse`, both per-unit, and a Waterwalker is shoved *onto* the
water and stands there. #259 resolved the cliff (fall damage) and the void (removal) at that stop;
#116 resolved the water, and `tests/law/test_falls.gd` pins all three.

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
   **BUILT as [#258](https://github.com/Phaazoid/Godoiosis/issues/258) (2026-08-20), reworked in
   review the same day** — see *Targeting* above (the STEP melee rule, lob-vs-gun, the directional
   exemption) and *Line of sight* (the sight trace, pulled forward from the deferred list).
3. **Falls.** Drop damage, void removal, the tumble, the no-push-uphill rule. Closes the
   #116 / #120 interlock.
   **BUILT as [#259](https://github.com/Phaazoid/Godoiosis/issues/259) (2026-08-20)** with the
   AIRBORNE revision — see *Falls, shoves and tumbles* above, and the tumble-then-plummet reversal
   plus [#431](https://github.com/Phaazoid/Godoiosis/issues/431)'s drop pointer that followed it.
   The interlock closed as far as it can before content: the fall-damage **weight term is wired**
   (`FallRules`) and inert at weight 0; #120's distance bands + the weight-authoring pass stay on
   #120 — and **#116's water fork CLOSED 2026-08-26** (terrain.md → *Water — shallow vs deep*), so
   the interlock is complete.

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

**Built (#258) as a per-cell TILE, not a colour** — the `TARGET_ATLAS_COORDS` precedent for
per-cell states on this layer: blocked cells wear a hatched fill (`BLOCKED_ATLAS_COORDS`, a third
tile on `Basic_Tile_Overlay.png`) under the SAME layer modulate, so the heal-green fork follows for
free. In 3D there is no per-cell art, so `OverlayMirror` routes those coords to their own
`Layer.ATTACK_BLOCKED` fill whose colour is DERIVED — the live reach modulate dimmed by
`OverlayManager.BLOCKED_REACH_DIM` (a GameKnobs row) — a declared #292 asymmetry: same information,
per-stack idiom. `OverlayManager.show_attack_reach(union, blocked)` is the one draw door.

---

## Dev tools [BUILT as #260]

> **The brush grew a STEEPNESS door in #427 slice 2 (2026-08-23), and its height step opened.** The
> Height spinbox steps by **1 unit** now rather than a whole level, so a half-level platform is
> authorable — slice 1 had deliberately held it at `UNITS_PER_LEVEL` because nothing could draw one.
> The WHEEL matches it -- one UNIT per notch. It moved a whole LEVEL for a few hours, which made a
> two-cell gentle slope unbuildable by the only gesture that changes height mid-stroke: "I have no
> way to connect more than one half slope together." Ctrl+wheel still hands the notch to the camera,
> and always did -- what made zooming feel broken was the camera's own floor, below.
>
> Steepness is a **separate control from direction** (dev call, 2026-08-23), against folding both
> into one nine-entry dropdown: a Rise Amount picker (Full 45° / Half 26.6°) beside the compass, and
> **X** cycles it — between Z and C, so turn-left / change-pitch / turn-right read as one gesture. It
> greys with the direction on a tile that stands up, for the same reason. The amount deliberately
> survives *Reset to flat*: it is a steepness preference, not a piece of the shape.

> **THE RE-METRIC BROKE EVERY BOX THAT DRAWS A CELL VOLUME (dev, 2026-08-23, with screenshots).**
> *"when I hover a block currently, my voxel selector hovers a half height too high ... hovering above
> a block, and not going to the floor."* **The hover selector** (`BoardOverlays`, `Kind.BRACKET`) is
> the one he reported. Its mesh was a **cube** — `half = 0.5 * CELL_SIZE * bracket_scale` on all three
> axes — centred on `cell_center`, which said the right thing only while a mirror cell *was* a cube.
> A level-tall box centred on a half-level row hangs a **quarter of a level** high at both ends. Now:
> X and Z span a cell, **Y spans however many ROWS the selector is set to**, and the box's **top face
> sits on the cell's surface** with its depth reaching down from there.
>
> A **Selector depth** picker (Level / Half) on the Game tab plus **V** say how far down. It is a
> `GameKnobs` row rather than a Tile Brush one because the selector is up in **ordinary play**, and V
> is a top-level dev key for the same reason — needing an armed brush would leave the thing visible
> and the key that moves it dead. Turning the knob **rebuilds what is already standing**: the hover
> layer only repaints when the pointer *cell* changes, so a still mouse would otherwise see nothing.
>
> **The brush GHOST had the same disease** — one block mesh is one row, so it previewed the top half
> of the slab a paint makes. Fixed the same way and deliberately **without** a knob: how deep a
> preview draws is the slab the paint makes, and a WYSIWYG preview with a setting is one that can be
> wrong on purpose. One question, one knob, and it belongs to the selector.
>
> Both boxes are **scaled/sized, never stacked**: each wears a flat translucent material, so two
> boxes meeting would show their shared faces as a bright band across the middle.

> **A DEV PAGE OWNS ITS OWN INPUT (dev, 2026-08-23).** *"I should only be able to spawn units while
> the unit spawning window is up, yet when I press space in the brush mode, it spawns a unit."*
> `DevOverlay.showing(page)` is the one answer to which page is up — it has to be a function rather
> than a comparison, because Spawn and Character Editor share the Unit Authoring container, so
> either is showing only when that container is the current top-level tab AND the current authoring
> one. Four hand-rolled spellings collapsed onto it.
>
> `DevController` then combines it with the game state, once per key: `brush_armed()` and its new
> sibling `spawn_armed()`. **Both halves are load-bearing** — Spawn is the overlay's BOOT page, so
> the page test alone made SPACE try to spawn during ordinary play. Both SPACE handlers (game.gd's
> flat arm and battle3d's) and the 3D help line read the one predicate, which is what stops the
> readout promising a key the gate refuses.
>
> The zoom-in floor came down with it (`CameraRig3D.min_distance` 6.0 → 1.0, and its Game-tab knob
> now reaches 0.25): *"it really makes it hard to zoom in and see what I'm trying to brush paint."*


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
Godot emits a press *and* a release per notch. Five rulings worth keeping:

- **Negative levels are reachable, deliberately.** The dev: *"if I start designing a level and want a
  dip, without allowing negatives, I would have to shift everything up. no bueno."* Nothing in
  `can_step` cares — its only arithmetic is equality and ±1, which is symmetric about zero. The 3D
  PICKER did care, until [#294](https://github.com/Phaazoid/Godoiosis/issues/294): a column one
  deep tops out at level `0`, which was also its "there is no column here" answer, so a dip read as
  flat inside the authoring apron and was unclickable outside it. `BoardPicker.NO_COLUMN` separates
  the two — **a level is a number, not a truth value**, and nothing may gate on `level > 0`.
  [#582](https://github.com/Phaazoid/Godoiosis/issues/582) is the other half: #294 made a dip
  **representable**, and it was still not **reachable**. The apron's implicit floor sits at
  `FLAT_TOP_ROW`, and it used to end the walk like any real hit — so an *invisible* surface occluded
  a block that is plainly drawn, and a cell painted more than a level down became unpaintable,
  unerasable and unselectable at once, every dev gesture reading the one pick. **The plane is a
  floor, not a lid:** a plane hit is HELD, the walk goes on, the first real column below floor level
  wins, and the first real column at or above it blocks with the held hit standing — which is what
  keeps [#231](https://github.com/Phaazoid/Godoiosis/issues/231)'s erased cell answering for itself.
- **What the camera cannot see, the brush aims at instead.** The second half of #582, and a separate
  problem wearing the same symptom: a **one-cell** well two units deep is hidden by its own
  neighbours, honestly, at the rig's fixed 40° pitch — measured, it needs 56° to see the floor, and
  no picking rule recovers what is not on screen. Anything **two cells across is visible on its own
  at any depth** (3×3 and 5×5 measured, every cell), so the gap is exactly the one-wide well. The
  Tile Brush's **Aim at brush height** toggle answers it by changing the QUESTION: while it is on the
  pick resolves against the brush's own Height plane (`BoardPicker.pick_on_plane`) rather than the
  board, so nothing can occlude it. Off by default, because it trades away reaching a tall column to
  erase it — the commoner gesture by far. It is #340's ruling one layer down: the ghost already shows
  the tile at the height you picked rather than the height the cell happens to be.
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

> **#427 slice 3 pays the same cost again, by dev call.** Every flat tile now gets its own **outer**
> and **inner** corner caps at both climbs on top of its wedges: **2119 items, 4.8 MB**, and a longer
> re-import every time. He was offered generic (non-per-tile) caps for this slice — corners were only
> hand-authorable while slice 4 was still owed, so almost nothing would have seen the wrong art — and
> chose to pay now, so #340's rule holds with no exception. Slice 4 is what collected on that: the
> corner tool authors real corner cells on painted ground, wearing their own tile from the first
> stroke. Three SHAPES and not twelve masks: the GridMap's own
> yaw supplies each shape's four rotations, which is what keeps eight new forms at two new meshes.
> `BoardMirror._form_orientation` derives that yaw from the ground's own uphill
> (`Terrain.gradient_of_corners`) rather than a twelve-entry table, so the mesh and the rules cannot
> drift about which way a cell climbs.

- **Only GROUND may SLOPE — but every tile gets a variant (amended by
  [#342](https://github.com/Phaazoid/Godoiosis/issues/342), 2026-08-25/26).** The dev's rule is about
  authoring: *"only tiles that are flat, not things like rocks, lanterns, etc. grass, mud, etc."*
  The gate is `GridUtils.is_ground_shape` — a `prop_shape` derivation, not a stored flag — and it
  lives in `TileBrushTool.selected_rise()` so the GHOST reads it too; gated at the paint site
  instead, the preview would show a sloping rock the click then refuses. It read `stands_up_of` until
  #342 round 2; see *"is this GROUND?" is not the inverse of "does this STAND UP?"* below.

  **The meshlib generator used to share that gate, and that was the bug.** What a cap draws is not
  the tile's ART, it is the GROUND the tile stands on — which the generator's atlas pass has already
  composed for every tile: its own art if flat, the bare kind base for a prop, a generated speckle
  for a tuft. Gating cap emission on `stands_up` was therefore a **second answer to a question that
  pass already answers**, and it degraded exactly where the brush's rule does not reach: the corner
  tool gates on GROUND, not on `stands_up`, so any cell can be given corners, and a prop can be
  painted onto a cell that already slopes. Every such slope wore the generic `dirt_ramp*`, whose top
  face is the generated `grass_top` — measured off the dev's own screenshot at `rgb(129,185,108)`
  beside `rgb(62,226,169)` on the flat ground next to it, and **no tile in the sheet is that olive**.
  So the rule is now: *a 1x1 tile with a block has a cap for every climb and every shape, wearing the
  same face its block wears* (2089 → 2173 items). `tests/law/test_every_tile_can_wear_a_slope.gd`.
- **`dirt_ramp` stays as the fallback, not as dead scaffolding.** Three of the cases `item_for_tile`
  documents still reach it — an empty cell, a rotated alternative, and **multi-cell art**, whose
  tiles the generator skips outright and which therefore have no block either. A standing prop no
  longer does. Without the fallback those cells render as a hole.
- **A TUFT slopes, and its plants are planted per PLANT (#342).** The question this entry used to
  defer (*"should a tuft slope at all?"*) was answered by #427 slice 4 shipping: the corner tool
  slopes one whenever a neighbouring vertex is dragged, because it gates on GROUND. A tuft is the one
  prop whose parts are SPREAD ACROSS the square, so one surface point for the whole assembly is only
  right while the square is level; each cluster now reads `BoardSpace.surface_height_at` at **its
  own** point. It stays upright rather than tilting with the ground — these are Y-billboards, and a
  plant grows up whatever the hill does, which is why `surface_transform` (the answer this entry
  predicted) is the wrong seam for it.
- **"Is this GROUND?" is not the inverse of "does this STAND UP?" — #342 round 2 closed the brush's
  half on that.** `GridUtils.stands_up_of` asks whether a tile stands ON the ground, which is right
  for rendering: a tuft's plants really are billboards. The tile brush's rise gate borrowed it as a
  proxy for *may this tile be shaped like terrain*, and the two agreed **only until TUFT existed**,
  which answers yes to both. So a flowery-grass tile could be sloped by the corner tool and refused
  by the brush — one board, two answers. `GridUtils.GROUND_SHAPES` / `is_ground_shape` is the second
  question named once (`FLAT`, `TUFT`), and `TileBrushTool.selected_tile_is_ground` is its one
  caller; rocks, fences and lanterns still paint flat however the picker is set. The brush stays the
  CONSERVATIVE tool on purpose — the corner tool gates only on `has_ground`, so it will slope a rock,
  and *"different tools for different situations"* is the standing ruling that keeps them apart.
- **A prop follows its ground.** `BoardMirror._reconcile_prop` early-outs on identity, and until #342
  that identity was the TILE alone — so moving the ground under any prop left it sown at the old
  height. That is #471's law (*a poll compares every input its answer depends on*) one store along:
  every prop stands at `surface_point`, and a tuft's plants read the corners directly. It compares
  the cell's corners too now, and REBUILDS rather than re-placing, because a tuft has no single
  position to move. Reachable before the corner tool as well, by repainting the same tile at a new
  height; the tile brush writing tile and height together is what hid it.

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
  off the real grid via the same `item_for_cell` call the board uses. *Since #427 slice 2 a "block"
  is one ROW, so the flat preview spans a LEVEL — the slab a paint makes — reaching DOWN from the
  surface the click authors. Not a setting; the hover selector owns the only depth knob. It is
  SCALED rather than stacked: the ghost wears a flat translucent `material_override`, so two boxes
  meeting would show their shared faces as a bright band across the middle of the selector.*
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

- ~~**LoS evaluation**~~ — **no longer deferred**: built 2026-08-20 as the sight trace (see *The
  drawn path IS the rule* above), after the first real board broke the map-authoring mitigation.
- **Height → damage.** The dev wants it eventually — *"there might be cases where it can affect damage
  as well, but we can shelve that for a later grill session."* `elevation_delta` is the wire it will
  attach to. Likeliest first case: a heavy melee weapon swung downhill, since falling damage already
  establishes height-as-force in the fiction.
- **3D blast extent.** *"A fire ball can be lobbed, and create a 3D explosion radius where it lands."*
  Explicitly **not** part of this arc — recorded as a supported direction. On a heightmap it needs no
  volume math: it is one more authored number, "the blast covers cells whose surface is within V of
  the impact point," so a fireball on a terrace does not catch the men on the plateau above.
- **A projectile graphic riding the sight line** — dev, 2026-08-20: *"we can add a little graphic
  of a fire following it when it goes off, for when the advanced battle zoom is disabled"*. The
  trajectory function is already the one home the flight path would read.
- **Terrain interlocks** — water flowing downhill, fire climbing, fog settling in low ground. A rich
  vein and a separate project; see [terrain.md](terrain.md).
- ~~**30° two-tile slopes**~~ — **SUPERSEDED by [#427](https://github.com/Phaazoid/Godoiosis/issues/427)
  (2026-08-23), and deliberately not built as described.** The gentler slope arrives as a HALF-level
  rise over ONE cell — `atan(1/2)` ≈ 26.6°, the actual RollerCoaster Tycoon angle — never as one
  level spread over two cells, so no multi-cell coupling enters the ramp vocabulary and every cell
  stays self-contained. Slice 1 re-based the unit that makes it expressible; **slice 2 BUILT the
  form** (2026-08-23). Everything else here still assumes 45°, which is now 2 units per cell.
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
