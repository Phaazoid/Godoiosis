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
# RELEASED where it cannot lie (#1537), gas spills to that cell's open sides at its full level:
# released_onto, the one answer every release asks -- the resolver's deposits and the ignitions below.
# So a burning tree smokes the ground around it; a cell with no open side, or a hole, loses it.
#
# IGNITION (#1335): every cell fire takes this round gives off what its ground's ignition reaction
# releases -- the same `gases` a hit that lights it releases -- added AFTER spill and fade, so fresh
# smoke sits thick for a round before it spreads. Asked of the tile states BEFORE their own tick lights
# anything, which is why both stacks run the gas round first (game._on_round_completed).
#
# WIND (#1660): after spill and fade, every gas the step runs drifts the board's wind's tiles downwind
# (WindRules.drift), along can_cross -- a wall, a sheer ledge or a hole stops it -- and leaves past the
# board's edge (off_board, #1638's rule). A diagonal wind moves it a tile diagonally per tile, as two
# cardinal legs through either side tile: height_step_ok reads no edge on a true diagonal, so it is never
# asked whole. Every cloud walks from one snapshot, and each tile then keeps, per gas, the thickest of all
# that ends there, the younger on a tie, so the visiting order cannot change the answer. A held gas
# neither drifts nor takes a cloud of its kind, which stops on the tile before it. Fresh smoke comes
# after, so it sits a round before it travels; the sky's steam is in the field already, and drifts at once.
#
# THE TIME PAIR (#1311, Pace): the round is two steps. The first runs every gas a Still does not hold; a
# held gas keeps its level and its age, spills nothing, and takes no raise or fresh smoke while it lies
# there (one that is absent may still drift in). The second, only where something is quickened, runs the
# quickened gas again from the first's result, with the smoke of the cells fire's second tick lights
# (TerrainStateManager.cells_fire_takes_again). Both fire lists come off one snapshot, so this forecasts
# the whole round before the tile tick runs. The tile tick between the two steps changes nothing a step
# reads (holds_gas sees FROZEN, which has no clock), so running both here is the round.

const SIDES: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]


# The field after one round. `cells` is GasField's packed map; it is read, never written.
static func next(cells: Dictionary[Vector2i, int], board: BoardContext) -> Dictionary[Vector2i, int]:
	var taken: Array[Vector2i] = []
	var again: Array[Vector2i] = []
	if board.terrain_states != null:
		taken = board.terrain_states.cells_fire_takes(board.tiles)
		again = board.terrain_states.cells_fire_takes_again(board.tiles, taken)
	var out := _step(cells, board, taken, false)
	if again.is_empty() and not _any_quickened(out, board):
		return out
	return _step(out, board, again, true)


# One step of the round: every gas the step runs spills and fades, then the cells `lit` give off their
# smoke. `quick_only` is the second step, which runs only what is quickened.
static func _step(cells: Dictionary[Vector2i, int], board: BoardContext, lit: Array[Vector2i],
		quick_only: bool) -> Dictionary[Vector2i, int]:
	var out: Dictionary[Vector2i, int] = {}
	var raises: Dictionary = {}   # Vector2i -> {Gas.Kind: level}
	for cell: Vector2i in cells:
		var packed: int = cells[cell]
		var kept := packed
		var marks := board.paces_at(cell)
		for kind: Gas.Kind in Gas.kinds_in(packed):
			if not _runs(Pace.of_gas(marks, kind), quick_only):
				continue
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
		var marks := board.paces_at(cell)
		for kind: Gas.Kind in into:
			var level: int = into[kind]
			if level > Gas.level_in(packed, kind) and not _held_here(packed, kind, marks):
				packed = Gas.with_level(packed, kind, level)
		if packed != 0:
			out[cell] = packed
	out = _drift(out, board, quick_only)
	_add_ignitions(out, board, lit)
	return out


# The wind's step (#1660): every gas this step runs, moved downwind by the board's drift. `cells` is
# read, never written; a board with no drift hands it back as it is.
static func _drift(cells: Dictionary[Vector2i, int], board: BoardContext, quick_only: bool) -> Dictionary[Vector2i, int]:
	var tiles := WindRules.drift_of(board)
	if tiles <= 0 or cells.is_empty():
		return cells
	var step := Wind.step(board.wind_direction)
	var out: Dictionary[Vector2i, int] = {}
	var landed: Array[Array] = []   # [cell, kind, level, age]
	for cell: Vector2i in cells:
		var packed: int = cells[cell]
		var stays := packed
		var marks := board.paces_at(cell)
		for kind: Gas.Kind in Gas.kinds_in(packed):
			if not _runs(Pace.of_gas(marks, kind), quick_only) or GasRules.for_kind(kind) == null:
				continue
			stays = Gas.with_level(stays, kind, 0)
			var to: Variant = _blown_to(cell, kind, step, tiles, cells, board)
			if to != null:
				landed.append([to, kind, Gas.level_in(packed, kind), Gas.age_in(packed, kind)])
		if stays != 0:
			out[cell] = stays
	for land: Array in landed:
		var cell: Vector2i = land[0]
		var kind: Gas.Kind = land[1]
		var level: int = land[2]
		var age: int = land[3]
		var packed: int = out.get(cell, 0)
		var here := Gas.level_in(packed, kind)
		if level > here or (level == here and age < Gas.age_in(packed, kind)):
			out[cell] = Gas.with_level(packed, kind, level, age)
	return out


# Where a cloud of `kind` on `cell` comes to rest after `tiles` steps downwind, or null when it blows
# off the board. `cells` is the field it drifts across, whose held gas it stops short of.
static func _blown_to(cell: Vector2i, kind: Gas.Kind, step: Vector2i, tiles: int,
		cells: Dictionary[Vector2i, int], board: BoardContext) -> Variant:
	var pos := cell
	for _i in tiles:
		var next := pos + step
		if off_board(next, board):
			return null
		if _held_here(cells.get(next, 0), kind, board.paces_at(next)) or not _drifts(pos, next, step, board):
			break
		pos = next
	return pos


# May a cloud drift one step: across the edge for a cardinal wind, or through either side tile, each leg
# crossed, for a diagonal one.
static func _drifts(from: Vector2i, to: Vector2i, step: Vector2i, board: BoardContext) -> bool:
	if step.x == 0 or step.y == 0:
		return can_cross(from, to, board)
	for side: Vector2i in [from + Vector2i(step.x, 0), from + Vector2i(0, step.y)]:
		if can_cross(from, side, board) and can_cross(side, to, board):
			return true
	return false


# Is this cell past the board's edge (#1638): no tile, and not a hole inside the board. Open sky, which
# carries gas away. The one answer for blown gas (PlanResolver._gas_landing) and the wind's drift.
static func off_board(cell: Vector2i, board: BoardContext) -> bool:
	return not board.has_ground(cell) and not board.is_void_at(cell)


# Does a step run a gas at this pace: never a held one, and only a quickened one on the second step.
static func _runs(pace: Pace.Kind, quick_only: bool) -> bool:
	return pace != Pace.Kind.HELD and (not quick_only or pace == Pace.Kind.QUICK)


# A held gas lying here takes nothing more (#1311); one that is absent may arrive.
static func _held_here(packed: int, kind: Gas.Kind, marks: Dictionary) -> bool:
	return Gas.level_in(packed, kind) > 0 and Pace.of_gas(marks, kind) == Pace.Kind.HELD


# Is any gas in the field quickened where it lies: whether the round needs its second step at all.
static func _any_quickened(cells: Dictionary[Vector2i, int], board: BoardContext) -> bool:
	for cell: Vector2i in cells:
		var marks := board.paces_at(cell)
		if marks.is_empty():
			continue
		for kind: Gas.Kind in Gas.kinds_in(cells[cell]):
			if Pace.of_gas(marks, kind) == Pace.Kind.QUICK:
				return true
	return false


# What a spreading fire gives off where it lands, into `out`: GasField.add_level's add-and-cap with a
# fresh hold, wherever released_onto lays it (a burning TREE spills it to its open sides, #1537).
# `lit` is the cells the step's fire tick takes, read as the board's planned tiles leave them (#1430,
# #1498): the outline's board carries the previewed plan's, so a tile a queued hit lights spreads in it;
# the round's carries none.
static func _add_ignitions(out: Dictionary[Vector2i, int], board: BoardContext, lit: Array[Vector2i]) -> void:
	if board.terrain_states == null:
		return
	for cell: Vector2i in lit:
		var fuel := board.terrain_states.fuel_at(cell)
		if fuel == null:
			continue
		for onto in released_onto(cell, board):
			var packed: int = out.get(onto, 0)
			var marks := board.paces_at(onto)
			for kind: Gas.Kind in Gas.released(fuel.gases):
				if _held_here(packed, kind, marks):
					continue
				var level := mini(Gas.level_in(packed, kind) + fuel.gases[kind], Gas.MAX_LEVEL)
				packed = Gas.with_level(packed, kind, level)
			if packed != 0:
				out[onto] = packed


# Where gas RELEASED on this cell comes to lie (#1537): the cell itself when it holds gas; otherwise each
# open side it could cross onto, every one at the full level released; nowhere from a hole, or a cell
# with no open side. The one answer for every release -- a hit's deposit, a unit's reaction, a fire's
# ignition -- so a burning tree smokes the ground around it. Sides in SIDES order.
static func released_onto(cell: Vector2i, board: BoardContext) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if holds_gas(cell, board):
		out.append(cell)
		return out
	if not board.has_surface(cell):
		return out
	for side: Vector2i in SIDES:
		if _may_enter(cell, cell + side, board):
			out.append(cell + side)
	return out


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
	return holds_gas(from, board) and _may_enter(from, to, board)


# The edge half of can_cross, which a spill off a cell that cannot hold gas asks alone (released_onto).
static func _may_enter(from: Vector2i, to: Vector2i, board: BoardContext) -> bool:
	return holds_gas(to, board) and RulesService.height_step_ok(from, to, board)
