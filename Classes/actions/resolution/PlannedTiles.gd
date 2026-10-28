extends RefCounted
class_name PlannedTiles

# Where a pass leaves the tiles it touches (#1498): the cell half of the pass's hypothetical, beside
# the body half on ResolvedPlan.hypo, and the same model. A cell is copied from the live stores the
# first time a landing touches it, and every later landing folds into the copy; a cell nothing has
# touched is not here, and reads as the stores do. One absolute record per cell -- what a pass can
# change today, its tile states and its gas -- so a read is one lookup, never a fold over deposits.
#
# land() is the one write door, and it uses the stores' own folds and ground rule
# (TerrainStateManager.fold, GasField.fold), so a planned cell and the landed one cannot disagree. It
# never writes a store. BoardContext.planned is the read door: a board whose tile reads ask here first.
#
# A snapshot, like the body copy: a store written after a cell was copied (a dev brush stroke under a
# cached plan) is not seen here until the next resolve.

class Cell:
	var states: Array[Terrain.TileState] = []
	var gas := 0

var _terrain: TerrainStateManager
var _gas: GasField
var _cells: Dictionary[Vector2i, Cell] = {}


func _init(terrain: TerrainStateManager, gas: GasField) -> void:
	_terrain = terrain
	_gas = gas


# Land one tile change, copying its cell from the stores on first touch.
func land(effect: ResolvedCellEffect) -> void:
	var cell := effect.cell
	var record: Cell = _cells.get(cell)
	if record == null:
		record = Cell.new()
		if _terrain != null:
			record.states = _terrain.states_at(cell)
		if _gas != null:
			record.gas = _gas.packed_at(cell)
		_cells[cell] = record
	if _terrain != null:
		record.states = TerrainStateManager.fold(record.states, effect, _terrain.has_ground(cell))
	if _gas != null:
		record.gas = GasField.fold(record.gas, effect, _gas.has_ground(cell))


# The ONE spelling of "planned first, then live": the record where a landing touched the cell, the
# stores' answer everywhere else.
func states_at(cell: Vector2i) -> Array[Terrain.TileState]:
	var record: Cell = _cells.get(cell)
	if record != null:
		return record.states.duplicate()
	if _terrain == null:
		var none: Array[Terrain.TileState] = []
		return none
	return _terrain.states_at(cell)


func has_state(cell: Vector2i, state: Terrain.TileState) -> bool:
	var record: Cell = _cells.get(cell)
	if record != null:
		return record.states.has(state)
	return _terrain != null and _terrain.has_state(cell, state)


func gas_at(cell: Vector2i) -> int:
	var record: Cell = _cells.get(cell)
	if record != null:
		return record.gas
	return _gas.packed_at(cell) if _gas != null else 0


# The cells a landing touched, in the order they were first touched.
func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_cells.keys())
	return out


func copy() -> PlannedTiles:
	var twin := PlannedTiles.new(_terrain, _gas)
	for cell: Vector2i in _cells:
		var record := Cell.new()
		record.states = _cells[cell].states.duplicate()
		record.gas = _cells[cell].gas
		twin._cells[cell] = record
	return twin


# The board as it stands once these changes land, written nowhere: the one-off moment (the AI's single
# deposit, the split forecast's replay) beside the pass's own plan.tiles. Built on any tiles the board
# already carries, so none are dropped.
static func after(board: BoardContext, effects: Array[ResolvedCellEffect]) -> BoardContext:
	if effects.is_empty():
		return board
	var tiles := board.tiles.copy() if board.tiles != null else PlannedTiles.new(board.terrain_states, board.gas)
	for effect in effects:
		tiles.land(effect)
	return board.planned(tiles)
