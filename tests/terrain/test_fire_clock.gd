# #890: a fire lasts as long as its FUEL, and the fuel is the ground. The clock moved off the state
# (a STATE_DURATIONS table keyed by TileState) and onto the ignition reaction the ground carries,
# which is what let BLAZE retire -- "a fire that never goes out" is now BURNING on ground that is
# not fuel, not a second enum member.
#
# Successor to test_blaze.gd. Pure store, headless, no board: the fixture says what the ground is
# made of and the store asks it. Durations derive from the FIXTURE's dial, never a literal and
# never the authored one -- these cases are about the mechanism. The one case that does read
# authored content is the last, and it reads it as a QUESTION (does grass carry a clock at all)
# rather than pinning the number.
extends GdUnitTestSuite

const T := preload("res://tests/support/terrain_fixtures.gd")

const CELL := Vector2i(1, 0)


func _deposit(store: TerrainStateManager, cell: Vector2i, state: Terrain.TileState) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([state])
	store.apply(effect)


# THE FORK, in one case: identical deposits, different ground, opposite outcomes. Split across two
# suites it would be two facts; here it is the rule.
func test_the_same_fire_goes_out_on_fuel_and_never_does_on_stone() -> void:
	var grass: TerrainStateManager = auto_free(T.store_on_fuel())
	add_child(grass)
	var stone: TerrainStateManager = auto_free(T.store_on_stone())
	add_child(stone)
	_deposit(grass, CELL, Terrain.TileState.BURNING)
	_deposit(stone, CELL, Terrain.TileState.BURNING)
	for _i in range(T.FUEL_TURNS * 2):
		grass.tick_states()
		stone.tick_states()
	assert_bool(grass.has_state(CELL, Terrain.TileState.BURNING)) \
		.override_failure_message("fire on fuel outlived the fuel") \
		.is_false()
	assert_bool(stone.has_state(CELL, Terrain.TileState.BURNING)) \
		.override_failure_message("fire on ground that is not fuel burned out anyway -- the clock is coming from somewhere other than the ground") \
		.is_true()


# The variable half of the ruling: two grounds, two clocks, neither of them a constant anywhere in
# the code. A single shared duration would pass every OTHER case in this file.
func test_each_ground_burns_for_its_own_clock() -> void:
	var slow: TerrainStateManager = auto_free(T.store_on_fuel(T.FUEL_TURNS))
	add_child(slow)
	var quick: TerrainStateManager = auto_free(T.store_on_fuel(1))
	add_child(quick)
	_deposit(slow, CELL, Terrain.TileState.BURNING)
	_deposit(quick, CELL, Terrain.TileState.BURNING)
	quick.tick_states()
	slow.tick_states()
	assert_bool(quick.has_state(CELL, Terrain.TileState.BURNING)) \
		.override_failure_message("the one-turn ground burned longer than the clock it authored") \
		.is_false()
	assert_bool(slow.has_state(CELL, Terrain.TileState.BURNING)) \
		.override_failure_message("both grounds burned out together -- the clock is not per-ground") \
		.is_true()


func test_the_hover_clock_reads_the_grounds_number_and_stone_reports_none() -> void:
	# turns_remaining is the readout's read, and -1 is its "no clock here" answer. A permanent fire
	# must report -1 rather than a number the player would watch fail to count down.
	var grass: TerrainStateManager = auto_free(T.store_on_fuel())
	add_child(grass)
	var stone: TerrainStateManager = auto_free(T.store_on_stone())
	add_child(stone)
	_deposit(grass, CELL, Terrain.TileState.BURNING)
	_deposit(stone, CELL, Terrain.TileState.BURNING)
	assert_int(grass.turns_remaining(CELL, Terrain.TileState.BURNING)).is_equal(T.FUEL_TURNS)
	assert_int(stone.turns_remaining(CELL, Terrain.TileState.BURNING)).is_equal(-1)


func test_a_loaded_fire_on_stone_arms_no_clock() -> void:
	# The contrast to test_burnout's loaded-fire-gets-a-fresh-timer: on stone there is no timer to
	# arm, so a saved board's standing fires are still standing after any number of rounds.
	var src: TerrainStateManager = auto_free(T.store_on_stone())
	add_child(src)
	_deposit(src, CELL, Terrain.TileState.BURNING)

	var dst: TerrainStateManager = auto_free(T.store_on_stone())
	add_child(dst)
	dst.load_state_dict(src.to_state_dict())
	for _i in range(T.FUEL_TURNS * 2):
		dst.tick_states()
	assert_bool(dst.has_state(CELL, Terrain.TileState.BURNING)).is_true()


func test_is_burning_answers_for_fire_and_no_others() -> void:
	var bare: Array[Terrain.TileState] = []
	var cold: Array[Terrain.TileState] = [Terrain.TileState.FROZEN, Terrain.TileState.COVER]
	var burning: Array[Terrain.TileState] = [Terrain.TileState.COVER, Terrain.TileState.BURNING]
	assert_bool(Terrain.is_burning(bare)).is_false()
	assert_bool(Terrain.is_burning(cold)).is_false()
	assert_bool(Terrain.is_burning(burning)).is_true()


func test_burning_cells_lists_a_cell_once() -> void:
	var store: TerrainStateManager = auto_free(T.store_on_fuel())
	add_child(store)
	_deposit(store, CELL, Terrain.TileState.BURNING)
	_deposit(store, CELL, Terrain.TileState.COVER)   # a dug-in cell can also be alight
	_deposit(store, Vector2i(4, 0), Terrain.TileState.FROZEN)
	assert_array(store.burning_cells()).contains_exactly([CELL])


# The tombstone gate. BLAZE stays in the enum because it serializes as a plain int, so the one door
# it can still arrive through is a board saved before #890 -- and load_state_dict is where it dies,
# rather than at each of the readers downstream.
func test_a_retired_state_never_survives_a_load() -> void:
	var store: TerrainStateManager = auto_free(T.store_on_stone())
	add_child(store)
	var old_save := {CELL: [Terrain.TileState.BLAZE, Terrain.TileState.COVER]}
	store.load_state_dict(old_save)
	assert_bool(store.has_state(CELL, Terrain.TileState.BLAZE)) \
		.override_failure_message("a retired state came back off an old save and is now live on the board") \
		.is_false()
	assert_bool(store.has_state(CELL, Terrain.TileState.COVER)) \
		.override_failure_message("dropping the retired state took its cell-mates with it") \
		.is_true()


# The CONTENT case, and the only one here that reads authored files: every ground the shipped
# reactions declare flammable must also declare how long it burns. Omitting the clock is legal
# GDScript and legal .tres -- it means "burns forever" -- so a grass field that never goes out
# would ship silently. Asks WHETHER, never how much: the number is a tuning dial.
func test_every_shipped_flammable_ground_authors_a_burn_clock() -> void:
	var reactions := TerrainReactionCatalog.get_all()
	var checked := 0
	for reaction in reactions:
		if reaction.incoming_element != Elemental.Element.FIRE \
				or not reaction.add_tile_states.has(Terrain.TileState.BURNING):
			continue
		checked += 1
		assert_bool(reaction.add_state_turns.has(Terrain.TileState.BURNING)) \
			.override_failure_message("an ignition reaction for %s authors no burn clock, so fire on that ground would never go out"
				% Terrain.Kind.keys()[reaction.required_kind]) \
			.is_true()
	assert_int(checked) \
		.override_failure_message("no ignition reactions found at all -- this case would pass vacuously") \
		.is_greater(0)
