extends Object
class_name BoardSpace

# The 3D presentation stack's ONE coordinate convention (#205 / #176 stage 1):
# board cell <-> world position. Every unit placement, overlay quad, highlight and
# picker resolves through here — nothing else does this arithmetic (the GridMap's
# authored cell_size must agree; pinned by test). Presentation-side only: the rules
# layer keeps its own 2D vocabulary (GridUtils), and bridging the two is stage 2+.
#
# A cell Vector3i(x, y, z) occupies [x..x+1] x [y..y+1] x [z..z+1] * CELL_SIZE.
# Boundary rule: a position exactly on a face floors UPWARD (cell_of is a volume
# query for interior points; round-trip through cell_center, not standing_point).

const CELL_SIZE := 1.0

# "No cell" sentinel — far outside any real board (GridUtils.NO_CELL's 3D twin).
const NO_CELL := Vector3i(-999, -999, -999)


# Center of the cell's volume. Agrees with GridMap.map_to_local at cell_size (1,1,1).
static func cell_center(cell: Vector3i) -> Vector3:
	return Vector3(cell.x + 0.5, cell.y + 0.5, cell.z + 0.5) * CELL_SIZE


# Center of the cell's TOP face: where a unit stands, an overlay lies, a highlight sits.
static func standing_point(cell: Vector3i) -> Vector3:
	return Vector3((cell.x + 0.5) * CELL_SIZE, surface_y(cell.y), (cell.z + 0.5) * CELL_SIZE)


# The world Y of a surface at `level` — the top face of that level's block, since a level-E block
# occupies [E .. E+1]. The ONE spelling of it (#273): the live board's unit placement
# (UnitMirror) and the walk demo's injected stand_at both read this, so the mirrored board and
# the demo cannot drift about where the ground is.
static func surface_y(level: int) -> float:
	return float(level + 1) * CELL_SIZE


# Where a thing STANDING on this 2D cell sits — a unit, a flame, a crate (#273). ONE answer for
# every such caller, because three of them eyeballing the same offset is how a flame ends up half a
# level off the crate on its own tile. It lives here rather than on either mirror so neither has to
# reach for the other.
#
# A ramp's surface SLOPES, and verticality.md rules its visual midpoint purely presentational — so
# anything on one rides half a level up rather than sinking into the low edge the RULES call its
# level. That is the one place presentation and rules deliberately disagree, and it is why
# UnitSprite3D.stand_at was made injectable in the first place.
static func surface_point(cell: Vector2i, heights: BoardHeights) -> Vector3:
	return surface_transform(cell, heights).origin


# The surface's height directly UNDER a world position (#259 rework round 2): surface_transform's
# own plane evaluated at (x, z), so a sliding sprite can stick to a ramp continuously instead of
# stepping per cell or floating over it. Flat cells are constant; a ramp's plane meets the next
# ramp's (and the level catch's surface) exactly at the shared edge, which is what makes a tumble
# read as one slide. Same tan as RAMP_SLOPE_ANGLE: one level of rise per cell of run.
static func surface_height_at(cell: Vector2i, x: float, z: float, heights: BoardHeights) -> float:
	var t := surface_transform(cell, heights)
	var rise := Terrain.RampRise.NONE if heights == null else heights.ramp_rise_at(cell)
	if rise == Terrain.RampRise.NONE:
		return t.origin.y
	var dir := Terrain.rise_direction(rise)
	return t.origin.y + tan(RAMP_SLOPE_ANGLE) * ((x - t.origin.x) * dir.x + (z - t.origin.z) * dir.y)


# The surface height of `cell` AT the edge it meets its `dir` neighbour on (#472). One edge is
# named from either side -- surface_height_at_edge(a, d) and surface_height_at_edge(a + d, -d) are
# the same seam -- which is what lets "do these two surfaces MEET here?" be one question with one
# answer. Both the drop pointer (OverlayMirror._append_drop) and the shove's own fall
# (MovementComponent._edge_drop) ask it, and they must agree: the trail promises a drop exactly
# where this says there is one, so a second spelling is a preview drawing a fall the sprite never
# takes.
#
# Read AT the edge, never at the centre: a slide onto a ramp's high shoulder enters level with the
# flight and only THEN descends, so measuring the centre would call every such slide half a level
# of fall.
static func surface_height_at_edge(cell: Vector2i, dir: Vector2i, heights: BoardHeights) -> float:
	var x := (float(cell.x) + 0.5 + float(dir.x) * 0.5) * CELL_SIZE
	var z := (float(cell.y) + 0.5 + float(dir.y) * 0.5) * CELL_SIZE
	return surface_height_at(cell, x, z, heights)


# One level of rise per cell of run — the authored wedge's own profile (its slope face runs corner
# to corner, normal (0,1,1)), and the same ratio surface_point's half-level lift already encodes.
const RAMP_SLOPE_ANGLE := atan2(CELL_SIZE, CELL_SIZE)

# A slope is LONGER than the cell it spans (1/cos of the angle), so markup that only rotated would
# cover the cell's footprint and leave the ramp face bare at both edges. Stretching along the slope
# is what keeps a fill covering its whole cell and an arrow foreshortening exactly as the ground
# under it does.
const SLOPE_STRETCH := 1.0 / cos(RAMP_SLOPE_ANGLE)


# How a FLAT thing LIES on this cell's surface (#281) — a path arrow, an overlay fill, any markup
# that is part of the ground rather than standing on it. The origin half is surface_point's, so the
# two cannot drift; the basis half is what makes markup follow a slope instead of hanging level
# through it. Anything that STANDS stays upright and keeps reading surface_point (units, flames,
# props).
static func surface_transform(cell: Vector2i, heights: BoardHeights) -> Transform3D:
	if heights == null:
		return lie_on(of_cell(cell, 0), Terrain.RampRise.NONE)
	return lie_on(of_cell(cell, heights.elevation_at(cell)), heights.ramp_rise_at(cell))


# The lie itself, for a caller that already resolved the level — the overlay fills, whose Vector3i
# states it (of_cell's "every caller states the LEVEL it means" rule, #273; re-deriving it here
# would look up what was already passed).
#
# The tilt is DERIVED from Terrain.rise_direction — the same call BoardMirror._ramp_orientation
# yaws the wedge by — so the ground and the markup on it cannot disagree about which way it climbs.
static func lie_on(cell: Vector3i, rise: Terrain.RampRise) -> Transform3D:
	var origin := standing_point(cell)
	if rise == Terrain.RampRise.NONE:
		return Transform3D(Basis.IDENTITY, origin)
	# The midpoint of the slope, which is exactly where a quad tilted about its own centre lies flat.
	origin.y += CELL_SIZE * 0.5
	var dir := Terrain.rise_direction(rise)
	var uphill := Vector3(dir.x, 0.0, dir.y)
	var basis := Basis(uphill.cross(Vector3.UP).normalized(), RAMP_SLOPE_ANGLE)
	# Stretch the ONE local axis that ends up running up the slope, so the art keeps its orientation
	# (a rotated arrow would point somewhere else) and only its length along the slope changes.
	if dir.x != 0:
		basis.x *= SLOPE_STRETCH
	else:
		basis.z *= SLOPE_STRETCH
	return Transform3D(basis, origin)


# The cell containing a world position (floor per axis — see the boundary rule above).
static func cell_of(position: Vector3) -> Vector3i:
	return Vector3i(
		floori(position.x / CELL_SIZE),
		floori(position.y / CELL_SIZE),
		floori(position.z / CELL_SIZE)
	)


# The TOP of a GROUND-LEVEL column, in cells — what BoardPicker's fallback plane sits on over an
# erased cell (#231), since y=0 is the slab's BOTTOM and a plane there returns the wrong cell at
# grazing angles. Elevation (#273) did NOT retire this: an unpainted column is still exactly one
# cell tall, so this is the top of level 0 and nothing more. It equals surface_y(0), and
# test_board_space pins the two spellings together.
const FLAT_TOP_LEVEL := 1

# The sim<->mirror cell pair (#222): sim cells are 2D (x, y), mirror cells are (x, level, y).
# The ONE spelling of it. flat(NO_CELL) equals GridUtils.NO_CELL by value — pinned, the pointer
# source relies on it.
static func flat(cell: Vector3i) -> Vector2i:
	return Vector2i(cell.x, cell.z)


# Every caller states the LEVEL it means (#273 — this took no argument and hardcoded 0 while the
# sim had no elevation). Passing beats looking up, and a required argument is what makes the old
# flat assumption unrepresentable rather than merely discouraged.
static func of_cell(cell: Vector2i, level: int) -> Vector3i:
	return Vector3i(cell.x, level, cell.y)


# A 2D-game world POSITION (pixels) as a 3D position at height `y`. The one spelling of
# the ÷16 metric that maps the flat game onto the diorama — grid.map_to_local's pixel
# size, which is what UnitMirror's sprite placement is pinned against. NB the 2D
# camera's CELL_WORLD (32) is a zoom constant, not this, and mixing them was falsified
# earlier in the arc.
static func of_pixels(px: Vector2, y: float) -> Vector3:
	var per_cell := float(GridUtils.TILE_SIZE)
	return Vector3(px.x / per_cell, y, px.y / per_cell)
