# #890: a burning tile takes its flammable neighbours, one step per round, and leaves SCORCHED
# ground behind it that fire can never take again.
#
# The whole step is pure over (burning set, ground), so it tests headlessly with no board -- the
# fixture says what the ground is made of and the store asks it. Durations derive from the
# fixture's dial, never a literal.
#
# The ORDER inside tick_states is the rule, and three cases below exist only to pin it: the take is
# read BEFORE the clocks run (a fire on its last round still passes the flame on), the deposit
# happens AFTER (a fresh catch does not lose a turn), and a cell already alight is never taken
# (or two neighbours restoke each other for ever).
extends GdUnitTestSuite

const T := preload("res://tests/support/terrain_fixtures.gd")

const HERE := Vector2i(3, 3)


func _deposit(store: TerrainStateManager, cell: Vector2i, state: Terrain.TileState) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([state])
	store.apply(effect)


func _burning(store: TerrainStateManager) -> Array[Vector2i]:
	var cells := store.burning_cells()
	cells.sort()
	return cells


func test_fire_takes_its_four_cardinal_neighbours_and_no_diagonal() -> void:
	var store: TerrainStateManager = auto_free(T.store_on_fuel())
	add_child(store)
	_deposit(store, HERE, Terrain.TileState.BURNING)
	store.tick_states()
	# The SET is the rule, never the order -- burning_cells walks a Dictionary.
	assert_array(_burning(store)) \
		.override_failure_message("the front is not the four cardinal neighbours plus the source") \
		.contains_exactly_in_any_order([
			HERE, HERE + Vector2i.UP, HERE + Vector2i.DOWN,
			HERE + Vector2i.LEFT, HERE + Vector2i.RIGHT])
	assert_bool(store.has_state(HERE + Vector2i(1, 1), Terrain.TileState.BURNING)) \
		.override_failure_message("fire went diagonally -- all eight is tall grass's, and #891's") \
		.is_false()


func test_fire_advances_one_tile_a_round_and_never_two() -> void:
	# A cell lit THIS tick must not be a source in the SAME tick, or a fire crosses the board in
	# one round. The snapshot at the top of tick_states is what stops it.
	var store: TerrainStateManager = auto_free(T.store_on_fuel())
	add_child(store)
	_deposit(store, HERE, Terrain.TileState.BURNING)
	store.tick_states()
	assert_bool(store.has_state(HERE + Vector2i(2, 0), Terrain.TileState.BURNING)) \
		.override_failure_message("fire reached two tiles out in one round") \
		.is_false()
	store.tick_states()
	assert_bool(store.has_state(HERE + Vector2i(2, 0), Terrain.TileState.BURNING)) \
		.override_failure_message("fire failed to reach two tiles out in two rounds") \
		.is_true()


func test_a_fire_on_its_last_round_still_passes_the_flame_on() -> void:
	# The take is read BEFORE the clocks run down. Reverse the two and a front strands itself one
	# cell short of the fuel it was reaching for, every time its clock happens to expire.
	var store: TerrainStateManager = auto_free(T.store_on_fuel(1))
	add_child(store)
	_deposit(store, HERE, Terrain.TileState.BURNING)
	store.tick_states()   # the source's one and only round: it goes out on this tick
	assert_bool(store.has_state(HERE, Terrain.TileState.BURNING)) \
		.override_failure_message("precondition: the source did not go out, so nothing below is about a LAST round") \
		.is_false()
	assert_bool(store.has_state(HERE + Vector2i.RIGHT, Terrain.TileState.BURNING)) \
		.override_failure_message("a fire on its last round took nothing with it") \
		.is_true()


func test_a_freshly_caught_cell_gets_a_whole_clock_and_not_a_short_one() -> void:
	# The deposit happens AFTER the tick. Deposited before it, a new catch would be decremented on
	# the round it caught and burn one round short for ever after.
	var store: TerrainStateManager = auto_free(T.store_on_fuel())
	add_child(store)
	_deposit(store, HERE, Terrain.TileState.BURNING)
	store.tick_states()
	assert_int(store.turns_remaining(HERE + Vector2i.RIGHT, Terrain.TileState.BURNING)) \
		.override_failure_message("a cell that caught this round was already one turn down") \
		.is_equal(T.FUEL_TURNS)


func test_fire_never_restokes_a_cell_that_is_already_alight() -> void:
	# Two burning neighbours. Without the already-alight exclusion each re-deposits into the other
	# every round, apply() resets the timer, and NO field ever goes out -- scorching or not.
	var store: TerrainStateManager = auto_free(T.store_on_fuel())
	add_child(store)
	_deposit(store, HERE, Terrain.TileState.BURNING)
	_deposit(store, HERE + Vector2i.RIGHT, Terrain.TileState.BURNING)
	for _i in range(T.FUEL_TURNS):
		store.tick_states()
	assert_bool(store.has_state(HERE, Terrain.TileState.BURNING)) \
		.override_failure_message("a pair of burning neighbours kept each other alight for ever") \
		.is_false()
	assert_bool(store.has_state(HERE + Vector2i.RIGHT, Terrain.TileState.BURNING)) \
		.override_failure_message("a pair of burning neighbours kept each other alight for ever") \
		.is_false()


# --- SCORCHED ------------------------------------------------------------------------------------

func test_fuel_that_burns_out_leaves_scorched_ground() -> void:
	var store: TerrainStateManager = auto_free(T.store_on_fuel())
	add_child(store)
	_deposit(store, HERE, Terrain.TileState.BURNING)
	for _i in range(T.FUEL_TURNS):
		store.tick_states()
	assert_bool(store.has_state(HERE, Terrain.TileState.SCORCHED)) \
		.override_failure_message("spent fuel left no mark, so fire can re-cross it") \
		.is_true()
	assert_int(store.turns_remaining(HERE, Terrain.TileState.SCORCHED)) \
		.override_failure_message("scorched ground was given a clock -- it must be permanent") \
		.is_equal(-1)


func test_ground_that_was_never_fuel_does_not_scorch() -> void:
	# A fire on flagstones consumed nothing, so there is nothing to leave behind. It also never
	# runs out, which is why this drives the burn-out door directly through a douse instead.
	var store: TerrainStateManager = auto_free(T.store_on_stone())
	add_child(store)
	_deposit(store, HERE, Terrain.TileState.BURNING)
	for _i in range(T.FUEL_TURNS * 2):
		store.tick_states()
	assert_bool(store.has_state(HERE, Terrain.TileState.SCORCHED)) \
		.override_failure_message("stone sooted up permanently for no rule reason") \
		.is_false()


func test_fire_never_takes_scorched_ground_again() -> void:
	# THE terminator. Without it a spreading fire re-crosses what it already burnt, for ever.
	var store: TerrainStateManager = auto_free(T.store_on_fuel())
	add_child(store)
	_deposit(store, HERE, Terrain.TileState.SCORCHED)
	_deposit(store, HERE + Vector2i.RIGHT, Terrain.TileState.BURNING)
	store.tick_states()
	assert_bool(store.has_state(HERE, Terrain.TileState.BURNING)) \
		.override_failure_message("fire took ground it had already burnt") \
		.is_false()
	assert_bool(store.has_state(HERE + Vector2i(2, 0), Terrain.TileState.BURNING)) \
		.override_failure_message("precondition: the source spread nowhere at all, so the case above proves nothing") \
		.is_true()


func test_a_field_of_fuel_burns_out_and_stays_out() -> void:
	# The property every other case here is in service of: a fire on a finite field SETTLES. Run it
	# far past any single clock and assert the board is quiet -- which is false under any of the
	# four mutants above, and is what makes The Dry Field a race rather than a foregone loss.
	#
	# BOUNDED deliberately: the two things that stop a fire are spent fuel and the edge of the
	# board, and an unbounded fixture has only the first, so an infinite plane of grass genuinely
	# burns for ever. That is the rule working, not a failure -- this case needs a field with an
	# edge to reach.
	var store: TerrainStateManager = auto_free(T.store_on_fuel_within(Rect2i(0, 0, 8, 8)))
	add_child(store)
	_deposit(store, HERE, Terrain.TileState.BURNING)
	for _i in range(40):
		store.tick_states()
	assert_array(store.burning_cells()) \
		.override_failure_message("the field was still alight after forty rounds -- the fire does not settle") \
		.is_empty()


# --- the clocks survive a save (#890, the dev's ask when the ticket was split) -------------------

func test_a_saved_fire_comes_back_where_it_had_got_to() -> void:
	var src: TerrainStateManager = auto_free(T.store_on_fuel())
	add_child(src)
	_deposit(src, HERE, Terrain.TileState.BURNING)
	src.tick_states()   # one round spent

	var dst: TerrainStateManager = auto_free(T.store_on_fuel())
	add_child(dst)
	dst.load_state_dict(src.to_state_dict(), src.to_turns_dict())
	assert_int(dst.turns_remaining(HERE, Terrain.TileState.BURNING)) \
		.override_failure_message("the loaded fire did not resume at the countdown it was saved with") \
		.is_equal(src.turns_remaining(HERE, Terrain.TileState.BURNING))


func test_a_save_that_carries_no_clocks_still_lights_its_fires() -> void:
	# Every mission .tres is this shape: an author says which cells are alight and never sets a
	# countdown. No sentinel distinguishes it -- the absent entry simply falls through to the
	# ground's own clock, which is what a fresh deposit gets.
	var store: TerrainStateManager = auto_free(T.store_on_fuel())
	add_child(store)
	store.load_state_dict({HERE: [Terrain.TileState.BURNING]})
	assert_int(store.turns_remaining(HERE, Terrain.TileState.BURNING)) \
		.override_failure_message("a board authored with fire and no clocks did not get its ground's clock") \
		.is_equal(T.FUEL_TURNS)


# --- #891: ground that throws to its corners ------------------------------------------------------
#
# The reach is the BURNING cell's own ground, never the ground catching: a taller flame throws
# sparks further, so tall grass carries fire diagonally into whatever is beside it while ordinary
# grass does not take a corner however flammable that corner is.

func test_ground_that_spreads_wide_takes_all_eight_neighbours() -> void:
	var store: TerrainStateManager = auto_free(T.store_on_wide_fuel())
	add_child(store)
	_deposit(store, HERE, Terrain.TileState.BURNING)
	store.tick_states()
	var want: Array[Vector2i] = [HERE]
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var cell := HERE + Vector2i(dx, dy)
			if not want.has(cell):
				want.append(cell)
	assert_array(_burning(store)) \
		.override_failure_message("wide ground did not take all eight neighbours") \
		.contains_exactly_in_any_order(want)


func test_a_wide_fire_still_advances_only_one_ring_a_round() -> void:
	# The snapshot at the top of tick_states governs the wide shape exactly as it governs the
	# cardinal one -- a corner lit this tick must not throw its own corner in the same tick.
	var store: TerrainStateManager = auto_free(T.store_on_wide_fuel())
	add_child(store)
	_deposit(store, HERE, Terrain.TileState.BURNING)
	store.tick_states()
	assert_bool(store.has_state(HERE + Vector2i(2, 2), Terrain.TileState.BURNING)) \
		.override_failure_message("a wide fire crossed two rings in one round") \
		.is_false()


func test_the_reach_is_the_burning_grounds_and_not_the_catching_grounds() -> void:
	# The load-bearing case. A fire standing on WIDE ground at x=2 must reach the corner at x=3,
	# which is NARROW ground -- the flame's reach, not the target's catchability.
	var store: TerrainStateManager = auto_free(T.store_on_split_ground(3))
	add_child(store)
	var on_wide := Vector2i(2, 5)
	_deposit(store, on_wide, Terrain.TileState.BURNING)
	store.tick_states()
	assert_bool(store.has_state(on_wide + Vector2i(1, 1), Terrain.TileState.BURNING)) \
		.override_failure_message("a fire in wide ground failed to reach a corner of narrow ground") \
		.is_true()


func test_narrow_ground_takes_no_corner_even_when_that_corner_spreads_wide() -> void:
	# The mirror, and what makes the case above about the SOURCE rather than about either cell: a
	# fire on NARROW ground at x=3 must not reach the corner at x=2, however wide that ground is.
	var store: TerrainStateManager = auto_free(T.store_on_split_ground(3))
	add_child(store)
	var on_narrow := Vector2i(3, 5)
	_deposit(store, on_narrow, Terrain.TileState.BURNING)
	store.tick_states()
	assert_bool(store.has_state(on_narrow + Vector2i(-1, -1), Terrain.TileState.BURNING)) \
		.override_failure_message("narrow ground reached a corner because the CORNER spreads wide") \
		.is_false()


func test_fire_on_ground_that_is_not_fuel_stays_cardinal() -> void:
	# A brazier on flagstone is consuming nothing, so there is nothing to tell it to throw wide --
	# _spreads_wide has to answer false for null fuel rather than erroring or defaulting open.
	# The neighbours are wide fuel, so anything taken is the SOURCE's doing.
	var store: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(store)
	var wide := T.wide_fuel()
	store.fuel_source = func(cell: Vector2i) -> TerrainReaction:
		return null if cell == HERE else wide
	_deposit(store, HERE, Terrain.TileState.BURNING)
	store.tick_states()
	assert_bool(store.has_state(HERE + Vector2i(1, 1), Terrain.TileState.BURNING)) \
		.override_failure_message("a fire on non-fuel ground threw to a corner") \
		.is_false()
	assert_bool(store.has_state(HERE + Vector2i.RIGHT, Terrain.TileState.BURNING)) \
		.override_failure_message("a fire on non-fuel ground stopped spreading altogether") \
		.is_true()


func test_the_source_cell_is_never_taken_by_its_own_reach() -> void:
	# cells_within_blended_range hands back the ORIGIN as well as the ring, and what drops it is
	# _catches_fire refusing a cell that is already alight -- every source being a burning cell by
	# construction. That guard now carries two rules, so it is worth asking about directly: re-taking
	# the source would deposit BURNING again and reset its clock, and the fire would never go out.
	var store: TerrainStateManager = auto_free(T.store_on_wide_fuel())
	add_child(store)
	_deposit(store, HERE, Terrain.TileState.BURNING)
	for _round in T.FUEL_TURNS:
		store.tick_states()
	assert_bool(store.has_state(HERE, Terrain.TileState.BURNING)) \
		.override_failure_message("the source re-lit itself and its clock never ran out") \
		.is_false()
	assert_bool(store.has_state(HERE, Terrain.TileState.SCORCHED)) \
		.override_failure_message("the source burnt out without leaving scorched ground") \
		.is_true()


func test_a_wide_fire_cannot_cross_a_one_cell_lane_of_non_fuel() -> void:
	# The firebreak, and the whole of what an authored non-flammable lane is worth (#895): the
	# reach is ONE ring, so a lane a single cell wide is enough to stop even a fire that takes its
	# corners -- the diagonal lands IN the lane, not across it.
	#
	# It is the target-side half of the fuel question, and no case above asks it: every other
	# non-fuel case here puts the non-fuel under the SOURCE. Fire on wide ground either side of a
	# bare column must light every cell of its own side and none of the far one.
	var lane_x := 4
	var store: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(store)
	var wide := T.wide_fuel()
	store.fuel_source = func(cell: Vector2i) -> TerrainReaction:
		return null if cell.x == lane_x else wide
	var near := Vector2i(lane_x - 1, 5)
	_deposit(store, near, Terrain.TileState.BURNING)
	store.tick_states()

	for dy in [-1, 0, 1]:
		assert_bool(store.has_state(Vector2i(lane_x, 5 + dy), Terrain.TileState.BURNING)) \
			.override_failure_message("the bare lane itself caught fire") \
			.is_false()
		assert_bool(store.has_state(Vector2i(lane_x + 1, 5 + dy), Terrain.TileState.BURNING)) \
			.override_failure_message("fire crossed a one-cell lane of non-fuel") \
			.is_false()
	assert_bool(store.has_state(near + Vector2i(-1, -1), Terrain.TileState.BURNING)) \
		.override_failure_message("the fire stopped spreading on its own side of the lane too") \
		.is_true()
