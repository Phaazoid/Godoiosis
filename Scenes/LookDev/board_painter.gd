# Paints the look-dev diorama board (#203). @tool so the board is visible in the
# editor viewport during tuning sessions; the height map below is the one source
# of board shape, repainted deterministically on every load. Placeholder terrain
# only -- the real board pipeline is #176 stage 1+, this scene is wired into nothing.
@tool
extends GridMap

const GRASS := 0
const STONE := 1
const RAMP := 2

# One string per row (z), one digit per column (x): the column's height in cells.
const HEIGHT_ROWS: Array[String] = [
	"11111111111111",
	"11111122222111",
	"11111123332111",
	"11111123332111",
	"11111123332111",
	"11111122222111",
	"11111111111111",
	"11111111111111",
	"11111111111111",
	"11222111111111",
	"11222111111111",
	"11222111111111",
	"11111111111111",
	"11111111111111",
]

# Columns in this rect are stone (the platform); everything else is grass.
const STONE_MIN := Vector2i(2, 9)
const STONE_MAX := Vector2i(4, 11)

# Ramps: cell + yaw (degrees, CCW from above). The ramp mesh's high edge faces -Z
# at yaw 0; 270 points it east (+X), 90 points it west (-X).
const RAMPS: Array[Dictionary] = [
	{"cell": Vector3i(5, 1, 3), "yaw": 270},   # plain -> hill ring
	{"cell": Vector3i(6, 2, 3), "yaw": 270},   # hill ring -> plateau
	{"cell": Vector3i(5, 1, 10), "yaw": 90},   # plain -> stone platform
]


func _ready() -> void:
	repaint()


func repaint() -> void:
	clear()
	for z in HEIGHT_ROWS.size():
		var row := HEIGHT_ROWS[z]
		for x in row.length():
			var height := row.unicode_at(x) - 48
			var item := STONE if _is_stone(Vector2i(x, z)) else GRASS
			for y in height:
				set_cell_item(Vector3i(x, y, z), item)
	for ramp in RAMPS:
		var cell: Vector3i = ramp["cell"]
		var yaw: int = ramp["yaw"]
		var orientation := get_orthogonal_index_from_basis(Basis(Vector3.UP, deg_to_rad(float(yaw))))
		set_cell_item(cell, RAMP, orientation)


func _is_stone(column: Vector2i) -> bool:
	return column.x >= STONE_MIN.x and column.x <= STONE_MAX.x \
			and column.y >= STONE_MIN.y and column.y <= STONE_MAX.y
