extends Object
class_name BoardSpace

# The 3D presentation stack's ONE coordinate convention (#205 / #176 stage 1):
# board cell <-> world position. Every unit placement, overlay quad, highlight and
# picker resolves through here — nothing else does this arithmetic (the GridMap's
# authored cell_size must agree; pinned by test). Presentation-side only: the rules
# layer keeps its own 2D vocabulary (GridUtils), and bridging the two is stage 2+.
#
# A mirror cell Vector3i(x, y, z) occupies [x..x+1] x [z..z+1] * CELL_SIZE horizontally and
# [y..y+1] * ROW_HEIGHT vertically. NOT a cube since #427 slice 2 — the vertical index is a ROW of
# one HEIGHT UNIT (half a level), because the store measures in half levels and geometry that only
# exists at whole levels cannot draw one. A ground slab is still one LEVEL deep, i.e.
# UNITS_PER_LEVEL rows, which is what keeps every world position exactly where it was.
# Boundary rule: a position exactly on a face floors UPWARD (cell_of is a volume
# query for interior points; round-trip through cell_center, not standing_point).

const CELL_SIZE := 1.0

# One row of the vertical index, in world units. The whole re-metric is this constant: a 45 degree
# ramp still rises CELL_SIZE over CELL_SIZE of run, it now just spans UNITS_PER_LEVEL rows to do it.
const ROW_HEIGHT := CELL_SIZE / Terrain.UNITS_PER_LEVEL

# "No cell" sentinel — far outside any real board (GridUtils.NO_CELL's 3D twin).
const NO_CELL := Vector3i(-999, -999, -999)


# Center of the cell's volume. Agrees with GridMap.map_to_local at the authored cell_size.
static func cell_center(cell: Vector3i) -> Vector3:
	return Vector3((cell.x + 0.5) * CELL_SIZE, (cell.y + 0.5) * ROW_HEIGHT, (cell.z + 0.5) * CELL_SIZE)


# Center of the cell's TOP face: where a unit stands, an overlay lies, a highlight sits.
static func standing_point(cell: Vector3i) -> Vector3:
	return Vector3((cell.x + 0.5) * CELL_SIZE, surface_y(cell.y), (cell.z + 0.5) * CELL_SIZE)


# The world Y of a surface at `row` — the top face of that row's block, since a row-R block
# occupies [R .. R+1] * ROW_HEIGHT. The ONE spelling of it (#273): the live board's unit placement
# (UnitMirror) and the walk demo's injected stand_at both read this, so the mirrored board and
# the demo cannot drift about where the ground is.
static func surface_y(row: int) -> float:
	return float(row + 1) * ROW_HEIGHT


# The row a cell of this rule HEIGHT tops out at (#427 slice 2) — the one conversion between the
# store's unit and the mirror's vertical index, and the successor to Terrain.level_of at every site
# that used to place geometry. A ground slab is one LEVEL deep, so a height-H surface is the top of
# row H + UNITS_PER_LEVEL - 1; with a slab of exactly one row that reduces to H, which is what the
# whole-level version silently assumed.
static func top_row_of(height: int) -> int:
	return height + Terrain.UNITS_PER_LEVEL - 1


# The world Y a surface at this rule HEIGHT sits at, for a height that need not be a whole unit
# (#427 slice 3 -- a corner cell's surface passes through every value between its corners). It IS
# surface_y(top_row_of(h)) rearranged, and test_board_space pins the two spellings together: a slab
# is one LEVEL deep and tops out at top_row_of(h), so its surface is h + UNITS_PER_LEVEL rows up.
static func world_y_of_height(height: float) -> float:
	return (height + float(Terrain.UNITS_PER_LEVEL)) * ROW_HEIGHT


# Where a grid VERTEX sits in the world (#427 slice 4): the point four cells share, at a rule height.
# cell_center's twin for a POINT rather than a volume, and the difference IS the half-cell offset --
# a vertex takes none, because it is the cell's CORNER. That is the one thing easy to get wrong here
# and the reason it is spelled once rather than at the marker that draws it.
static func vertex_point(vertex: Vector2i, height: float) -> Vector3:
	return Vector3(vertex.x * CELL_SIZE, world_y_of_height(height), vertex.y * CELL_SIZE)


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
# read as one slide. The gradient is the ramp's OWN climb since #427 slice 2, so a gentle slope
# slides at half the pitch of a 45 degree one rather than at the one hardcoded angle.
static func surface_height_at(cell: Vector2i, x: float, z: float, heights: BoardHeights) -> float:
	if heights == null:
		return world_y_of_height(0.0)
	# The point's place INSIDE the cell: u east across it, v south down it, both 0..1 -- the frame
	# Terrain.height_at_uv answers in. Clamped because a caller may be a hair outside its own cell
	# (a sprite mid-slide is placed by the tween, not by the grid), and extrapolating a triangle
	# past its own edge is how a foot ends up under the ground it is standing on.
	var u := clampf(x / CELL_SIZE - float(cell.x), 0.0, 1.0)
	var v := clampf(z / CELL_SIZE - float(cell.y), 0.0, 1.0)
	return world_y_of_height(Terrain.height_at_uv(heights.corners_at(cell), u, v))


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


# The three per-CLIMB slope helpers (slope_gradient / slope_angle / slope_stretch) went with #427
# slice 3. Steepness is no longer one number per cell: a corner form's downhill is diagonal, so the
# angle and the stretch are derived from the four corners inside lie_on, and nothing outside ever
# asked for them.


# How a FLAT thing LIES on this cell's surface (#281) — a path arrow, an overlay fill, any markup
# that is part of the ground rather than standing on it. The origin half is surface_point's, so the
# two cannot drift; the basis half is what makes markup follow a slope instead of hanging level
# through it. Anything that STANDS stays upright and keeps reading surface_point (units, flames,
# props).
#
# The one place a stored HEIGHT becomes a drawn ROW (#427): the store measures in half-level units
# and the mirror's vertical index is one row per unit, so top_row_of is the conversion the whole 3D
# stack inherits through this function.
static func surface_transform(cell: Vector2i, heights: BoardHeights) -> Transform3D:
	var corners := Vector4i.ZERO if heights == null else heights.corners_at(cell)
	return lie_on(of_cell(cell, top_row_of(Terrain.low_of_corners(corners))), corners)


# The lie itself, for a caller that already resolved the row — the overlay fills, whose Vector3i
# states it (of_cell's "every caller states the ROW it means" rule, #273; re-deriving it here
# would look up what was already passed). The CORNERS are required for the same reason: a cell's
# shape is authored per cell, and a default would be one caller silently drawing another's ground.
#
# It took (rise, climb) until #427 slice 3, which could not describe a corner form at all — a shape
# whose downhill is DIAGONAL. The tilt is now the best-fit plane through the four corners
# (Terrain.gradient_of_corners), which reproduces a cardinal ramp exactly and simply keeps working
# when both components are non-zero.
static func lie_on(cell: Vector3i, corners: Vector4i) -> Transform3D:
	var origin := standing_point(cell)
	var gradient := Terrain.gradient_of_corners(corners)
	if gradient.is_zero_approx():
		return Transform3D(Basis.IDENTITY, origin)
	# The cell's CENTRE height, which is exactly where a quad tilted about its own centre lies flat.
	# For a cardinal ramp that is its low side plus half its climb, as it always was.
	origin.y += (Terrain.centre_height_of_corners(corners)
			- float(Terrain.low_of_corners(corners))) * ROW_HEIGHT
	# Rise over run, in WORLD units, so the angle is the ground's own pitch. The gradient POINTS
	# uphill by definition -- it is the direction height increases -- and the rotation axis is its
	# cross with UP, so a sign slip here tilts the plane the wrong way rather than failing loudly.
	var slope := gradient * (ROW_HEIGHT / CELL_SIZE)
	var uphill := Vector3(slope.x, 0.0, slope.y).normalized()
	var angle := atan(slope.length())
	var basis := Basis(uphill.cross(Vector3.UP).normalized(), angle)
	# Stretch along the UPHILL direction only, so the art keeps its orientation (a rotated arrow
	# would point somewhere else) and only its length up the slope changes. Applied BEFORE the tilt
	# and along an arbitrary horizontal axis rather than to basis.x or basis.z: a diagonal downhill
	# does not lie on either of them, and scaling the nearest one would skew every corner cell.
	var stretch := 1.0 / cos(angle) - 1.0
	var along := Basis(
		Vector3.RIGHT + uphill * (stretch * uphill.x),
		Vector3.UP,
		Vector3.BACK + uphill * (stretch * uphill.z))
	return Transform3D(basis * along, origin)


# The cell containing a world position (floor per axis — see the boundary rule above).
static func cell_of(position: Vector3) -> Vector3i:
	return Vector3i(
		floori(position.x / CELL_SIZE),
		floori(position.y / ROW_HEIGHT),
		floori(position.z / CELL_SIZE)
	)


# The TOP of a GROUND-LEVEL column, in ROWS — what BoardPicker's fallback plane sits on over an
# erased cell (#231), since y=0 is the slab's BOTTOM and a plane there returns the wrong cell at
# grazing angles. Elevation (#273) did NOT retire this: an unpainted column is still exactly one
# LEVEL tall, so this is the top of a height-0 cell and nothing more — which since #427 slice 2 is
# UNITS_PER_LEVEL rows rather than one. It equals surface_y(top_row_of(0)), and test_board_space
# pins the two spellings together.
const FLAT_TOP_ROW := Terrain.UNITS_PER_LEVEL

# The sim<->mirror cell pair (#222): sim cells are 2D (x, y), mirror cells are (x, level, y).
# The ONE spelling of it. flat(NO_CELL) equals GridUtils.NO_CELL by value — pinned, the pointer
# source relies on it.
static func flat(cell: Vector3i) -> Vector2i:
	return Vector2i(cell.x, cell.z)


# Every caller states the ROW it means (#273 — this took no argument and hardcoded 0 while the
# sim had no elevation). Passing beats looking up, and a required argument is what makes the old
# flat assumption unrepresentable rather than merely discouraged. A caller holding a rule HEIGHT
# converts with top_row_of rather than passing it raw.
static func of_cell(cell: Vector2i, row: int) -> Vector3i:
	return Vector3i(cell.x, row, cell.y)


# A 2D-game world POSITION (pixels) as a 3D position at height `y`. The one spelling of
# the ÷16 metric that maps the flat game onto the diorama — grid.map_to_local's pixel
# size, which is what UnitMirror's sprite placement is pinned against. NB the 2D
# camera's CELL_WORLD (32) is a zoom constant, not this, and mixing them was falsified
# earlier in the arc.
static func of_pixels(px: Vector2, y: float) -> Vector3:
	var per_cell := float(GridUtils.TILE_SIZE)
	return Vector3(px.x / per_cell, y, px.y / per_cell)
