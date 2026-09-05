# Repositioning a placed unit inside the deployment zone (#772) -- the last thing the board preview
# could not do. Driven through the REAL sequence throughout: game._on_left_click to open the ring,
# MainActionMenu.on_pressed to take the verb, then _on_left_click again for the cell pick, because
# the gate being tested lives in _pre_mission_options and the candidate guard lives in
# _click_picking_target, and nothing but a real open and a real click consults either.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const SCRATCH := "user://__pre_mission_772.tres"

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const ROW_WIDTH := 16
# Long enough that its far end is out of any leader's cohesion reach -- COH is a PATH distance and
# defaults to 4, so cell 12 is comfortably outside a leader standing at 0.
const ZONE_CELLS := 13
const FAR_CELL := Vector2i(ZONE_CELLS - 1, 0)

var _main: Node
var game: Node2D
var sm: ScenarioManager
var mc: MissionController


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
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func _a_roster() -> String:
	var names: Array[String] = RosterCatalog.saved_rosters()
	if names.is_empty():
		push_warning("no rosters are shipped, so repositioning cannot be exercised")
		return ""
	return names[0]


func _roster_size(name: String) -> int:
	var roster: Roster = RosterCatalog.resolve(name)
	return 0 if roster == null else roster.entries.size()


# The zone is a straight row so path distance is trivially the column gap, and an authored ENEMY can
# be parked INSIDE it -- which is what makes the not-a-swap-target case reachable.
func _author(roster: String, cap: int, enemy_in_zone := false) -> String:
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	if enemy_in_zone:
		assert_object(game.spawn_unit(H.make_unit_data({}, Team.Faction.ENEMY), FAR_CELL)) \
			.override_failure_message("precondition: the authored enemy would not spawn").is_not_null()
	sm.current_roster = roster
	sm.current_deployment_cap = cap
	var scenario := sm.capture_scenario("pre_mission_772", true)
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	return SCRATCH


func _enter_phase(cap := 2, enemy_in_zone := false) -> bool:
	var roster := _a_roster()
	if roster == "" or _roster_size(roster) < cap:
		push_warning("the shipped roster cannot fill this cap")
		return false
	mc.begin_mission(_author(roster, cap, enemy_in_zone))
	await await_idle_frame()
	return true


func _drawn() -> Array[Unit]:
	var found: Array[Unit] = []
	for unit: Unit in game.units_root.get_children():
		if unit.drawn_from_roster:
			found.append(unit)
	return found


func _ring_names(unit: Unit) -> Array[String]:
	var names: Array[String] = []
	for id: int in game.main_action_menu.populate(unit):
		names.append(String(MainActionMenu.ACTION_DATA[id]["name"]))
	return names


# The whole gesture, as the player performs it.
func _reposition(unit: Unit, to: Vector2i) -> void:
	game._on_left_click(unit.movement.cell)
	game.main_action_menu.on_pressed(MainActionMenu.REPOSITION, unit)
	game._on_left_click(to)


# --- the verb, and who is offered it ---

func test_a_placed_roster_unit_is_offered_reposition() -> void:
	if not await _enter_phase():
		return
	var names := _ring_names(_drawn()[0])

	assert_bool(names.has("Reposition")).override_failure_message(
		"a placed unit cannot be moved: %s" % str(names)).is_true()
	# Still not a turn verb -- no move is spent and nothing is queued.
	assert_bool(names.has("Move")).is_false()


# Same gate Undeploy rides, and for the same reason: an authored unit is the BOARD's, additive to
# the roster's draw (#731 ruling 2c), so it is not the player's to shuffle.
func test_a_unit_the_board_authored_is_not_repositionable() -> void:
	if not await _enter_phase(2, true):
		return
	var authored: Unit = null
	for unit: Unit in game.units_root.get_children():
		if not unit.drawn_from_roster:
			authored = unit
	assert_object(authored).is_not_null()

	assert_bool(_ring_names(authored).has("Reposition")).override_failure_message(
		"the phase offered to move a unit the board authored").is_false()


# --- where it may go ---

func test_the_candidates_are_zone_cells_and_never_the_units_own() -> void:
	if not await _enter_phase():
		return
	var unit: Unit = _drawn()[0]
	var cells := mc.reposition_cells(unit)

	assert_array(cells).is_not_empty()
	assert_bool(cells.has(unit.movement.cell)).override_failure_message(
		"the unit was offered the cell it is already standing on").is_false()
	for cell: Vector2i in cells:
		assert_bool(game.zone_manager.contains("landing", cell)).override_failure_message(
			"%s is outside the deployment zone" % cell).is_true()
	# ...and the ground beyond the zone is painted and walkable, so its absence is the ZONE's rule
	# rather than the terrain's.
	assert_bool(cells.has(Vector2i(ZONE_CELLS, 0))).override_failure_message(
		"a walkable cell outside the zone was offered").is_false()


func test_a_cell_an_authored_unit_holds_is_not_a_swap_target() -> void:
	if not await _enter_phase(2, true):
		return
	var unit: Unit = _drawn()[0]

	assert_bool(mc.reposition_cells(unit).has(FAR_CELL)).override_failure_message(
		"the zone cell an authored unit stands on was offered as a swap").is_false()


func test_a_click_outside_the_candidates_cancels_and_moves_nobody() -> void:
	if not await _enter_phase():
		return
	var unit: Unit = _drawn()[0]
	var from := unit.movement.cell

	_reposition(unit, Vector2i(ROW_WIDTH - 1, 0))   # painted ground, outside the zone
	await await_idle_frame()

	assert_vector(unit.movement.cell).override_failure_message(
		"a click off the highlighted set moved the unit anyway").is_equal(from)
	assert_int(game.game_state).override_failure_message(
		"the cancelled pick did not rest the board back in the phase"
	).is_equal(game.GameState.PRE_MISSION)


# --- the move itself ---

func test_repositioning_puts_the_unit_on_the_picked_cell() -> void:
	if not await _enter_phase():
		return
	var unit: Unit = _drawn()[0]
	var placed: int = _drawn().size()
	assert_bool(mc.reposition_cells(unit).has(FAR_CELL)).is_true()

	_reposition(unit, FAR_CELL)
	await await_idle_frame()

	assert_vector(unit.movement.cell).override_failure_message(
		"the unit did not move to the cell that was picked").is_equal(FAR_CELL)
	assert_object(game.get_unit_at_cell(FAR_CELL)).is_same(unit)
	assert_int(_drawn().size()).override_failure_message(
		"repositioning changed the force -- it is a MOVE, not a redeploy").is_equal(placed)
	assert_int(game.game_state).is_equal(game.GameState.PRE_MISSION)


# Swapping is allowed (dev, 2026-09-05): an occupied zone cell is a legal target, not a refusal.
func test_repositioning_onto_another_placed_unit_trades_their_places() -> void:
	if not await _enter_phase(2):
		return
	var placed: Array[Unit] = _drawn()
	assert_int(placed.size()).is_equal(2)
	var mover: Unit = placed[0]
	var other: Unit = placed[1]
	var mover_from := mover.movement.cell
	var other_from := other.movement.cell

	assert_bool(mc.reposition_cells(mover).has(other_from)).override_failure_message(
		"another placed unit's cell was not offered as a swap").is_true()
	_reposition(mover, other_from)
	await await_idle_frame()

	assert_vector(mover.movement.cell).is_equal(other_from)
	assert_vector(other.movement.cell).override_failure_message(
		"the swap moved one unit and left the other standing on top of it").is_equal(mover_from)


# --- THE ruling: the squad settles here, not a turn later ---

# Placing a member out of its leader's reach is legal, and the consequence lands NOW rather than at
# turn 1 where enforce_contact would otherwise find it (dev, 2026-09-05). That makes this phase a
# third settle point beside the end of a resolution pass and turn start -- and the point of doing it
# here is that the player is still looking at the board that caused it.
func test_a_reposition_that_breaks_cohesion_ejects_the_member_there_and_then() -> void:
	if not await _enter_phase(2):
		return
	var placed: Array[Unit] = _drawn()
	var leader: Unit = placed[0]
	var member: Unit = placed[1]

	game._on_left_click(leader.movement.cell)
	game.main_action_menu.on_pressed(MainActionMenu.SQUADUP, leader)
	game._on_left_click(member.movement.cell)
	await await_idle_frame()
	assert_bool(leader.has_squad()).override_failure_message(
		"precondition: the squad never formed").is_true()
	var squad: Squad = leader.squad

	_reposition(member, FAR_CELL)
	await await_idle_frame()

	assert_vector(member.movement.cell).is_equal(FAR_CELL)
	assert_bool(squad.get_members().has(member)).override_failure_message(
		"the member walked out of cohesion range and stayed in the squad -- turn 1 would have "
		+ "ejected them, a whole turn after the decision that did it").is_false()
	assert_object(member.squad).override_failure_message(
		"the ejected member is in no squad at all").is_not_null()
	assert_object(member.squad).is_not_same(squad)


# The other half of the same ruling: a move that STAYS in range costs the squad nothing.
func test_a_reposition_inside_cohesion_range_keeps_the_squad() -> void:
	if not await _enter_phase(2):
		return
	var placed: Array[Unit] = _drawn()
	var leader: Unit = placed[0]
	var member: Unit = placed[1]

	game._on_left_click(leader.movement.cell)
	game.main_action_menu.on_pressed(MainActionMenu.SQUADUP, leader)
	game._on_left_click(member.movement.cell)
	await await_idle_frame()
	var squad: Squad = leader.squad
	assert_bool(leader.has_squad()).is_true()

	var near := Vector2i(leader.movement.cell.x + 2, 0)   # inside a COH of 4, path distance
	assert_bool(mc.reposition_cells(member).has(near)).is_true()
	_reposition(member, near)
	await await_idle_frame()

	assert_vector(member.movement.cell).is_equal(near)
	assert_bool(squad.get_members().has(member)).override_failure_message(
		"a move well inside the leash broke the squad anyway").is_true()
