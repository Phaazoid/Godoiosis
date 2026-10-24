extends Object
class_name GasSpread

# How gas moves, once per round (#508): the ONE rule, a pure function of the field and the board.
# GasField.tick plays it on the live store and GasMirror's forecast runs it on a copy, so what Alt
# shows for next round and what the round does cannot disagree.
#
# SPILL (dev, 2026-10-03): every medium or thick cell raises each open side to one level thinner,
# every round it holds; a cell thins a level after holding it for its gas's hold_rounds. Thin gas
# never spreads. Computed from a snapshot with raises taking the max, so the order cells are visited
# in cannot change the answer.
#
# WHERE gas may be is ruling 6: never across an edge a unit could not walk over, but over water.
#
# IGNITION (#1335): every cell fire takes this round gives off what its ground's ignition reaction
# releases -- the same `gases` a hit that lights it releases -- added AFTER spill and fade, so fresh
# smoke sits thick for a round before it spreads. Asked of the tile states BEFORE their own tick lights
# anything, which is why both stacks run the gas round first (game._on_round_completed).

const SIDES: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]


# The field after one round. `cells` is GasField's packed map; it is read, never written.
static func next(cells: Dictionary[Vector2i, int], board: BoardContext) -> Dictionary[Vector2i, int]:
	var out: Dictionary[Vector2i, int] = {}
	var raises: Dictionary = {}   # Vector2i -> {Gas.Kind: level}
	for cell: Vector2i in cells:
		var packed: int = cells[cell]
		var kept := packed
		for kind: Gas.Kind in Gas.kinds_in(packed):
			var rules := GasRules.for_kind(kind)
			if rules == null:
				continue
			var level := Gas.level_in(packed, kind)
			if level >= Gas.Level.MEDIUM:
				for side: Vector2i in SIDES:
					var to := cell + side
					if can_cross(cell, to, board):
						var into: Dictionary = raises.get(to, {})
						into[kind] = maxi(int(into.get(kind, 0)), level - 1)
						raises[to] = into
			var age := Gas.age_in(packed, kind) + 1
			if age >= rules.hold_rounds:
				kept = Gas.with_level(kept, kind, level - 1)
			else:
				kept = Gas.with_level(kept, kind, level, age)
		if kept != 0:
			out[cell] = kept
	for cell: Vector2i in raises:
		var into: Dictionary = raises[cell]
		var packed: int = out.get(cell, 0)
		for kind: Gas.Kind in into:
			var level: int = into[kind]
			if level > Gas.level_in(packed, kind):
				packed = Gas.with_level(packed, kind, level)
		if packed != 0:
			out[cell] = packed
	_add_ignitions(out, board)
	return out


# What a spreading fire gives off where it lands, into `out`: GasField.add_level's add-and-cap with a
# fresh hold, on a cell that can hold gas (a burning TREE cannot, ruling 6, so its smoke goes nowhere).
# The fire spreads from the tiles as the board's deposits leave them (#1430): the outline's board
# carries the previewed plan's, so a tile a queued hit lights spreads in it; the round's carries none.
static func _add_ignitions(out: Dictionary[Vector2i, int], board: BoardContext) -> void:
	if board.terrain_states == null:
		return
	for cell: Vector2i in board.terrain_states.cells_fire_takes(board.deposits):
		var fuel := board.terrain_states.fuel_at(cell)
		if fuel == null or not holds_gas(cell, board):
			continue
		var packed: int = out.get(cell, 0)
		for kind: Gas.Kind in Gas.released(fuel.gases):
			var level := mini(Gas.level_in(packed, kind) + fuel.gases[kind], Gas.MAX_LEVEL)
			packed = Gas.with_level(packed, kind, level)
		if packed != 0:
			out[cell] = packed


# May gas lie on this cell at all: ground, not a hole, and somewhere a unit could stand -- or water,
# which it floats over.
static func holds_gas(cell: Vector2i, board: BoardContext) -> bool:
	if board.grid == null:
		return true   # no board to judge: GridUtils' own permissive answer for a gridless context
	if not board.has_surface(cell):
		return false
	return board.is_walkable(cell) or board.terrain_kind_at(cell) == Terrain.Kind.WATER


# May gas cross from one cell to its neighbour: both hold gas, and the edge between them is one a
# unit could step over (RulesService.height_step_ok -- a sheer ledge stops it, a ramp does not).
static func can_cross(from: Vector2i, to: Vector2i, board: BoardContext) -> bool:
	return holds_gas(from, board) and holds_gas(to, board) and RulesService.height_step_ok(from, to, board)
