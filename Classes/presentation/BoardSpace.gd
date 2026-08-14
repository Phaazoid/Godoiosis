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
	return Vector3(cell.x + 0.5, cell.y + 1.0, cell.z + 0.5) * CELL_SIZE


# The cell containing a world position (floor per axis — see the boundary rule above).
static func cell_of(position: Vector3) -> Vector3i:
	return Vector3i(
		floori(position.x / CELL_SIZE),
		floori(position.y / CELL_SIZE),
		floori(position.z / CELL_SIZE)
	)


# The TOP LEVEL of a flat-board column: of_flat puts every cell at y-index 0, so the
# face a unit stands on — and the plane BoardPicker falls back to over an erased cell
# (#231) — sits one CELL_SIZE up, never at y = 0. Named because y=0 is the slab's
# BOTTOM and reads plausible: a fallback plane there returns the wrong cell at grazing
# angles. UnitMirror.COLUMN_TOP derives from this rather than restating it.
const FLAT_TOP_LEVEL := 1

# The flat-board bridge (#222): sim cells are 2D (x, y), mirror cells are (x, 0, y)
# until real elevation arrives — the ONE spelling of that pair. Not for columns with
# a real height (BoardPicker._top_cell keeps its own y). flat(NO_CELL) equals
# GridUtils.NO_CELL by value — pinned, the pointer source relies on it.
static func flat(cell: Vector3i) -> Vector2i:
	return Vector2i(cell.x, cell.z)


static func of_flat(cell: Vector2i) -> Vector3i:
	return Vector3i(cell.x, 0, cell.y)


# A 2D-game world POSITION (pixels) as a 3D position at height `y`. The one spelling of
# the ÷16 metric that maps the flat game onto the diorama — grid.map_to_local's pixel
# size, which is what UnitMirror's sprite placement is pinned against. NB the 2D
# camera's CELL_WORLD (32) is a zoom constant, not this, and mixing them was falsified
# earlier in the arc.
static func of_pixels(px: Vector2, y: float) -> Vector3:
	var per_cell := float(GridUtils.TILE_SIZE)
	return Vector3(px.x / per_cell, y, px.y / per_cell)
