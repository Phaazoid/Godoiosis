# Guard's three GAME-LEVEL wires (#414), each of which is a whole feature that can be missing while
# every rule test stays green — #103's shape, three times over:
#
#   1. The lapse tick. "Lapses when its owner's faction's next turn begins" is one line in
#      game._run_turn_start_ticks; without it a Guard is immortal and the rule tests never notice,
#      because they call Unit.lapse_guard directly.
#   2. The ground markers. An armed Guard has to be visible on the board through the enemy phase,
#      which means it cannot ride the selection channel — and the refresh has to actually be called.
#   3. The save round trip. A live ward is battle state, and it is a PAIR, so it can only round-trip
#      through the entry-index re-link ScenarioManager owns.
#
# Fixture is the shared game-scene one -- see tests/README.md -> Testing the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		for y in range(3):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


func _guard_marked(unit: Unit) -> bool:
	var icons: Dictionary = game.overlay_manager.icons_by_unit
	if not icons.has(unit):
		return false
	return (icons[unit] as Dictionary).has(OverlayIcon.IconType.GUARD_WARD)


# --- 1. the lapse tick --------------------------------------------------------------------------

func test_a_factions_turn_start_lapses_its_own_guards_and_leaves_the_others() -> void:
	var player_blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var player_ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	var enemy_blocker := _spawn(Team.Faction.ENEMY, Vector2i(5, 0))
	var enemy_ward := _spawn(Team.Faction.ENEMY, Vector2i(6, 0))
	await await_idle_frame()
	player_blocker.arm_guard(player_ward, player_blocker.get_guard_range())
	enemy_blocker.arm_guard(enemy_ward, enemy_blocker.get_guard_range())

	game.turn_manager.turn_started.emit(Team.Faction.PLAYER)
	await await_idle_frame()

	assert_object(player_blocker.guard) \
		.override_failure_message("the player's Guard survived its own turn start -- it is immortal") \
		.is_null()
	assert_object(enemy_blocker.guard) \
		.override_failure_message("a turn start lapsed somebody ELSE's Guard") \
		.is_not_null()


# --- 2. the ground markers ----------------------------------------------------------------------

func test_an_armed_guard_marks_both_ends_of_the_pair() -> void:
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	await await_idle_frame()
	blocker.arm_guard(ward, blocker.get_guard_range())

	game.refresh_guard_markers()

	assert_bool(_guard_marked(blocker)).is_true()
	assert_bool(_guard_marked(ward)).is_true()


func test_queueing_and_executing_a_guard_leaves_the_marker_on_the_board() -> void:
	# THE sequence a player performs, which every other case in this file skips: queue the order,
	# press Execute, look at the board. The cases below arm the ward by calling arm_guard and then
	# call refresh_guard_markers by hand — i.e. they set the state directly instead of driving the
	# real path, which is the blind spot #114 exists to name. If the marker never appears in play,
	# this is the case that says so.
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	var _enemy := _spawn(Team.Faction.ENEMY, Vector2i(6, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(ward, blocker.squad)

	game.queue_guard(blocker, ward)
	assert_bool(blocker.has_action_type_queued(BaseAction.ActionType.GUARD)) \
		.override_failure_message("fixture failed to queue the Guard").is_true()

	await game.order_executor.execute_orders(blocker.squad.get_leader())

	assert_object(blocker.guard) \
		.override_failure_message("the pass did not arm the Guard at all").is_not_null()
	assert_bool(_guard_marked(ward)) \
		.override_failure_message("no ground marker under the WARD after a real queue-and-execute") \
		.is_true()
	assert_bool(_guard_marked(blocker)) \
		.override_failure_message("no ground marker under the BLOCKER after a real queue-and-execute") \
		.is_true()


func test_a_spent_guard_stops_being_marked() -> void:
	# It protects nobody now; leaving the mark up would promise cover that is gone.
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	await await_idle_frame()
	blocker.arm_guard(ward, blocker.get_guard_range())
	game.refresh_guard_markers()

	blocker.spend_guard()
	game.refresh_guard_markers()

	assert_bool(_guard_marked(blocker)).is_false()
	assert_bool(_guard_marked(ward)).is_false()


func test_a_guard_marker_survives_a_selection_clear() -> void:
	# The whole reason it is not on the selection channel: a standing reaction has to stay readable
	# while the player clicks elsewhere and all through the enemy's phase.
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	await await_idle_frame()
	blocker.arm_guard(ward, blocker.get_guard_range())
	game.refresh_guard_markers()

	game.clear_selection_icons()

	assert_bool(_guard_marked(blocker)).is_true()


# --- 3. the save round trip ---------------------------------------------------------------------

func test_a_live_guard_survives_a_capture_and_apply() -> void:
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(ward, blocker.squad)
	blocker.arm_guard(ward, blocker.get_guard_range())

	var snapshot: ScenarioData = game.scenario_manager.capture_scenario("guard-roundtrip")
	game.scenario_manager.clear_board()
	game.scenario_manager.apply_scenario(snapshot)
	await await_idle_frame()

	var reloaded_blocker: Unit = game.get_unit_at_cell(Vector2i(1, 0))
	var reloaded_ward: Unit = game.get_unit_at_cell(Vector2i(2, 0))
	assert_object(reloaded_blocker).override_failure_message("the board did not reload").is_not_null()
	assert_object(reloaded_blocker.guard) \
		.override_failure_message("the Guard was lost on save/load").is_not_null()
	assert_object(reloaded_blocker.guard.ward).is_same(reloaded_ward)
	assert_bool(reloaded_blocker.guard.spent).is_false()


func test_a_spent_guard_round_trips_as_spent() -> void:
	# The other half: "already used" and "never had one" are different facts, and a save that
	# forgot the flag would hand the player a fresh block on load.
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(ward, blocker.squad)
	blocker.arm_guard(ward, blocker.get_guard_range())
	blocker.spend_guard()

	var snapshot: ScenarioData = game.scenario_manager.capture_scenario("guard-roundtrip-spent")
	game.scenario_manager.clear_board()
	game.scenario_manager.apply_scenario(snapshot)
	await await_idle_frame()

	var reloaded_blocker: Unit = game.get_unit_at_cell(Vector2i(1, 0))
	assert_object(reloaded_blocker.guard).is_not_null()
	assert_bool(reloaded_blocker.guard.spent).is_true()


func test_a_board_with_no_guards_round_trips_with_none() -> void:
	# The control for both cases above: without it they pass against a loader that arms everybody.
	var a := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var b := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(b, a.squad)

	var snapshot: ScenarioData = game.scenario_manager.capture_scenario("guard-roundtrip-none")
	game.scenario_manager.clear_board()
	game.scenario_manager.apply_scenario(snapshot)
	await await_idle_frame()

	assert_object((game.get_unit_at_cell(Vector2i(1, 0)) as Unit).guard).is_null()
	assert_object((game.get_unit_at_cell(Vector2i(2, 0)) as Unit).guard).is_null()
