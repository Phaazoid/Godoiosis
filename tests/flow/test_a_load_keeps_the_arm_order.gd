# A mid-battle load keeps which standing watch, and which Guard, is OLDER (#1565). Arm order is what
# decides which one an entry spends: the oldest watch over a cell fires on the walker, the oldest Guard
# on a ward takes the hit. A load used to re-arm each one fresh in BOARD order, so two watchers armed
# against their board order swapped after a save, and the other one fired.
#
# Everything reaches the board through the real doors: each watch and Guard is a queued order armed by
# its own pass, the round trip is the game's own capture_scenario/apply_scenario, and the answer is the
# resolver's, read off a real queued enemy order on the game host AND on the headless BoardBuilder load
# of the same data.
#
# The control is the authored rule, which must not move: an authored save writes no arm order, so an
# Update of a board with authored standing watches writes no new line.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true in the shipped tileset
const WIDTH := 7
const HEIGHT := 5

# Two watchers, spawned FIRST and SECOND, both aimed at one cell an enemy walks into.
const FIRST_WATCHER := Vector2i(1, 0)
const SECOND_WATCHER := Vector2i(1, 4)
const WATCHED := Vector2i(1, 2)
const WALKER := Vector2i(3, 2)
const WALK: Array[Vector2i] = [Vector2i(3, 2), Vector2i(2, 2), Vector2i(1, 2)]

# Two blockers, spawned FIRST and SECOND, both warding one unit an enemy strikes.
const FIRST_BLOCKER := Vector2i(1, 1)
const SECOND_BLOCKER := Vector2i(3, 1)
const WARD := Vector2i(2, 1)
const STRIKER := Vector2i(2, 2)

var _main: Node
var game: Node2D
var sm: ScenarioManager


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	sm = game.scenario_manager
	game.mission_controller._close_mission_select()
	sm.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()
	for x in range(WIDTH):
		for y in range(HEIGHT):
			game.grid.paint(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	sm.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func _units() -> Array[Unit]:
	var units: Array[Unit] = []
	for child in game.units_root.get_children():
		if child is Unit and not child.is_queued_for_deletion():
			units.append(child)
	return units


static func _unit_at(units: Array[Unit], cell: Vector2i) -> Unit:
	for unit: Unit in units:
		if unit.movement.cell == cell:
			return unit
	return null


# Volley siblings link into a shared self-referential array (#35); break them so the plan does not leak.
static func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
	for ctr in plan.counters:
		ctr.volley = empty
	for shot in plan.watch_shots:
		shot.volley = empty


# A watcher whose equipped weapon carries a watch attack reaching WATCHED. Ad-hoc content (the razor).
func _watcher(cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, PLAYER), cell)
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CARBINE
	template.main_attack = WeaponAttackData.new()
	var watch := WeaponAttackData.new()
	watch.can_overwatch = true
	watch.max_range = 2
	watch.power = 3
	template.extra_attacks = [watch]
	unit.add_item(WeaponInstance.make(template))
	return unit


# A real Overwatch order aimed at WATCHED, armed by its own pass.
func _arm_watch(unit: Unit) -> void:
	var order := OverwatchAction.new()
	order.init(unit, WATCHED, unit.overwatch_attacks()[0])
	assert_bool(game.squad_manager.queue_action(unit.squad, order)) \
		.override_failure_message("precondition: the Overwatch order was refused").is_true()
	await game.order_executor.execute_orders(unit)
	assert_object(unit.watch).override_failure_message("precondition: the watch did not arm").is_not_null()


# A real Guard order on `ward`, armed by its own pass.
func _arm_guard(blocker: Unit, ward: Unit) -> void:
	game.queue_guard(blocker, ward)
	await game.order_executor.execute_orders(blocker)
	assert_object(blocker.guard).override_failure_message("precondition: the Guard did not arm").is_not_null()


# The game's two units watching WATCHED, armed SECOND watcher first, against their board order.
func _watches_armed_against_board_order() -> void:
	var first := _watcher(FIRST_WATCHER)
	var second := _watcher(SECOND_WATCHER)
	game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: 60}, ENEMY), WALKER)
	await _arm_watch(second)
	await _arm_watch(first)
	assert_bool(second.watch.sequence < first.watch.sequence) \
		.override_failure_message("precondition: the second watcher's watch is not the older").is_true()


# The game's two blockers on WARD, armed SECOND blocker first, against their board order.
func _guards_armed_against_board_order() -> void:
	var first: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: 60}, PLAYER), FIRST_BLOCKER)
	var second: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: 60}, PLAYER), SECOND_BLOCKER)
	var ward: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: 60}, PLAYER), WARD)
	var striker_data := H.make_unit_data({}, ENEMY)
	var inventory: Array[Item] = [H.make_weapon(4)]
	striker_data.starting_inventory = inventory
	striker_data.starting_equipped_index = 0
	game.spawn_unit(striker_data, STRIKER)
	await _arm_guard(second, ward)
	await _arm_guard(first, ward)
	assert_bool(second.guard.sequence < first.guard.sequence) \
		.override_failure_message("precondition: the second blocker's Guard is not the older").is_true()


# Which watcher fires on the walker walking into WATCHED: the resolver's answer on `manager`'s board.
static func _who_fires(manager: SquadManager, board: BoardContext, units: Array[Unit]) -> Unit:
	var walker := _unit_at(units, WALKER)
	var move := MoveAction.new()
	move.init(walker, WALK, null)
	if not manager.queue_action(walker.squad, move):
		return null
	var plan := manager.resolve_plan(walker.squad, board)
	var shooter: Unit = plan.watch_shots[0].actor if not plan.watch_shots.is_empty() else null
	_break_volleys(plan)
	return shooter


# Which blocker takes the striker's hit on WARD: the resolver's answer on `manager`'s board.
static func _who_absorbs(manager: SquadManager, board: BoardContext, units: Array[Unit]) -> Unit:
	var striker := _unit_at(units, STRIKER)
	if not manager.queue_action(striker.squad, AttackAction.declare(striker, STRIKER, WARD)):
		return null
	var plan := manager.resolve_plan(striker.squad, board)
	var blocker: Unit = plan.attacks[0].target if not plan.attacks.is_empty() else null
	_break_volleys(plan)
	return blocker


# The same captured board onto a fresh headless board, through the Play API's loader.
func _headless_load(scenario: ScenarioData) -> Dictionary:
	var board := BoardBuilder.build(self, "ArmOrderHeadless")
	auto_free(board.root)
	var units: Array[Unit] = await BoardBuilder.apply_scenario(board, scenario)
	return {"board": board, "units": units,
		"context": BoardContext.new(board.grid, units, board.squad_manager)}


# ==============================================================================

func test_the_older_watch_still_fires_first_after_a_load() -> void:
	await _watches_armed_against_board_order()

	var snapshot: ScenarioData = sm.capture_scenario("arm_order_watch")
	sm.apply_scenario(snapshot)
	await await_idle_frame()

	var units := _units()
	var shooter := _who_fires(game.squad_manager, game._board(), units)
	assert_object(shooter).override_failure_message("nobody fired on the walker after the load").is_not_null()
	assert_that(shooter.movement.cell).override_failure_message(
		"the game's load swapped the arm order: the younger watch fired").is_equal(SECOND_WATCHER)

	var headless := await _headless_load(snapshot)
	var headless_shooter := _who_fires(headless.board.squad_manager, headless.context, headless.units)
	assert_object(headless_shooter).override_failure_message(
		"nobody fired on the walker after the headless load").is_not_null()
	assert_that(headless_shooter.movement.cell).override_failure_message(
		"the headless load swapped the arm order: the younger watch fired").is_equal(SECOND_WATCHER)


func test_the_older_guard_still_absorbs_first_after_a_load() -> void:
	await _guards_armed_against_board_order()

	var snapshot: ScenarioData = sm.capture_scenario("arm_order_guard")
	sm.apply_scenario(snapshot)
	await await_idle_frame()

	var blocker := _who_absorbs(game.squad_manager, game._board(), _units())
	assert_object(blocker).override_failure_message("nothing was struck after the load").is_not_null()
	assert_that(blocker.movement.cell).override_failure_message(
		"the game's load swapped the arm order: the younger Guard absorbed").is_equal(SECOND_BLOCKER)

	var headless := await _headless_load(snapshot)
	var headless_blocker := _who_absorbs(headless.board.squad_manager, headless.context, headless.units)
	assert_object(headless_blocker).override_failure_message(
		"nothing was struck after the headless load").is_not_null()
	assert_that(headless_blocker.movement.cell).override_failure_message(
		"the headless load swapped the arm order: the younger Guard absorbed").is_equal(SECOND_BLOCKER)


func test_an_authored_save_writes_no_arm_order() -> void:
	await _watches_armed_against_board_order()
	var ward: Unit = game.spawn_unit(H.make_unit_data({}, PLAYER), Vector2i(5, 0))
	await _arm_guard(game.spawn_unit(H.make_unit_data({}, PLAYER), Vector2i(5, 1)), ward)

	var authored: ScenarioData = sm.capture_scenario("arm_order_authored", true)
	var watches := 0
	var guards := 0
	for entry: ScenarioUnitEntry in authored.unit_entries:
		watches += 1 if not entry.watch_cells.is_empty() else 0
		guards += 1 if entry.guard_ward_index >= 0 else 0
		assert_int(entry.watch_sequence).override_failure_message(
			"an authored save wrote a watch's arm order, so an Update writes a line no board had").is_equal(0)
		assert_int(entry.guard_sequence).override_failure_message(
			"an authored save wrote a Guard's arm order, so an Update writes a line no board had").is_equal(0)
	assert_int(watches).override_failure_message("precondition: the authored save kept no watch").is_equal(2)
	assert_int(guards).override_failure_message("precondition: the authored save kept no Guard").is_equal(1)
