extends RefCounted
class_name BoardHeights

# The per-cell ground-geometry store (#218/#257, re-shaped by #427) — FOUR CORNER HEIGHTS per cell,
# in units where one level is 2 (Terrain.UNITS_PER_LEVEL). Sibling of TerrainStateManager: same
# per-cell shape, same round-trip through ScenarioData, same role in BoardContext. Canon:
# docs/design/verticality.md.
#
# Corners are per-TILE, not a shared vertex grid: two neighbours may disagree about the edge they
# meet on, and that disagreement IS a cliff. A shared grid could not express two flat cells at
# different heights at all.
#
# elevation_at / ramp_rise_at are DERIVED from the corners rather than stored beside them — one
# question, one answer. That is what lets every rule and every renderer keep reading exactly what
# they read before the shape changed.
#
# NOT tileset custom data, unlike walkable / move_cost / terrain_type. Those are per-TILE (per atlas
# coordinate), so an elevation among them would need a distinct grass tile per level -- 21 of them
# for a 20-level cliff city -- and a Tile Brush palette to match. Per-cell also means the rules can
# be tested on any painted board with no new tiles or art.
#
# NOT folded into TerrainStateManager either: that holds a STACK of enum states with durations, this
# holds geometry, and height is authored map geometry rather than something attacks deposit. It is
# deliberately not assumed permanent, though -- terrain.md's "attack the map" list already carries
# EARTH raising a destructible wall.
#
# RefCounted rather than TerrainStateManager's Node: no signals, no _process, nothing needing the
# tree, and a RefCounted frees itself instead of reading as a gdUnit orphan.

# Vector4i and not a packed array: a packed array is a REFERENCE type, so a read would hand out this
# store's own object and any caller mutating it would silently edit the board (#447's aliasing bug).
var _corners: Dictionary[Vector2i, Vector4i] = {}

# Which cells changed since the 3D mirror last reconciled (#319) — the BoardGrid.dirty twin, same
# single-consumer contract. Height is terrain to the mirror: it decides how tall a column is drawn,
# so a height edit has to reach it exactly the way a repaint does.
var dirty := DirtyCells.new()

# The board's lowest painted corner, CACHED. BoardMirror needs it per sync (every column reaches
# down to a shared floor, or a dip would be a hole) and re-deriving it walked painted_cells() each
# time -- O(board) on a fully-painted board, in the frame path this ticket exists to empty.
# Recomputed lazily and only when a write could have RAISED it; a write that lowers it is answered
# in place.
var _lowest := 0
var _lowest_stale := false

# An ABSENT cell is flat at height 0, and that is a decision rather than a gap: a flat board is the
# overwhelmingly common case, so it is stored as nothing at all. This method is the ONE place that
# default is applied -- no caller re-derives it, and no caller reads the dictionary directly.
func corners_at(cell: Vector2i) -> Vector4i:
	return _corners.get(cell, Vector4i.ZERO)

# A cell's single rule-height is its LOW side (verticality.md, DECIDED) — which for a flat cell is
# its level and for a ramp is the floor it connects upward from.
func elevation_at(cell: Vector2i) -> int:
	var c := corners_at(cell)
	return mini(mini(c.x, c.y), mini(c.z, c.w))

func ramp_rise_at(cell: Vector2i) -> Terrain.RampRise:
	return Terrain.rise_of_corners(corners_at(cell))

func is_ramp(cell: Vector2i) -> bool:
	return ramp_rise_at(cell) != Terrain.RampRise.NONE

# The one writer. A flat cell at height 0 is PRUNED rather than stored so to_corner_dict stays
# sparse and two boards painted to the same shape compare equal regardless of how they got there.
func set_corners(cell: Vector2i, corners: Vector4i) -> void:
	var previous := elevation_at(cell)
	if corners == Vector4i.ZERO:
		_corners.erase(cell)
	else:
		_corners[cell] = corners
	dirty.mark(cell)
	# Lowering is answered in place; only RAISING the cell that WAS the floor can move it, and only
	# a rescan knows where to. Both branches, or a dip filled back in leaves every column reaching
	# down to a floor nothing sits on.
	var lowest := elevation_at(cell)
	if lowest < _lowest:
		_lowest = lowest
	elif previous == _lowest and lowest > previous:
		_lowest_stale = true

# The cardinal-shape composer: what the brush authors and what every fixture builds. Not a second
# store — it writes through set_corners — but the shape most callers actually mean.
func set_cell(cell: Vector2i, elevation: int, rise: Terrain.RampRise = Terrain.RampRise.NONE) -> void:
	set_corners(cell, Terrain.corners_of_ramp(elevation, rise))

func clear() -> void:
	_corners.clear()
	dirty.mark_all()
	_lowest = 0
	_lowest_stale = false

# The lowest corner anywhere on the board, which is 0 or below: an ABSENT cell is flat at 0 (see
# corners_at), so a board with nothing painted -- and any board with one unpainted cell -- genuinely
# has 0 as its minimum. That is why the scan starts at 0 rather than clamping afterwards.
func lowest_elevation() -> int:
	if _lowest_stale:
		_lowest = 0
		for cell: Vector2i in _corners:
			var c: Vector4i = _corners[cell]
			_lowest = mini(_lowest, mini(mini(c.x, c.y), mini(c.z, c.w)))
		_lowest_stale = false
	return _lowest

# Height goes with the ground (#260), the rule TerrainStateManager.prune_groundless already holds
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
		set_corners(cell, Vector4i.ZERO)
	return not doomed.is_empty()

# Every cell carrying a non-default shape -- what a dev readout or a renderer iterates. One store
# since #427: a ramp at height 0 has corners (0,0,2,2), which is not flat, so it is here on its own.
func painted_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(_corners.keys())
	return result

# Serialization pair, mirroring TerrainStateManager.to_state_dict / load_state_dict exactly. A plain
# Dictionary because that is what ScenarioData can @export; the typed view above is the only way the
# rest of the game reads it.
func to_corner_dict() -> Dictionary:
	return _corners.duplicate()

func load_corner_dict(corners: Dictionary) -> void:
	clear()
	for cell: Vector2i in corners:
		var value: Vector4i = corners[cell]
		if value != Vector4i.ZERO:
			_corners[cell] = value
	# This writes the store DIRECTLY rather than through set_corners (a load restores a result, it
	# does not replay edits), so the floor cache has to be invalidated by hand. clear() above
	# already marked the dirty set.
	_lowest_stale = true
