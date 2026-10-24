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
	var hero_damage := RulesService.occupant_damage_for(hero.state, states.states_at(hero.movement.cell))
	var foe_damage := RulesService.occupant_damage_for(foe.state, states.states_at(foe.movement.cell))
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


# Steam's scald (#1331) reaches the headless stack too, and is REPORTED: a gas row used to print only its
# state, so the damage it now carries would have landed with no line saying so.
func test_a_unit_standing_in_steam_is_scalded_and_told_so() -> void:
	var s := _field("ScaldRoot", [])
	var sess = s.sess
	var hero: Unit = s.hero
	var gas: GasField = s.board.gas_field
	gas.set_level(hero.movement.cell, Gas.Kind.STEAM, Gas.MAX_LEVEL)
	var scald := RulesService.gas_damage_for(hero.state, Gas.Kind.STEAM, Gas.MAX_LEVEL)
	var hero_hp := hero.get_current_hp()
	assert_int(scald).override_failure_message("fixture: thick steam scalds nobody").is_greater(0)
	assert_int(hero_hp).override_failure_message("fixture: the scald would down the hero").is_greater(scald)

	var res: Dictionary = sess.end_turn()   # the PLAYER's end of turn

	assert_int(hero.get_current_hp()).override_failure_message(
			"the player's end of turn did not scald the player standing in steam").is_equal(hero_hp - scald)
	var told := "%s takes %d from %s" % [sess.handle_for(hero), scald, Gas.display_name(Gas.Kind.STEAM)]
	var events: Array = res.get("ai_events", [])
	var reported := false
	for line in events:
		if str(line).begins_with(told):
			reported = true
	assert_bool(reported).override_failure_message(
			"the scald landed and end_turn did not say so: %s" % [events]).is_true()


func test_a_burn_that_ends_the_mission_does_not_hand_off() -> void:
	# game.end_turn checks the mission after its burn and bails; so must the headless one.
	var s := _field("LastBurnRoot", [])
	var sess = s.sess
	var hero: Unit = s.hero
	var states: TerrainStateManager = s.board.terrain_states
	_light(states, hero.movement.cell)
	var damage := RulesService.occupant_damage_for(hero.state, states.states_at(hero.movement.cell))
	assert_int(damage).override_failure_message("fixture: fire on this ground charges nothing").is_greater(0)
	hero.take_damage(hero.get_current_hp() - damage)   # one burn's worth left
	assert_bool(hero.is_active()).override_failure_message("fixture: the hero is already down").is_true()

	var res: Dictionary = sess.end_turn()

	assert_bool(hero.is_downed()).override_failure_message(
			"fixture: the burn did not down the player's last unit") \
			.is_true()
	var mission: String = sess.mission_tag()
	assert_str(mission).override_failure_message("fixture: downing the last unit ended nothing") \
			.is_not_empty()
	var reported: String = str(res.get("mission", ""))
	assert_str(reported).override_failure_message("end_turn did not report the mission its burn ended") \
			.is_equal(mission)
	var faction: String = str(sess.status().faction)
	assert_str(faction).override_failure_message(
			"a burn ended the mission and the turn was handed over anyway") \
			.is_equal("PLAYER")


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
	var damage := RulesService.occupant_damage_for(foe.state, states.states_at(lit))
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


# THE HAND-OFF RULE IS THE GAME'S (#1365). The AI loop's own hand-off had no skip, so an AI faction
# with nobody to command took its turn headlessly and burned its downed bodies at the end of it, where
# game._on_turn_started passes it straight over. Both now ask TurnBoundary.start_turn.
func test_a_faction_with_nobody_to_command_is_passed_over_without_its_burn() -> void:
	var b := BoardBuilder.build(self, "SkipRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 16, 16))
	BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var foe: Unit = BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(10, 0))
	foe.squad.archetype = AIArchetype.Type.HOLD
	var body: Unit = BoardBuilder.spawn(b, _data("Body", Team.Faction.ALLY), Vector2i(5, 5))
	body.take_damage(body.get_current_hp())   # damage == HP: downed at 1 hp, not killed
	var sess = PlaySession.new(b)
	var data := ScenarioData.new()
	var ai: Array[Team.Faction] = [ENEMY, Team.Faction.ALLY]
	data.ai_factions = ai
	sess.scenario_data = data
	var states: TerrainStateManager = b.terrain_states
	_light(states, body.movement.cell)
	assert_bool(body.is_downed()).override_failure_message("fixture: the body is not down").is_true()
	assert_int(RulesService.occupant_damage_for(body.state, states.states_at(body.movement.cell))) \
			.override_failure_message("fixture: fire charges the body nothing, so a burn would not show") \
			.is_greater(0)
	var hp := body.get_current_hp()

	sess.end_turn()   # the player's end, the enemy's AI turn, then ALLY: nobody to command

	var faction: String = str(sess.status().faction)
	assert_str(faction).override_failure_message("the hand-off did not come back to the player") \
			.is_equal("PLAYER")
	assert_bool(is_instance_valid(body) and not body.is_dead()).override_failure_message(
			"the downed faction took a turn headlessly and its body burned to death") \
			.is_true()
	assert_int(body.get_current_hp()).override_failure_message(
			"the downed faction took a turn headlessly and burned at its end") \
			.is_equal(hp)


# A hand-off that ends the mission starts no AI turn (#1365): the game's handler returns before
# start_faction_turn, and the headless AI loop regrouped first and asked the mission after.
func test_a_hand_off_that_ends_the_mission_starts_no_ai_turn() -> void:
	AIProfiles.use_fixtures({"": AIProfile.new()})   # a profile that regroups, owned by this case
	var b := BoardBuilder.build(self, "OverRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(0, 0, 16, 4))
	var stats := Stats.STAT_DEFAULTS.duplicate()
	stats[Stats.Stat.LDR] = 8   # room for a squadmate
	var lead: Unit = BoardBuilder.spawn(b, UnitFactory.create_unit_data(stats, "Lead", PLAYER), Vector2i(0, 0))
	var stray: Unit = BoardBuilder.spawn(b, _data("Stray", PLAYER), Vector2i(1, 0))
	BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(15, 3))
	var sess = PlaySession.new(b)
	var data := ScenarioData.new()
	var ai: Array[Team.Faction] = [PLAYER]   # the side whose turn the ending hand-off starts
	data.ai_factions = ai
	sess.scenario_data = data
	var lose: Array[MissionRules.LoseCondition] = [MissionRules.LoseCondition.ROUND_LIMIT]
	sess.mission.lose_conditions = lose
	sess.mission.round_limit = sess.mission.rounds_elapsed + 1   # the wrap into PLAYER runs it out
	b.turn_manager.set_active_faction(ENEMY)

	var res: Dictionary = sess.end_turn()

	assert_str(str(res.get("mission", ""))).override_failure_message(
			"fixture: the hand-off into PLAYER did not end the mission") \
			.is_equal("DEFEAT")
	assert_bool(stray.squad == lead.squad).override_failure_message(
			"the AI regrouped on a board whose mission had already ended") \
			.is_false()
	# Non-vacuity: the regroup the ending withheld is real.
	var sm: SquadManager = b.squad_manager
	assert_int(AIController.regroup(PLAYER, sm, sm.board_source.call())).override_failure_message(
			"fixture: nothing here would have regrouped, so the case shows nothing") \
			.is_greater(0)
	AIProfiles.clear_fixtures()
