extends Node
class_name TerrainStateManager

# The dynamic per-cell tile-state store (#50). Distinct from the static TileMapLayer custom
# data (walkable / move_cost / terrain_type — authored board content): this holds the states
# attacks DEPOSIT and reactions READ (BURNING, ...). Round-trips through
# ScenarioData.terrain_states; drawn by OverlayManager.

# Injectable "does this cell have ground?" (#245) -- the GridUtils.has_ground shape, wired at the
# two construction sites (game.gd and play/board_builder.gd). A tile state modifies what happens
# when a unit WALKS on a tile, so a cell with no tile has nothing to modify (dev ruling).
# This store is the ONE seam every deposit passes through -- three producers (PlanResolver,
# SquadManager's Burrow COVER, the dev brush) and three appliers (OrderExecutor, PlaySession, the
# brush) -- so the rule lives here rather than in six places that would drift.
# Unset = no judgement, NOT "no ground": a bare store built without a board still accepts
# everything, which is what the headless terrain fixtures rely on.
var ground_source: Callable

# Injectable "what does fire consume on this cell?" (#890) -- the ground's ignition reaction, or
# null where the ground is not fuel. Composed by TerrainReactionCatalog.fuel_source_for and wired
# at the same two construction sites as ground_source above.
#
# It replaced a STATE_DURATIONS table that lived here. A tile state's clock is not a property of
# the STATE, it is a property of what is burning: grass carries 3, tall grass will carry less, and
# the flagstone under a brazier carries none at all, so the fire on it never runs out. Deleting the
# table rather than demoting it to a default is deliberate (dev, 2026-09-10) -- both live
# construction sites wire this, so a fallback would have been a constant only tests could reach.
#
# Unset = nothing has a clock, which is the honest reading for a bare store built with no board:
# it cannot know what any cell is made of, so it must not invent a duration.
var fuel_source: Callable

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
	var current := fold(states_at(effect.cell), effect, grounded)
	if current.is_empty():
		_states.erase(effect.cell)
	else:
		_states[effect.cell] = current
	for s in effect.states_removed:
		_clear_timer(effect.cell, s)
	if grounded:
		for s in effect.states_added:
			_start_timer(effect.cell, s)

# The remove-then-add fold one effect makes to a state list — apply()'s rule, shared so a PENDING
# deposit reads exactly as the applied one will (#419).
static func fold(states: Array[Terrain.TileState], effect: ResolvedCellEffect,
		grounded := true) -> Array[Terrain.TileState]:
	var result := states.duplicate()
	for s in effect.states_removed:
		result.erase(s)
	if grounded:
		for s in effect.states_added:
			if not result.has(s):
				result.append(s)
	return result


# A cell's states with this pass's own deposits folded in — what the END OF TURN forecast reads,
# since cell effects only reach the store at execution (#419).
func projected_states_at(cell: Vector2i, effects: Array[ResolvedCellEffect]) -> Array[Terrain.TileState]:
	var states := states_at(cell)
	var grounded := _has_ground(cell)
	for effect in effects:
		if effect.cell == cell:
			states = fold(states, effect, grounded)
	return states


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

# The live clocks, so a mid-battle save puts a fire back where it had got to (#890). A SECOND dict
# beside the states rather than a richer one: the state dict is authored by hand in a mission .tres
# and read by the brush, and re-shaping it to carry a countdown would rewrite content to record
# something no author sets.
#
# A cell whose fire has no clock (ground that is not fuel) contributes nothing here, which is what
# lets load_state_dict tell "this save knew of no clock" from "this save recorded a permanent fire"
# without a sentinel -- see there.
func to_turns_dict() -> Dictionary:
	return _state_turns.duplicate(true)

func load_state_dict(data: Dictionary, turns: Dictionary = {}) -> void:
	_states.clear()
	_state_turns.clear()
	for cell in data:
		var states: Array[Terrain.TileState] = []
		states.assign(data[cell])
		# A board saved before #890 can carry a retired state (BLAZE). Dropped HERE, at the only
		# door one can arrive through, rather than guarded at each of the readers downstream --
		# the hover card, the glossary bridge, the icon table -- none of which should have to know
		# the enum has tombstones in it.
		for retired in Terrain.RETIRED_STATES:
			states.erase(retired)
		if not states.is_empty():
			_states[cell] = states
			for s in states:
				_restore_timer(cell, s, turns)

func cells_with(state: Terrain.TileState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in _states:
		if _states[cell].has(state):
			result.append(cell)
	return result

# Every cell on fire, each listed ONCE. Terrain.FIRE_STATES is a single member again since #890
# retired BLAZE, so the de-duplication has nothing to do today -- it stays because the ONCE is the
# contract the end-of-turn burn relies on, and it must not become a bug the day fire grows a
# second spelling again.
func burning_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in _states:
		if Terrain.is_burning(states_at(cell)):
			result.append(cell)
	return result

# Public read of a ticking state's clock at one cell — -1 when it has no timer there (the state is
# permanent — COVER, or fire on ground that is not fuel — or simply absent). The hover readout is
# the first reader.
func turns_remaining(cell: Vector2i, state: Terrain.TileState) -> int:
	if _state_turns.has(cell) and _state_turns[cell].has(state):
		return _state_turns[cell][state]
	return -1

# The turn tick (#890): fire SPREADS, clocks run down, and burnt-out fuel SCORCHES. One function,
# because the three are one moment and their ORDER is the rule.
#
#   1. Read what fire takes BEFORE anything moves, so a fire on its last turn still passes the
#      flame on -- otherwise a front strands itself one cell short of the fuel it was reaching for.
#   2. Run the clocks down. Where fire leaves ground that WAS fuel, leave SCORCHED behind.
#   3. Only THEN light what step 1 chose, each cell taking ITS OWN ground's clock -- deposited
#      after the tick so a fire never loses a turn on the round it catches.
#
# Called once per ROUND (TurnManager.round_completed -> game._on_round_completed), which is after
# every faction's end-of-turn burn. That is what keeps Law #2: no spread can land between the
# queue's forecast of a tile hit and the pass that pays it.
func tick_states() -> void:
	var taken := _cells_fire_takes()
	for cell in _state_turns.keys():
		for state in _state_turns[cell].keys():
			_state_turns[cell][state] -= 1
			if _state_turns[cell][state] <= 0:
				_burn_out(cell, state)
	for cell in taken:
		_deposit(cell, Terrain.TileState.BURNING)


# Which cells fire takes this round, each burning cell reaching as far as ITS OWN ground throws
# (#891) -- the four sides, or the corners too where the fuel says so.
#
# cells_within_blended_range(cell, 1, and_a_half) is the reach, not a list of neighbour vectors:
# aiming already answers "sides, or sides and corners" for every attack in the game
# (AttackData.max_and_a_half), and a second answer to it here is the duplicate seam Law #4 is about.
# It hands back the ORIGIN as well, which costs nothing and cannot go wrong by construction -- every
# source comes from burning_cells(), and _catches_fire refuses a cell that is alight.
func _cells_fire_takes() -> Array[Vector2i]:
	var taken: Array[Vector2i] = []
	for source in burning_cells():
		for cell in GridUtils.cells_within_blended_range(source, 1, _spreads_wide(source)):
			if not taken.has(cell) and _catches_fire(cell):
				taken.append(cell)
	return taken


# Does the fire standing HERE throw to the corners? Asked of the burning cell's own ground, which is
# the whole of the rule: a taller flame reaches further, so tall grass carries fire diagonally into
# whatever is beside it while ordinary grass does not take a corner however flammable it is.
#
# Ground that is not fuel answers false -- a brazier on flagstone is consuming nothing, so there is
# nothing to tell it to throw wide.
func _spreads_wide(cell: Vector2i) -> bool:
	var fuel := _fuel_at(cell)
	return fuel != null and fuel.spread_and_a_half


# Would fire take this cell? Its ground must be fuel AND must admit fire in the state it is
# currently holding -- which is what refuses SCORCHED, and refuses it identically to a direct hit,
# since both ask the same authored clause.
#
# A cell ALREADY ALIGHT is never taken, and that exclusion carries TWO rules rather than being an
# optimisation. Two burning neighbours would otherwise restoke each other every round through
# apply()'s timer reset, and no field would ever go out however much of it had already burnt. Since
# #891 it is also what drops the ORIGIN out of _cells_fire_takes' reach, every source there being a
# burning cell by construction -- so a fire cannot re-light itself and lose its own clock.
func _catches_fire(cell: Vector2i) -> bool:
	if Terrain.is_burning(states_at(cell)) or not _has_ground(cell):
		return false
	var fuel := _fuel_at(cell)
	return fuel != null and fuel.admits(states_at(cell))


# A state whose clock has run out. Fire that was consuming FUEL leaves the spent ground behind it;
# fire on ground that was never fuel has consumed nothing, so there is nothing to leave -- and it
# never reaches here anyway, having no clock to run out.
func _burn_out(cell: Vector2i, state: Terrain.TileState) -> void:
	_remove_state(cell, state)
	if state == Terrain.TileState.BURNING and _fuel_at(cell) != null:
		_deposit(cell, Terrain.TileState.SCORCHED)


# Through apply(), never straight into the dictionaries: it is the ONE deposit seam, so a state this
# store lays down itself is grounded, timed and pruned by exactly the rules a fireball's would be.
func _deposit(cell: Vector2i, state: Terrain.TileState) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([state])
	apply(effect)

# Give a freshly deposited state its clock, IF its ground gives it one. The single place that
# question is asked, so every deposit path -- the resolver, the dev brush, a load -- reads the same
# answer. No entry for this state (or no fuel at all) means no timer, which is the permanence COVER
# and FROZEN have always had and which BLAZE used to need a second enum member for.
func _start_timer(cell: Vector2i, state: Terrain.TileState) -> void:
	var fuel := _fuel_at(cell)
	if fuel == null or not fuel.add_state_turns.has(state):
		return
	if not _state_turns.has(cell):
		_state_turns[cell] = {}
	_state_turns[cell][state] = fuel.add_state_turns[state]


# A loaded state's clock: the SAVED remainder where the save recorded one, and otherwise whatever
# this cell's ground would give a fresh deposit.
#
# NO SENTINEL is needed to tell the two apart, and that falls out of the model rather than being
# arranged: a save written before #890's clocks recorded nothing at all, so every fire in it lands
# on the fresh-clock branch, which is exactly the old behaviour; and a fire that was permanent when
# saved has no entry either, but its ground gives no clock, so the fresh branch answers permanent
# too. The only thing an entry can mean is a countdown mid-flight.
func _restore_timer(cell: Vector2i, state: Terrain.TileState, turns: Dictionary) -> void:
	if not turns.has(cell) or not (turns[cell] as Dictionary).has(state):
		_start_timer(cell, state)
		return
	if not _state_turns.has(cell):
		_state_turns[cell] = {}
	_state_turns[cell][state] = turns[cell][state]


func _fuel_at(cell: Vector2i) -> TerrainReaction:
	if not fuel_source.is_valid():
		return null
	var fuel: TerrainReaction = fuel_source.call(cell)   # typed local: .call() erases to Variant
	return fuel

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
