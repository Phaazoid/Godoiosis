extends RefCounted
class_name BoardHeights

# The per-cell elevation store (#218/#257) — how high each cell's surface sits, and which cells are
# ramps. Sibling of TerrainStateManager: same per-cell shape, same round-trip through ScenarioData,
# same role in BoardContext. Canon: docs/design/verticality.md.
#
# NOT tileset custom data, unlike walkable / move_cost / terrain_type. Those are per-TILE (per atlas
# coordinate), so an elevation among them would need a distinct grass tile per level -- 21 of them
# for a 20-level cliff city -- and a Tile Brush palette to match. Per-cell also means the rules can
# be tested on any painted board with no new tiles or art.
#
# NOT folded into TerrainStateManager either: that holds a STACK of enum states with durations, this
# holds two scalars, and height is authored map geometry rather than something attacks deposit. It is
# deliberately not assumed permanent, though -- terrain.md's "attack the map" list already carries
# EARTH raising a destructible wall.
#
# RefCounted rather than TerrainStateManager's Node: no signals, no _process, nothing needing the
# tree, and a RefCounted frees itself instead of reading as a gdUnit orphan.

var _elevations: Dictionary[Vector2i, int] = {}
var _ramps: Dictionary[Vector2i, Terrain.RampRise] = {}

# Which cells changed since the 3D mirror last reconciled (#319) — the BoardGrid.dirty twin, same
# single-consumer contract. Height is terrain to the mirror: it decides how tall a column is drawn,
# so a height edit has to reach it exactly the way a repaint does.
var dirty := DirtyCells.new()

# The board's lowest painted elevation, CACHED. BoardMirror needs it per sync (every column reaches
# down to a shared floor, or a dip would be a hole) and re-deriving it walked painted_cells() each
# time -- O(board) on a fully-painted board, in the frame path this ticket exists to empty.
# Recomputed lazily and only when a write could have RAISED it; a write that lowers it is answered
# in place.
var _lowest := 0
var _lowest_stale := false

# An ABSENT cell is elevation 0, and that is a decision rather than a gap: a flat board is the
# overwhelmingly common case, so it is stored as nothing at all. This method is the ONE place that
# default is applied -- no caller re-derives it, and no caller reads the dictionaries directly.
func elevation_at(cell: Vector2i) -> int:
	return _elevations.get(cell, 0)

func ramp_rise_at(cell: Vector2i) -> Terrain.RampRise:
	return _ramps.get(cell, Terrain.RampRise.NONE)

func is_ramp(cell: Vector2i) -> bool:
	return ramp_rise_at(cell) != Terrain.RampRise.NONE

# The one writer. Defaults are PRUNED rather than stored so to_dict stays sparse and two boards
# painted to the same shape compare equal regardless of how they got there.
func set_cell(cell: Vector2i, elevation: int, rise: Terrain.RampRise = Terrain.RampRise.NONE) -> void:
	var previous := elevation_at(cell)
	if elevation == 0:
		_elevations.erase(cell)
	else:
		_elevations[cell] = elevation
	if rise == Terrain.RampRise.NONE:
		_ramps.erase(cell)
	else:
		_ramps[cell] = rise
	dirty.mark(cell)
	# Lowering is answered in place; only RAISING the cell that WAS the floor can move it, and only
	# a rescan knows where to. Both branches, or a dip filled back in leaves every column reaching
	# down to a floor nothing sits on.
	if elevation < _lowest:
		_lowest = elevation
	elif previous == _lowest and elevation > previous:
		_lowest_stale = true

func clear() -> void:
	_elevations.clear()
	_ramps.clear()
	dirty.mark_all()
	_lowest = 0
	_lowest_stale = false

# The lowest elevation anywhere on the board, which is 0 or below: an ABSENT cell is elevation 0
# (see elevation_at), so a board with nothing painted -- and any board with one unpainted cell --
# genuinely has 0 as its minimum. That is why the scan starts at 0 rather than clamping afterwards.
func lowest_elevation() -> int:
	if _lowest_stale:
		_lowest = 0
		for cell: Vector2i in _elevations:
			_lowest = mini(_lowest, _elevations[cell])
		_lowest_stale = false
	return _lowest

# Elevation goes with the ground (#260), the rule TerrainStateManager.prune_groundless already holds
# for tile states: a height under no tile is junk that resurrects the moment ground is repainted
# there, and it rides every save in the meantime. A SWEEP for the same reason that one is -- the
# brush erases one cell, resize_map clears and repaints a whole rectangle. Returns whether anything
# went, so a caller can skip its redraw.
#
# The predicate is a PARAMETER rather than an injected ground_source field like that sibling's: it
# needs one because attacks deposit states from many sites, while this store has one writer and one
# pruner, both of which can reach GridUtils.has_ground from where they stand.
func prune_groundless(has_ground: Callable) -> bool:
	var doomed: Array[Vector2i] = []
	for cell in painted_cells():
		var grounded: bool = has_ground.call(cell)   # typed local: .call() erases to Variant
		if not grounded:
			doomed.append(cell)
	for cell in doomed:
		set_cell(cell, 0, Terrain.RampRise.NONE)
	return not doomed.is_empty()

# Every cell carrying a non-default value -- what a dev readout or a renderer iterates. Ramp cells
# at elevation 0 are legal and must not be missed, so both stores contribute.
func painted_cells() -> Array[Vector2i]:
	var seen: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in _elevations:
		seen[cell] = true
	for cell: Vector2i in _ramps:
		seen[cell] = true
	var result: Array[Vector2i] = []
	result.assign(seen.keys())
	return result

# Serialization pair, mirroring TerrainStateManager.to_state_dict / load_state_dict exactly. Two
# plain Dictionaries because that is what ScenarioData can @export; the typed views above are the
# only way the rest of the game reads them.
func to_elevation_dict() -> Dictionary:
	return _elevations.duplicate()

func to_ramp_dict() -> Dictionary:
	return _ramps.duplicate()

func load_dicts(elevations: Dictionary, ramps: Dictionary) -> void:
	clear()
	for cell: Vector2i in elevations:
		var height: int = elevations[cell]
		if height != 0:
			_elevations[cell] = height
	for cell: Vector2i in ramps:
		var rise: Terrain.RampRise = ramps[cell]
		if rise != Terrain.RampRise.NONE:
			_ramps[cell] = rise
	# These write the stores DIRECTLY rather than through set_cell (a load restores a result, it
	# does not replay edits), so the floor cache has to be invalidated by hand. clear() above
	# already marked the dirty set.
	_lowest_stale = true
