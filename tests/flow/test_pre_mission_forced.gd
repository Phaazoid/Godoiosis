# A roster VIP is forced into the force (#1456). The dev's ruling: "If the VIP comes from the roster,
# they should be forced to be selected." A ScenarioUnitEntry with must_survive on a ROSTER used to be
# dropped at the draw -- the unit came up unflagged, waited in reserve, and Begin went ahead without it.
#
# Every case drives the real door: begin_mission for the draw, the ring and the card for Undeploy, the
# commit and both restarts. The one state set directly is a VIP in reserve, through the host's RAW
# undeploy_unit, because no player door can put them there any more -- that is the point.
#
# THE ROSTER IS AUTHORED IN MEMORY and claimed into the resource cache under a scratch name, so the
# draw resolves it through RosterCatalog exactly as it would a file; nothing is written to Roster/.
# Four characters with the VIP LAST, a cap of 3 and four deployment cells: the authored walk alone
# would have stood the first three and left the VIP behind.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const SCRATCH := "user://__pre_mission_1456.tres"
const ROSTER_NAME := "__vip_roster_1456"

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true in the shipped tileset
const ROW_WIDTH := 8
const ZONE_CELLS := 4
const CAP := 3
const ENEMY_CELL := Vector2i(7, 0)
const NAMES: Array[String] = ["Ana", "Bram", "Cole", "Rebecca"]
const VIP_INDEX := 3

var _main: Node
var game: Node2D
var sm: ScenarioManager
var mc: MissionController
var _roster: Roster


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	mc = game.mission_controller
	sm = game.scenario_manager
	mc._close_mission_select()
	sm.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	sm.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	_roster = null   # the last reference: the cache lets the scratch path go with it
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


# --- the fixture ---------------------------------------------------------------------------------

func _make_roster() -> void:
	_roster = Roster.new()
	for i in NAMES.size():
		var data := H.make_unit_data({}, Team.Faction.PLAYER)
		data.display_name = NAMES[i]
		var entry := ScenarioUnitEntry.new()
		entry.unit_data = data
		entry.state_saved = false   # a cast reference, as a shipped roster's entries are
		entry.must_survive = i == VIP_INDEX
		_roster.entries.append(entry)
	_roster.take_over_path(RosterCatalog.roster_path(ROSTER_NAME))
	assert_object(RosterCatalog.resolve(ROSTER_NAME)).override_failure_message(
		"precondition: the scratch roster does not resolve through the catalogue").is_same(_roster)


# A board whose player force is the roster, declaring PROTECTED_UNIT_LOST, with one enemy so the
# mission is contested rather than won on the spot.
func _author() -> String:
	_make_roster()
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	assert_object(game.spawn_unit(H.make_unit_data({}, Team.Faction.ENEMY), ENEMY_CELL)) \
		.override_failure_message("precondition: could not place the enemy").is_not_null()
	sm.current_roster = ROSTER_NAME
	sm.current_deployment_cap = CAP
	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.ROUT]
	mc.set_objectives(objectives)
	var conds: Array[MissionRules.LoseCondition] = [MissionRules.LoseCondition.PROTECTED_UNIT_LOST]
	mc.set_lose_conditions(conds, 0)
	var scenario := sm.capture_scenario("pre_mission_1456", true)
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	return SCRATCH


func _begin() -> void:
	mc.begin_mission(_author())
	await await_idle_frame()
	assert_bool(mc.is_deploying()).override_failure_message(
		"precondition: the pre-mission phase did not open").is_true()


func _unit(unit_name: String) -> Unit:
	for unit: Unit in mc.roster_units():
		if is_instance_valid(unit) and unit.get_unit_name() == unit_name:
			return unit
	return null


func _vip() -> Unit:
	return _unit(NAMES[VIP_INDEX])


func _screen() -> PreMissionScreen:
	for child in game.card_layer.get_children():
		if child is PreMissionScreen:
			return child
	return null


func _card(unit: Unit) -> PreMissionCard:
	var screen := _screen()
	if screen == null:
		return null
	for card: PreMissionCard in screen._cards:
		if card.unit == unit:
			return card
	return null


# The ring's node for a verb, wherever the tree nests it.
func _ring_node(tree: Array, id: int) -> Dictionary:
	for node: Dictionary in tree:
		if int(node.get("id", -999)) == id:
			return node
		var found := _ring_node(node.get("children", []), id)
		if not found.is_empty():
			return found
	return {}


# --- the draw ------------------------------------------------------------------------------------

func test_the_draw_stands_a_roster_vip_last_in_the_file_and_flags_them() -> void:
	await _begin()
	var vip := _vip()
	assert_object(vip).is_not_null()
	assert_bool(game.is_deployed(vip)).override_failure_message(
		"the roster's VIP waited in reserve -- the walk did not choose them first").is_true()
	assert_bool(vip.must_survive).override_failure_message(
		"the VIP's unit came up unflagged: the draw never applied the entry's placement").is_true()
	# The cap still counts them (the plan's answer 2): the entry they displaced is the one waiting.
	assert_int(mc.deployed_roster_count()).is_equal(CAP)
	assert_bool(game.is_deployed(_unit(NAMES[CAP - 1]))).override_failure_message(
		"the VIP stood on top of the cap rather than inside it").is_false()


# The setup guard sees the drawn VIP, and the mission is lost when they die -- the whole point of the
# flag reaching the unit.
func test_the_drawn_vip_dying_loses_the_mission() -> void:
	await _begin()
	assert_array(mc.lose_conditions_missing_setup()).is_empty()
	assert_bool(mc.commit_deployment()).is_true()
	await await_idle_frame()
	mc.check()   # latch `contested` while both sides stand
	assert_bool(mc.is_over()).is_false()

	_vip().die()
	mc.check()
	assert_int(mc.outcome).is_equal(MissionRules.Outcome.DEFEAT)
	assert_int(mc.mission.failed_by).is_equal(MissionRules.LoseCondition.PROTECTED_UNIT_LOST)


# --- undeploy is refused at every player door ------------------------------------------------------

func test_the_ring_greys_undeploy_on_the_vip_and_the_arm_refuses_it_anyway() -> void:
	await _begin()
	var vip := _vip()
	var reason := mc.undeploy_block_reason(vip)
	assert_str(reason).override_failure_message("the phase has no refusal for the VIP").is_not_empty()

	var row := _ring_node(game.main_action_menu.build_tree(vip), MainActionMenu.UNDEPLOY)
	assert_bool(row.is_empty()).override_failure_message(
		"the VIP's ring lists no Undeploy at all -- a menu greys what it can explain, never hides it"
		).is_false()
	assert_bool(bool(row.get("disabled", false))).is_true()
	assert_str(String(row.get("tooltip", ""))).contains(UiText.wrap(reason))

	# Somebody else's row stays live: the refusal is about the VIP, not the phase.
	var other := _ring_node(game.main_action_menu.build_tree(_unit(NAMES[0])), MainActionMenu.UNDEPLOY)
	assert_bool(other.is_empty()).is_false()
	assert_bool(bool(other.get("disabled", false))).is_false()

	game.main_action_menu._dispatch(MainActionMenu.UNDEPLOY, vip)
	assert_bool(game.is_deployed(vip)).override_failure_message(
		"the ring's Undeploy arm took the VIP off the board").is_true()


func test_the_card_toggle_is_required_and_cannot_send_the_vip_back() -> void:
	await _begin()
	var vip := _vip()
	var card := _card(vip)
	assert_object(card).is_not_null()
	assert_str(card._deploy_button.text).is_equal(PreMissionCard.REQUIRED_TEXT)
	assert_bool(card._deploy_button.disabled).is_true()
	assert_str(card._deploy_button.tooltip_text).is_equal(UiText.wrap(mc.undeploy_block_reason(vip)))

	card.deploy_toggled.emit(vip)   # the belt behind the disabled button
	await await_idle_frame()
	assert_bool(game.is_deployed(vip)).is_true()


# --- Begin is refused without them -----------------------------------------------------------------

func test_begin_is_refused_while_the_vip_waits_in_reserve() -> void:
	await _begin()
	var vip := _vip()
	game.undeploy_unit(vip)   # the raw host door: no player door can do this
	var reason := mc.commit_block_reason()
	assert_str(reason).contains(vip.get_unit_name())

	var screen := _screen()
	screen.refresh()
	assert_bool(screen._begin_button.disabled).override_failure_message(
		"Begin stayed live with the VIP in reserve").is_true()
	assert_str(screen._begin_button.tooltip_text).is_equal(UiText.wrap(reason))

	mc.confirm_and_commit()
	assert_bool(mc.is_deploying()).override_failure_message(
		"the Enter-key commit began the mission without the VIP").is_true()
	assert_bool(mc.commit_deployment()).is_false()
	assert_bool(mc.is_deploying()).is_true()

	# ...and putting them back is all it takes.
	game.deploy_unit(vip, mc.open_deployment_cells()[0])
	assert_str(mc.commit_block_reason()).is_empty()


# --- both restarts keep them -----------------------------------------------------------------------

func test_a_restart_after_begin_stands_the_vip_again() -> void:
	await _begin()
	assert_bool(mc.commit_deployment()).is_true()
	await await_idle_frame()

	mc.restart_mission()
	await await_idle_frame()
	assert_bool(mc.is_deploying()).is_true()
	assert_bool(game.is_deployed(_vip())).is_true()
	assert_bool(_vip().must_survive).override_failure_message(
		"the replay stood the VIP but lost the flag -- it is re-applied from the roster at every draw"
		).is_true()


func test_a_restart_from_inside_the_phase_stands_the_vip_again() -> void:
	await _begin()
	assert_bool(mc.commit_deployment()).is_true()
	await await_idle_frame()
	mc.restart_mission()   # back into the phase on the buffer
	await await_idle_frame()

	mc.restart_mission()   # ...and from INSIDE it: the buffer drops, the authored walk runs
	await await_idle_frame()
	assert_bool(mc.is_deploying()).is_true()
	assert_bool(game.is_deployed(_vip())).is_true()
	assert_bool(_vip().must_survive).is_true()


# The committed cell is gone by the replay (the buffer's own cell rewritten off the map, the restart
# suite's way of reaching it): the VIP takes the first open cell, the one a Deploy click would pick.
func test_a_replay_whose_vip_cell_is_gone_stands_them_on_the_first_open_cell() -> void:
	await _begin()
	assert_bool(mc.commit_deployment()).is_true()
	await await_idle_frame()
	mc._staged.entries[VIP_INDEX].cell = Vector2i(-5, -5)

	mc.restart_mission()
	await await_idle_frame()
	var vip := _vip()
	assert_bool(game.is_deployed(vip)).override_failure_message(
		"the VIP's committed cell was gone and they were left in reserve").is_true()
	assert_bool(game.zone_manager.contains("landing", vip.movement.cell)).is_true()


# --- a board loaded without a draw ------------------------------------------------------------------

# The dev tools' Load and CI's mission sweep load a board without drawing it (F2 does not deploy, by
# design). Nobody is flagged on that board, and the protect condition must still read as set up, or
# a good roster-VIP mission would BLOCK on Check board and turn main red.
func test_a_board_loaded_without_a_draw_has_its_protect_subject() -> void:
	var path := _author()
	sm.clear_board()
	await await_idle_frame()
	sm.load_scenario(path)
	await await_idle_frame()
	assert_bool(mc.is_deploying()).is_false()
	assert_array(mc.protected_units(game._board())).override_failure_message(
		"precondition: a plain load drew the roster").is_empty()
	assert_array(mc.lose_conditions_missing_setup()).override_failure_message(
		"a roster VIP did not count as PROTECTED_UNIT_LOST's subject").is_empty()


# A roster entry carrying a leader's squad fields: the draw hands apply_placement a RESERVE unit,
# which has no squad yet. It used to dereference one.
func test_a_roster_entry_with_squad_fields_draws_without_crashing() -> void:
	var path := _author()
	var entry := _roster.entries[0]   # the roster is in memory: the draw reads it at begin_mission
	entry.squad_id = 0
	entry.is_leader = true
	entry.squad_name = "Escort"
	mc.begin_mission(path)
	await await_idle_frame()
	assert_bool(mc.is_deploying()).is_true()
	assert_bool(game.is_deployed(_unit(NAMES[0]))).is_true()


# --- the screen puts them first (dev: "VIP units should auto lock to the first slots") -------------

func _grid_units() -> Array[Unit]:
	var found: Array[Unit] = []
	for child in _screen()._grid.get_children():
		found.append((child as PreMissionCard).unit)
	return found


func _press_deploy(card: PreMissionCard) -> void:
	card._deploy_button.pressed.emit()
	await await_idle_frame()


static func _label_reading(root: Node, text: String) -> Label:
	for child in root.get_children():
		if child is Label and (child as Label).text == text:
			return child
		var found := _label_reading(child, text)
		if found != null:
			return found
	return null


# The VIP sorts LAST by name among the deployed, so the screen's A-Z rule alone never opens on them.
# Asked at the draw, after somebody else's toggle, and after Reset order: every way the grid is laid out.
func test_the_vip_card_holds_the_first_slot() -> void:
	await _begin()
	var vip := _vip()
	var ana := _unit(NAMES[0])
	assert_int(vip.get_unit_name().naturalnocasecmp_to(ana.get_unit_name())).override_failure_message(
		"precondition: the VIP sorts first by name anyway, so the order proves nothing").is_greater(0)
	assert_object(_grid_units()[0]).override_failure_message(
		"the grid did not open on the VIP").is_same(vip)

	await _press_deploy(_card(ana))
	assert_bool(game.is_deployed(ana)).is_false()
	assert_object(_grid_units()[0]).override_failure_message(
		"another card's toggle moved the VIP off the first slot").is_same(vip)

	_screen()._reset_order_button.pressed.emit()
	await await_idle_frame()
	assert_object(_grid_units()[0]).override_failure_message(
		"Reset order moved the VIP off the first slot").is_same(vip)


# The flag is read off the LIVE unit, so ticking Must survive in the dev tools mid-phase moves that
# card up at the next refresh, in behind the VIP already there.
func test_a_unit_flagged_mid_phase_joins_the_vips_at_the_front() -> void:
	await _begin()
	var bram := _unit(NAMES[1])
	assert_bool(game.is_deployed(bram)).is_true()
	bram.must_survive = true
	_screen().refresh()
	await await_idle_frame()
	assert_array(_grid_units().slice(0, 2)).override_failure_message(
		"a unit flagged mid-phase did not join the VIPs at the front").is_equal([_vip(), bram])


func test_the_vips_squad_leads_the_deployed_force_strip() -> void:
	await _begin()
	var vip := _vip()
	assert_int(vip.get_index()).override_failure_message(
		"precondition: the VIP already stands first on the board, so the strip's order proves nothing"
		).is_greater(_unit(NAMES[0]).get_index())
	var blocks: Array[Node] = _screen()._squads_row.get_children()
	assert_int(blocks.size()).is_equal(CAP)
	assert_object(_label_reading(blocks[0], vip.get_unit_name())).override_failure_message(
		"the VIP's squad is not first on the Deployed force strip").is_not_null()


# The pill rides the NAME LINE: on a row of its own it grew a VIP's card past its neighbours once a
# job picker sat under it.
func test_a_vip_card_is_as_tall_as_its_neighbours() -> void:
	await _begin()
	var vip_card := _card(_vip())
	var other := _card(_unit(NAMES[0]))
	assert_bool(vip_card._vip_pill.visible).is_true()
	assert_bool(other._vip_pill.visible).is_false()
	assert_object(vip_card._job_picker).override_failure_message(
		"precondition: the cards draw no job row, the layout the pill once grew").is_not_null()
	assert_float(vip_card.get_combined_minimum_size().y).override_failure_message(
		"the VIP's card is taller than its neighbour's").is_equal(other.get_combined_minimum_size().y)
