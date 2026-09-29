# The headless turn boundary (#898): PlaySession.end_turn runs what game.gd runs between two turns.
# Until it did, the Play API was fire-blind (no burn, no tile clock) and every turn-start tick was
# frozen with it: downed clocks, Guards and watches, stat effects. #110 found the gap on 2026-07-29.
#
# Every case drives the real hand-off through end_turn -- the rules themselves are TurnBoundary's
# and TerrainStateManager's, pinned elsewhere; what these pin is that the headless stack REACHES
# them, at the right faction's edge. Expectations are read off the stores and constants that rule
# them, never restated.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)


# A painted field with a player at the origin and an enemy well away from it, plus a player unit on
# each of `extra` (returned as "extra", in order). Nobody is armed and no faction is AI unless a case
# says so, so nothing but the boundary can change anybody's state. The session is built last, so it
# registers every unit the case needs.
func _field(root_name: String, extra: Array[Vector2i]) -> Dictionary:
	var b := BoardBuilder.build(self, root_name)
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 16, 16))
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var foe: Unit = BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(10, 0))
	var extras: Array[Unit] = []
	for cell in extra:
		extras.append(BoardBuilder.spawn(b, _data("Ally%d" % extras.size(), PLAYER), cell))
	var sess = PlaySession.new(b)
	return {"board": b, "sess": sess, "hero": hero, "foe": foe, "extra": extras}


func _light(states: TerrainStateManager, cell: Vector2i) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([Terrain.TileState.BURNING])
	states.apply(effect)


# One full round on a two-faction board: the player's end hands to the enemy, the enemy's end wraps
# the cycle, which is where TurnManager fires round_completed.
func _end_round(sess) -> void:
	sess.end_turn()
	sess.end_turn()
	var faction: String = str(sess.status().faction)
	assert_str(faction).override_failure_message(
			"a round did not come back to the player -- the fixture's cycle is not two factions") \
			.is_equal("PLAYER")


func test_a_unit_standing_in_fire_burns_at_its_own_factions_end_of_turn() -> void:
	var s := _field("BurnRoot", [])
	var sess = s.sess
	var hero: Unit = s.hero
	var foe: Unit = s.foe
	var states: TerrainStateManager = s.board.terrain_states
	_light(states, hero.movement.cell)
	_light(states, foe.movement.cell)
	var hero_damage := RulesService.occupant_damage_for(hero, states.states_at(hero.movement.cell))
	var foe_damage := RulesService.occupant_damage_for(foe, states.states_at(foe.movement.cell))
	var hero_hp := hero.get_current_hp()
	var foe_hp := foe.get_current_hp()
	assert_int(hero_damage).override_failure_message("fixture: fire on this ground charges nothing") \
			.is_greater(0)
	assert_int(hero_hp).override_failure_message("fixture: the burn would down the hero") \
			.is_greater(hero_damage)
	assert_int(foe_hp).override_failure_message("fixture: the burn would down the foe") \
			.is_greater(foe_damage)

	var res: Dictionary = sess.end_turn()   # the PLAYER's end of turn

	assert_int(hero.get_current_hp()).override_failure_message(
			"the player's end of turn did not burn the player standing in fire") \
			.is_equal(hero_hp - hero_damage)
	assert_int(foe.get_current_hp()).override_failure_message(
			"the enemy burned at the PLAYER's end of turn -- the burn is not scoped to the side that played") \
			.is_equal(foe_hp)
	var handle: String = sess.handle_for(hero)
	var reported := false
	var events: Array = res.get("ai_events", [])
	for line in events:
		if str(line).begins_with(handle):
			reported = true
	assert_bool(reported).override_failure_message("the burn landed and end_turn said nothing about it") \
			.is_true()

	sess.end_turn()   # the ENEMY's end of turn

	assert_int(foe.get_current_hp()).override_failure_message(
			"the enemy's own end of turn did not burn it") \
			.is_equal(foe_hp - foe_damage)


func test_an_ai_faction_burns_at_the_end_of_its_own_turn() -> void:
	# The AI loop is the burn's second door: an AI faction's turn ends inside end_turn, the way
	# AIController.take_faction_turn ends on game.end_turn.
	var s := _field("AiBurnRoot", [])
	var sess = s.sess
	var foe: Unit = s.foe
	var states: TerrainStateManager = s.board.terrain_states
	var data := ScenarioData.new()
	var ai: Array[Team.Faction] = [ENEMY]
	data.ai_factions = ai
	sess.scenario_data = data
	foe.squad.archetype = AIArchetype.Type.HOLD   # holds its ground, so it is still in the fire when its turn ends
	var lit := foe.movement.cell
	_light(states, lit)
	var damage := RulesService.occupant_damage_for(foe, states.states_at(lit))
	var foe_hp := foe.get_current_hp()
	assert_int(damage).override_failure_message("fixture: fire on this ground charges nothing").is_greater(0)
	assert_int(foe_hp).override_failure_message("fixture: the burn would down the foe").is_greater(damage)

	sess.end_turn()   # the player's end hands to the enemy, whose AI turn runs and ends in here

	assert_vector(foe.movement.cell).override_failure_message(
			"fixture: the AI walked off the fire, so its end of turn cannot say anything") \
			.is_equal(lit)
	var faction: String = str(sess.status().faction)
	assert_str(faction).override_failure_message("the AI turn did not hand back to the player") \
			.is_equal("PLAYER")
	assert_int(foe.get_current_hp()).override_failure_message(
			"an AI faction ended its turn standing in fire and did not burn") \
			.is_equal(foe_hp - damage)


func test_a_fire_runs_down_its_own_clock_one_round_at_a_time_and_goes_out() -> void:
	var s := _field("ClockRoot", [])
	var sess = s.sess
	var states: TerrainStateManager = s.board.terrain_states
	var cell := Vector2i(5, 10)   # far enough from both units that the spread never reaches them
	_light(states, cell)
	var clock := states.turns_remaining(cell, Terrain.TileState.BURNING)
	assert_int(clock).override_failure_message(
			"fixture: this ground gives fire no clock, so there is no tick to observe") \
			.is_greater(0)

	for round_index in range(clock):
		assert_int(states.turns_remaining(cell, Terrain.TileState.BURNING)).override_failure_message(
				"after %d round(s) the fire's clock has not moved -- nothing ticked it" % round_index) \
				.is_equal(clock - round_index)
		_end_round(sess)

	assert_bool(states.has_state(cell, Terrain.TileState.BURNING)).override_failure_message(
			"the fire outlived its own clock -- a headless board never burns out") \
			.is_false()


func test_a_downed_units_clock_runs_on_its_own_turns_and_it_bleeds_out() -> void:
	# A second player unit, so the player still has somebody to command while the body lies there.
	var s := _field("BleedRoot", [Vector2i(0, 3)])
	var sess = s.sess
	var extras: Array[Unit] = s.extra
	var body: Unit = extras[0]
	body.take_damage(body.get_current_hp())   # damage == HP: downed at 1 hp, not killed
	assert_bool(body.is_downed()).override_failure_message("fixture: the body is not down").is_true()
	var clock := body.downed_turns_remaining
	assert_int(clock).override_failure_message("fixture: a fresh down does not start the full clock") \
			.is_equal(Unit.DOWNED_TURNS)

	sess.end_turn()   # into the ENEMY's turn: not the body's, so its clock must hold
	assert_int(body.downed_turns_remaining).override_failure_message(
			"the body's clock ticked on the enemy's turn start") \
			.is_equal(clock)
	sess.end_turn()   # back to the player: the first of the body's own turns

	for turn in range(1, clock):
		assert_int(body.downed_turns_remaining).override_failure_message(
				"after %d of its own turn starts the body's clock reads wrong" % turn) \
				.is_equal(clock - turn)
		_end_round(sess)

	assert_bool(body.is_dead()).override_failure_message(
			"the body outlived its downed clock -- a headless body never bleeds out") \
			.is_true()


func test_a_guard_lapses_at_its_owners_next_turn_start() -> void:
	var s := _field("GuardRoot", [Vector2i(1, 0)])
	var sess = s.sess
	var blocker: Unit = s.hero
	var extras: Array[Unit] = s.extra
	var ward: Unit = extras[0]
	blocker.arm_guard(ward, blocker.get_guard_range())
	assert_object(blocker.guard).override_failure_message("fixture: no Guard armed").is_not_null()

	sess.end_turn()   # the enemy's turn starts: not the owner's
	assert_object(blocker.guard).override_failure_message(
			"the Guard lapsed on the wrong faction's turn start") \
			.is_not_null()

	sess.end_turn()   # the owner's next turn starts
	assert_object(blocker.guard).override_failure_message(
			"the Guard outlived its owner's next turn start -- a headless Guard never lapses") \
			.is_null()


func test_a_squadmate_out_of_contact_is_ejected_at_the_hand_off() -> void:
	# enforce_contact follows the ticks at every turn start (#151): displacement the plan never chose
	# splits the squad at the next boundary rather than leashing a member to a leader out of reach.
	var s := _field("ContactRoot", [Vector2i(1, 0)])
	var sess = s.sess
	var leader: Unit = s.hero
	var extras: Array[Unit] = s.extra
	var member: Unit = extras[0]
	var joined: Dictionary = sess.join(sess.handle_for(member), sess.handle_for(leader))
	assert_bool(joined.ok).override_failure_message("fixture: the member did not join").is_true()
	member.movement.set_cell(Vector2i(12, 12))   # a shove the plan never chose
	var squad_manager: SquadManager = s.board.squad_manager
	assert_bool(squad_manager.contact_breaks().has(member)).override_failure_message(
			"fixture: the member is still in contact, so there is nothing to eject") \
			.is_true()

	sess.end_turn()

	assert_bool(member.squad == leader.squad).override_failure_message(
			"a member out of its leader's reach survived the hand-off in the squad") \
			.is_false()
