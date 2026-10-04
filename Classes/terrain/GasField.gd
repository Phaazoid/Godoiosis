extends RefCounted
class_name GasField

# The atmosphere store (#508): how much of each gas every cell holds. The DECLARED second per-cell
# store beside TerrainStateManager, which the ticket asked for -- tile states are booleans with a
# clock, and an amount that spreads and thins is not a state (#508 ruling 1).
#
# Sparse, one packed int per cell (Gas.with_amount); a cell absent holds no gas. BoardHeights' shape:
# RefCounted, no signals, a DirtyCells whose non-consuming `version` is how a renderer learns that
# anything moved. Nothing consumes the cell LIST yet.
#
# Gas needs ground (the dev's ruling 6 keeps it off any edge a unit could not cross, and water is
# ground for this purpose), so the writer refuses a groundless cell and erasing a tile prunes it.
# The refusal is the STORE's, through ground_source -- TerrainStateManager's shape, wired at the same
# two build sites with the same predicate, so a brush stroke and an attack's deposit cannot disagree.

var _cells: Dictionary[Vector2i, int] = {}
var dirty := DirtyCells.new()

# cell -> has ground. Unset judges nothing, which is what a TileSet-less test board wants.
var ground_source: Callable


func amount_at(cell: Vector2i, kind: Gas.Kind) -> int:
	return Gas.amount_in(_cells.get(cell, 0), kind)


func packed_at(cell: Vector2i) -> int:
	return _cells.get(cell, 0)


# Clamped to 0..MAX; zero erases. Marks the cell only when its value actually changed, so a drag
# repainting what is already there costs a renderer nothing. A positive amount on a groundless cell is
# refused; taking gas away never is.
func set_amount(cell: Vector2i, kind: Gas.Kind, amount: int) -> void:
	if amount > 0 and not _has_ground(cell):
		return
	var before: int = _cells.get(cell, 0)
	var after := Gas.with_amount(before, kind, amount)
	if after == before:
		return
	if after == 0:
		_cells.erase(cell)
	else:
		_cells[cell] = after
	dirty.mark(cell)


# A deposit ADDS to what the cell holds, clamped at MAX: a second douse makes more steam.
func add_amount(cell: Vector2i, kind: Gas.Kind, amount: int) -> void:
	if amount <= 0:
		return
	set_amount(cell, kind, amount_at(cell, kind) + amount)


# Play one resolved cell effect's gas into the store -- terrain_states.apply's twin, called beside it
# by both executors.
func apply(effect: ResolvedCellEffect) -> void:
	for kind: Gas.Kind in effect.gas_added:
		add_amount(effect.cell, kind, effect.gas_added[kind])


func _has_ground(cell: Vector2i) -> bool:
	if not ground_source.is_valid():
		return true
	var grounded: bool = ground_source.call(cell)   # typed local: .call() erases to Variant
	return grounded


func clear() -> void:
	if _cells.is_empty():
		return
	_cells.clear()
	dirty.mark_all()


func is_empty() -> bool:
	return _cells.is_empty()


func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_cells.keys())
	return out


# The ground-loss sweep, BoardHeights.prune_groundless's shape and reasoning: gas over no tile is junk
# that would come back the moment ground was repainted there. Returns whether anything went.
func prune_groundless(has_ground: Callable) -> bool:
	var doomed: Array[Vector2i] = []
	for cell: Vector2i in _cells:
		var grounded: bool = has_ground.call(cell)
		if not grounded:
			doomed.append(cell)
	for cell in doomed:
		_cells.erase(cell)
		dirty.mark(cell)
	return not doomed.is_empty()


# Serialization pair for ScenarioData (a plain Dictionary is what it can @export), mirroring
# BoardHeights.to_corner_dict / load_corner_dict. A load restores a result, so it writes directly.
func to_dict() -> Dictionary:
	return _cells.duplicate()


func load_dict(data: Dictionary) -> void:
	_cells.clear()
	for cell: Vector2i in data:
		var packed: int = data[cell]
		if packed != 0:
			_cells[cell] = packed
	dirty.mark_all()
