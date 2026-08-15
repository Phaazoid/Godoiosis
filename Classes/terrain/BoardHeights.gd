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
	if elevation == 0:
		_elevations.erase(cell)
	else:
		_elevations[cell] = elevation
	if rise == Terrain.RampRise.NONE:
		_ramps.erase(cell)
	else:
		_ramps[cell] = rise

func clear() -> void:
	_elevations.clear()
	_ramps.clear()

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
