extends Node
class_name TerrainStateManager

# The dynamic per-cell tile-state store (#50). Distinct from the static TileMapLayer custom
# data (walkable / move_cost / terrain_type — authored board content): this holds the states
# attacks DEPOSIT and reactions READ (BURNING, ...). Round-trips through ScenarioData.tile_data
# and is drawn by OverlayManager — both wired in a later slice. docs/design/terrain.md.

var _states: Dictionary = {}   # Vector2i -> Array[Terrain.TileState]

func states_at(cell: Vector2i) -> Array[Terrain.TileState]:
	var result: Array[Terrain.TileState] = []
	if _states.has(cell):
		result.assign(_states[cell])
	return result

func has_state(cell: Vector2i, state: Terrain.TileState) -> bool:
	return _states.has(cell) and _states[cell].has(state)

# Play back one resolved cell effect (R3). Remove-then-add, mirroring how AttackAction.execute
# applies unit state deltas. Empties are pruned so an untouched cell never holds a stale entry.
func apply(effect: ResolvedCellEffect) -> void:
	var current: Array[Terrain.TileState] = []
	if _states.has(effect.cell):
		current.assign(_states[effect.cell])
	for s in effect.states_removed:
		current.erase(s)
	for s in effect.states_added:
		if not current.has(s):
			current.append(s)
	if current.is_empty():
		_states.erase(effect.cell)
	else:
		_states[effect.cell] = current

func clear() -> void:
	_states.clear()
	
func cells_with(state: Terrain.TileState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in _states:
		if _states[cell].has(state):
			result.append(cell)
	return result
