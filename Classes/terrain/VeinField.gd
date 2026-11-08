extends RefCounted
class_name VeinField

# The materia vein store (#696): which vein, if any, runs through each cell. GasField's shape -- sparse,
# one int a cell (a Vein.Kind), a DirtyCells whose `version` is how the renderer and the dev header
# learn that anything moved. One vein per cell: painting a cell overwrites what ran through it.
#
# AUTHORED, and no pass writes it, so a resolve does not seal it (tests/support/board_context_fields.gd)
# and an authored save writes it as painted (BoardSnapshot.edited copies it whole). A drill that opens
# or buries one mid-battle is a set_kind; every reader asks the store live.
#
# A vein needs ground, by the tile states' rule: the writer refuses a groundless cell (ground_source),
# and erasing a tile prunes it (DevController._prune_groundless_stores).

var _cells: Dictionary[Vector2i, int] = {}
var dirty := DirtyCells.new()

# cell -> has ground. Unset judges nothing, which is what a TileSet-less test board wants.
var ground_source: Callable


func kind_at(cell: Vector2i) -> Vein.Kind:
	return _cells.get(cell, Vein.Kind.NONE) as Vein.Kind


# NONE erases. A vein on a groundless cell is refused; taking one away never is. Marks the cell only
# when its value changed, so a drag repainting what is already there costs a renderer nothing.
func set_kind(cell: Vector2i, kind: Vein.Kind) -> void:
	if kind != Vein.Kind.NONE and not has_ground(cell):
		return
	if int(kind) == int(_cells.get(cell, Vein.Kind.NONE)):
		return
	if kind == Vein.Kind.NONE:
		_cells.erase(cell)
	else:
		_cells[cell] = kind
	dirty.mark(cell)


func has_ground(cell: Vector2i) -> bool:
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


# GasField.prune_groundless's shape: a vein over no tile would come back the moment ground was
# repainted there. Returns whether anything went.
func prune_groundless(has_ground_at: Callable) -> bool:
	var doomed: Array[Vector2i] = []
	for cell: Vector2i in _cells:
		var grounded: bool = has_ground_at.call(cell)
		if not grounded:
			doomed.append(cell)
	for cell in doomed:
		_cells.erase(cell)
		dirty.mark(cell)
	return not doomed.is_empty()


# The ScenarioData pair, GasField's: a load restores a result, so it writes directly.
func to_dict() -> Dictionary:
	return _cells.duplicate()


func load_dict(data: Dictionary) -> void:
	_cells.clear()
	for cell: Vector2i in data:
		var kind: int = data[cell]
		if kind != Vein.Kind.NONE:
			_cells[cell] = kind
	dirty.mark_all()
