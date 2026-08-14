extends Node
class_name TerrainStateManager

# The dynamic per-cell tile-state store (#50). Distinct from the static TileMapLayer custom
# data (walkable / move_cost / terrain_type — authored board content): this holds the states
# attacks DEPOSIT and reactions READ (BURNING, ...). Round-trips through
# ScenarioData.terrain_states; drawn by OverlayManager.

const STATE_DURATIONS := {
	Terrain.TileState.BURNING: 3,
}

# Injectable "does this cell have ground?" (#245) -- the GridUtils.has_ground shape, wired at the
# two construction sites (game.gd and play/board_builder.gd). A tile state modifies what happens
# when a unit WALKS on a tile, so a cell with no tile has nothing to modify (dev ruling).
# This store is the ONE seam every deposit passes through -- three producers (PlanResolver,
# SquadManager's Burrow COVER, the dev brush) and three appliers (OrderExecutor, PlaySession, the
# brush) -- so the rule lives here rather than in six places that would drift.
# Unset = no judgement, NOT "no ground": a bare store built without a board still accepts
# everything, which is what the headless terrain fixtures rely on.
var ground_source: Callable

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
	# Deposits onto a groundless cell are DROPPED; removals always run. The asymmetry is the point:
	# a cell whose tile was just erased still has to be cleanable, and routing that through here
	# keeps the timer bookkeeping below correct instead of needing a second back door.
	var grounded := _has_ground(effect.cell)
	var current: Array[Terrain.TileState] = []
	if _states.has(effect.cell):
		current.assign(_states[effect.cell])
	for s in effect.states_removed:
		current.erase(s)
	if grounded:
		for s in effect.states_added:
			if not current.has(s):
				current.append(s)
	if current.is_empty():
		_states.erase(effect.cell)
	else:
		_states[effect.cell] = current
	for s in effect.states_removed:
		_clear_timer(effect.cell, s)
	if grounded:
		for s in effect.states_added:
			if STATE_DURATIONS.has(s):
				_start_timer(effect.cell, s)

func _has_ground(cell: Vector2i) -> bool:
	if not ground_source.is_valid():
		return true
	var grounded: bool = ground_source.call(cell)   # typed local: .call() erases to Variant
	return grounded

# Drop every state whose cell no longer has ground, through apply() so the timers unwind exactly as
# they would on any other removal. Returns whether anything went, so a caller can skip its redraw.
#
# A SWEEP rather than a per-cell clear because there is more than one way to take ground away: the
# brush erases one cell, and resize_map calls grid.clear() and repaints a whole new rectangle. A
# targeted clear has to be remembered correctly at each site; this only has to be called.
func prune_groundless() -> bool:
	var doomed: Array[Vector2i] = []
	for cell: Vector2i in _states.keys():
		if not _has_ground(cell):
			doomed.append(cell)
	for cell in doomed:
		var effect := ResolvedCellEffect.new()
		effect.cell = cell
		effect.states_removed.assign(states_at(cell))
		apply(effect)
	return not doomed.is_empty()

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

# Every cell on fire, each listed ONCE -- a cell can legally hold both fire states (painted
# BLAZE, then a fireball lands), and the end-of-turn burn must not damage its occupant twice.
func burning_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in _states:
		if Terrain.is_burning(states_at(cell)):
			result.append(cell)
	return result

# Public read of a ticking state's clock at one cell — -1 when it has no timer there (the state
# is permanent, like COVER/BLAZE, or simply absent). The hover readout is the first reader.
func turns_remaining(cell: Vector2i, state: Terrain.TileState) -> int:
	if _state_turns.has(cell) and _state_turns[cell].has(state):
		return _state_turns[cell][state]
	return -1

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
