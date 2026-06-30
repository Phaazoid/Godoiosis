extends Node
class_name TerrainStateManager

# The dynamic per-cell tile-state store (#50). Distinct from the static TileMapLayer custom
# data (walkable / move_cost / terrain_type — authored board content): this holds the states
# attacks DEPOSIT and reactions READ (BURNING, ...). Round-trips through
# ScenarioData.terrain_states; drawn by OverlayManager.

const STATE_DURATIONS := {
	Terrain.TileState.BURNING: 3,
	Terrain.TileState.FROZEN: 3,
}

var _states: Dictionary = {}        # Vector2i -> Array[Terrain.TileState]
var _state_turns: Dictionary = {}   # Vector2i -> { Terrain.TileState: turns_left }

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
	for s in effect.states_removed:
		_clear_timer(effect.cell, s)
	for s in effect.states_added:
		if STATE_DURATIONS.has(s):
			_start_timer(effect.cell, s)

func clear() -> void:
	_states.clear()
	_state_turns.clear()

func to_state_dict() -> Dictionary:
	return _states.duplicate(true)

func load_state_dict(data: Dictionary) -> void:
	_states.clear()
	_state_turns.clear()
	for cell in data:
		var states: Array[Terrain.TileState] = []
		states.assign(data[cell])
		if not states.is_empty():
			_states[cell] = states
			for s in states:
				if STATE_DURATIONS.has(s):
					_start_timer(cell, s)

func cells_with(state: Terrain.TileState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in _states:
		if _states[cell].has(state):
			result.append(cell)
	return result

func tick_states() -> void:
	for cell in _state_turns.keys():
		for state in _state_turns[cell].keys():
			_state_turns[cell][state] -= 1
			if _state_turns[cell][state] <= 0:
				_remove_state(cell, state)

func _start_timer(cell: Vector2i, state: Terrain.TileState) -> void:
	if not _state_turns.has(cell):
		_state_turns[cell] = {}
	_state_turns[cell][state] = STATE_DURATIONS[state]

func _clear_timer(cell: Vector2i, state: Terrain.TileState) -> void:
	if _state_turns.has(cell):
		_state_turns[cell].erase(state)
		if _state_turns[cell].is_empty():
			_state_turns.erase(cell)

func _remove_state(cell: Vector2i, state: Terrain.TileState) -> void:
	_clear_timer(cell, state)
	if _states.has(cell):
		_states[cell].erase(state)
		if _states[cell].is_empty():
			_states.erase(cell)
