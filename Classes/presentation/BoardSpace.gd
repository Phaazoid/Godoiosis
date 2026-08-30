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
#
# STATEFUL SINCE #521, and that is a deliberate change of character -- everything above is pure
# arithmetic. The tear-out asks one new question, "is this cell STAGED, and where", and the dev's
# ruling on #410 puts it here: answered where BoardSpace is already consulted, never in a separate
# diorama scene, which would be a second answer to where a thing renders. A Staging class this
# delegated to would be two names for one fact. Pacing and PlayerSettings are the precedent.

const CELL_SIZE := 1.0

# One row of the vertical index, in world units. The whole re-metric is this constant: a 45 degree
# ramp still rises CELL_SIZE over CELL_SIZE of run, it now just spans UNITS_PER_LEVEL rows to do it.
const ROW_HEIGHT := CELL_SIZE / Terrain.UNITS_PER_LEVEL

# How far below a cell's surface a SIDE face starts (#559). A block's side quads used to reach the
# top plane itself, so at every cell border four surfaces met along one line — the two neighbouring
# top faces and both blocks' buried sides — and a pixel centre landing on it could be won by the
# side. At an axis-aligned yaw a whole row of those borders lands on one scanline, which is how a
# hairline of dirt drew itself across the board. Dropping the side by this much takes it out of the
# plane it was tying in; the RIM the generator puts in the gap wears the TOP material, so the
# surface still meeting the neighbour there is the ground rather than the dirt under it.
#
# A correctness epsilon, not a look value: big enough to clear depth-buffer resolution at board
# distances by orders of magnitude, small enough to stay under one texel (tiles are 32 px to a
# cell, so a texel is 0.031) and never read as a band. Nothing tunes it by eye — the laws that
# guard it measure the PROPERTY (a side never reaches the surface, the shell stays closed) so the
# value is free to move without rewriting them.
const SIDE_RIM := 0.004

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
# whose downhill is DIAGONAL. The tilt is the best-fit plane through the four corners
# (Terrain.gradient_of_corners), which reproduces a cardinal ramp exactly.
#
# ON A CORNER FORM THERE IS NO SUCH TRANSFORM, and this says so rather than approximating (#427
# slice 4 follow-up). A cell's four surface points are not coplanar there, an affine transform maps a
# plane to a plane, and the best-fit one CROSSES the ground — a quarter of the climb at every corner,
# alternating sign, which is an eighth of a cell on the gentle slope and shows as z-fighting on the
# flat half. Slice 3 shipped that plane and called it "the average the markup wants"; it is not.
# So the basis is IDENTITY on a non-planar form and the FOLD is the caller's to carry —
# BoardOverlays carries it in the marker's mesh, which is the only place it can live.
static func lie_on(cell: Vector3i, corners: Vector4i) -> Transform3D:
	var origin := standing_point(cell)
	# The cell's own surface at its CENTRE -- Terrain.height_at_uv, the ONE surface (slice 3's law),
	# so surface_point and surface_height_at are now the same function evaluated at the same point.
	# They were not: this read the corners' MEAN, which is the best-fit PLANE's centre, and on an
	# outer corner the two answer a quarter of the climb apart -- so anything STANDING on a corner
	# cell floated. Exact for every planar form, where the mean is the centre, so no flat cell and no
	# cardinal ramp moves by this.
	origin.y += (Terrain.height_at_uv(corners, 0.5, 0.5)
			- float(Terrain.low_of_corners(corners))) * ROW_HEIGHT
	var gradient := Terrain.gradient_of_corners(corners)
	if gradient.is_zero_approx() or not Terrain.is_planar_form(corners):
		return Transform3D(Basis.IDENTITY, origin)
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


# The camera yaw that sees a cell pair SIDE-ON (#520): looking perpendicular to the line from
# `from` to `to`, so an attacker and what they are swinging at both sit across the frame instead
# of one hiding behind the other. Cells rather than units because the RESOLVER already owns the
# aim (origin_cell -> target_cell) and re-deriving it off live node positions would be a second
# answer to where the blow is pointed (Law #2).
#
# Yaw convention, and it is the whole of the arithmetic: CameraRig3D orbits about Y with the
# camera parked at local +Z, so yaw t puts it at direction (sin t, cos t) from the aim. Side-on
# means that direction is perpendicular to the pair's, which atan2(-dz, dx) solves directly.
#
# TWO yaws satisfy it, 180 apart -- the same shot from either side. Returning the one nearer
# `baseline` is what makes it a SPIN rather than a lurch: the camera always takes the short way
# round from where playback squared it up.
#
# NAN for a pair with no direction (a self-verb, an aim at your own cell). A float sentinel is
# unavoidable here since every real angle is a legal yaw, and NAN is the one value that cannot be
# mistaken for one; is_nan() at the single call site is what keeps it from travelling.
static func side_on_yaw(from: Vector2i, to: Vector2i, baseline: float) -> float:
	var dx := float(to.x - from.x)
	var dz := float(to.y - from.y)   # a sim cell's y IS the world z -- see of_cell above
	if is_zero_approx(dx) and is_zero_approx(dz):
		return NAN
	var side_on := rad_to_deg(atan2(-dz, dx))
	var opposite := side_on + 180.0
	if absf(angle_difference(deg_to_rad(baseline), deg_to_rad(opposite))) \
			< absf(angle_difference(deg_to_rad(baseline), deg_to_rad(side_on))):
		return opposite
	return side_on


# --- the tear-out: which cells are staged, and where (#521) ------------------------------------
#
# Zero displacement IS the board, so every reader below is safe on an unstaged board and on a board
# that has never staged anything. One rigid offset for the whole set rather than one per cell: the
# diorama is a TRUE reconstruction (dev, #410), so board-relative geometry is preserved by moving
# the set as a body -- exact by construction, with no arithmetic to get wrong.
#
# A static outlives a suite (#449's lesson on PlayerSettings._state), which is what reset_for_test
# is for. Nothing here reads the profile: WHETHER to stage is the caller's question, and
# OrderExecutor asks it once per pass.
static var _staged: Dictionary[Vector2i, bool] = {}
static var _stage_offset := Vector3.ZERO
# How far above the board the diorama sits, in CELLS. A feel value, so it is a GameKnobs row rather
# than a constant -- and a `static var` because that is the only form a knob can write.
static var STAGE_LIFT := 40.0
# Monotonic, so a per-frame poll can tell "the staging moved" from "it did not" without diffing the
# set. DirtyCells.version's shape, and for the same reason: any number of readers, none consuming.
static var staging_version := 0

# --- the transition: tiles in the AIR, and where the camera is while they are (#521 slice B) -----
#
# FLIGHT IS AN OVERLAY, NEVER THE STORED STATE, and that is what keeps every existing reader honest.
# stage() still writes the LANDED board; this is a transient delta added on top. So a run with no
# driver -- headless, the BOARD profile, a bare fixture -- never populates it and reads exactly what
# it read before this slice existed. The alternative, storing in-flight positions as the truth,
# would have made "where is this cell" depend on whether anything was animating.
static var _flight: Dictionary[Vector2i, Vector3] = {}
# The schedule being played, and how far into it we are. Held here rather than on the driver because
# OrderExecutor publishes it and the 3D host polls it -- the same one-writer-many-readers shape as
# executing_plan and staging_version.
static var _flight_plan: Array[Dictionary] = []
static var _flight_elapsed := 0.0
# The path every tile walks, same for all of them and offset only in TIME. Entry runs socket ->
# diorama, exit runs diorama -> socket; one pair of endpoints rather than an "is it reversed" flag
# the geometry then has to interpret.
static var _flight_from := Vector3.ZERO
static var _flight_to := Vector3.ZERO
# Which direction this transition is going, for the driver's sake -- the camera and the white-out
# are not symmetric even though the travel is.
static var _flight_entering := true

# HOW HIGH THE CAMERA IS RIGHT NOW, which is NOT where the diorama is. They are the same at rest and
# they differ during exactly one window -- the transition -- which is the window that needs them
# apart: the cut treatment puts the camera at the diorama before a single tile is there, and the
# travel treatment holds it on the board while they leave. _mirror_camera polls this every frame, so
# with nothing driving it this returns stage_offset() and the camera behaves as it always has.
#
# A THIRD FIELD RATHER THAN A CLEVER READING OF THE OTHER TWO: directed_line is an angle,
# framed_span is a fit, emphasis is a weight, and one field answering two questions is what spins a
# camera side-on to a walk (#520).
static var _camera_lift := Vector3.ZERO
static var _camera_lift_driven := false


static func stage(cells: Array[Vector2i], offset: Vector3) -> void:
	_staged.clear()
	for cell in cells:
		_staged[cell] = true
	_stage_offset = offset
	staging_version += 1


static func clear_staging() -> void:
	# The flight goes FIRST and unconditionally, before the early-out: a transition abandoned by F2
	# or Mission Select mid-flight has an overlay to drop even on a board whose staged set is
	# already empty. Inside this function rather than beside its callers, because this is the door
	# clear_board() calls and a second reset door is how a column gets left in the sky.
	_end_flight()
	if _staged.is_empty():
		return
	_staged.clear()
	_stage_offset = Vector3.ZERO
	staging_version += 1


# --- driving the transition ---------------------------------------------------------------------


# Start flying `plan` (a StagingFlight schedule). Every cell begins in its socket, which is `from`
# below the diorama -- so the tiles are already logically staged and the overlay is what holds them
# down until their turn comes.
static func begin_flight(plan: Array[Dictionary], from: Vector3, to: Vector3, entering: bool) -> void:
	_flight_plan = plan
	_flight_elapsed = 0.0
	_flight_from = from
	_flight_to = to
	_flight_entering = entering
	_flight.clear()
	for entry: Dictionary in plan:
		_flight[entry["cell"]] = from
	staging_version += 1


# Advance the flight by `delta`. Returns true when a tile LANDED on this step, which is the caller's
# cue to re-route its column and let the standing-state polls rebuild its props.
#
# THE VERSION BUMPS ON LANDINGS ONLY, and that is load-bearing rather than thrifty: OverlayMirror
# gates its whole standing-state rebuild on staging_version, so bumping per frame would rebuild
# every prop on every frame of the transition. Landings are discrete, so a tile flies BARE and gets
# dressed the instant it is home -- which is also why props are dropped when the tear-out starts.
static func advance_flight(delta: float) -> bool:
	if _flight_plan.is_empty():
		return false
	_flight_elapsed += delta
	var landed := false
	for entry: Dictionary in _flight_plan:
		var cell: Vector2i = entry["cell"]
		var progress := StagingFlight.progress_at(entry, _flight_elapsed)
		if progress >= 1.0:
			if _flight.has(cell):
				# Erased rather than set to the endpoint: absence IS the landed state, so a cell
				# that is home costs nothing to ask about and cannot be left holding a stale delta.
				_flight.erase(cell)
				if _flight_to != Vector3.ZERO:
					_flight[cell] = _flight_to
				landed = true
			continue
		_flight[cell] = _flight_from.lerp(_flight_to, StagingFlight.slam(progress))
	if _flight.is_empty():
		_flight_plan.clear()
	if landed:
		staging_version += 1
	return landed


static func flight_active() -> bool:
	return not _flight_plan.is_empty()


static func flight_entering() -> bool:
	return _flight_entering


static func flight_elapsed() -> float:
	return _flight_elapsed


# This cell's displacement from the diorama right now. Zero once it is home, which is also what an
# unstaged or unknown cell answers -- there is no third state to check for.
static func flight_offset(cell: Vector2i) -> Vector3:
	return _flight.get(cell, Vector3.ZERO)


# Put every tile at the end of its path and stop. The executor calls this the moment its await
# returns, so "the board is where the transition left it" holds in runs that never drew a frame --
# headless, above all, where the await returns instantly and no driver ever ran.
static func end_flight_now() -> void:
	_end_flight()


# Is this cell between its socket and its landing right now? The ground asks, because a column in
# the air cannot live in either lattice -- one GridMap is one offset.
static func in_flight(cell: Vector2i) -> bool:
	return _flight.has(cell)


static func flying_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.assign(_flight.keys())
	return cells


static func _end_flight() -> void:
	_flight.clear()
	_flight_plan.clear()
	_flight_elapsed = 0.0
	_flight_from = Vector3.ZERO
	_flight_to = Vector3.ZERO
	_flight_entering = true
	release_camera_lift()


# Where the camera should sit right now. Equals the diorama at rest, so nothing changes for any
# caller until a transition actually takes it.
static func camera_lift() -> Vector3:
	return _camera_lift if _camera_lift_driven else _stage_offset


static func drive_camera_lift(lift: Vector3) -> void:
	_camera_lift = lift
	_camera_lift_driven = true


static func release_camera_lift() -> void:
	_camera_lift = Vector3.ZERO
	_camera_lift_driven = false


# Where this cell's contents render, relative to the board. THE placement question -- every mirror
# adds it at its own placement site, and the ground GridMap honours it as a node transform because
# a GridMap cell cannot be offset individually.
static func staged_offset(cell: Vector2i) -> Vector3:
	if not _staged.has(cell):
		return Vector3.ZERO
	# The overlay is empty whenever nothing is flying, so this is the plain stage offset at rest.
	return _stage_offset + _flight.get(cell, Vector3.ZERO)


static func is_staged(cell: Vector2i) -> bool:
	return _staged.has(cell)


# The set itself, for the one reader that must walk it: the mirror re-routing whole columns between
# the board and the staged GridMap when the staging changes.
static func staged_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.assign(_staged.keys())
	return cells


static func stage_offset() -> Vector3:
	return _stage_offset


# Is a fight on stage AT ALL -- asked by the camera per frame, so it must not build the cell array
# staged_cells() does. Not derivable from stage_offset(), which is legitimately ZERO when the lift
# knob is dialled to nothing.
static func staging_active() -> bool:
	return not _staged.is_empty()


# Where the diorama sits for a tear-out starting now. Straight up: the tiles rise OUT of the board
# (#521), and the exit drops them back into the sockets they left.
static func lift_offset() -> Vector3:
	return Vector3(0.0, STAGE_LIFT * CELL_SIZE, 0.0)


static func reset_for_test() -> void:
	_staged.clear()
	_stage_offset = Vector3.ZERO
	staging_version = 0
	_end_flight()
