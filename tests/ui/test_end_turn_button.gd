# The bottom-left End Turn button (#189) -- read at the RENDERED node (visible/flashing) rather
# than the predicate behind it, mirroring test_mission_status_panel.gd's doctrine: the wire cases
# drive the real dispatch (a menu WAIT pick, the button's own pressed signal), so a dropped
# refresh_end_turn_button() call or a broken .connect() goes red here, not just a wrong bool.
#
# Real game scene (the #114 fixture -- root MUST be named "Main" under /root).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

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
	game.turn_manager.set_active_faction(Team.Faction.PLAYER)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


func _visible() -> bool:
	return game.end_turn_button.visible


# ==============================================================================
#  Visibility
# ==============================================================================

func test_hidden_with_one_unacted_squad() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	game.refresh_end_turn_button()
	assert_bool(_visible()).is_false()


func test_appears_once_the_last_squad_waits_through_the_real_menu_pick() -> void:
	var unit := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	assert_bool(_visible()).is_false()

	game.main_action_menu.on_pressed(MainActionMenu.WAIT, unit)

	assert_bool(_visible()) \
		.override_failure_message("End Turn button did not appear once the only squad waited") \
		.is_true()


func test_stays_hidden_until_every_squad_has_acted() -> void:
	var first := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var second := _spawn(Team.Faction.PLAYER, Vector2i(2, 2))

	game.main_action_menu.on_pressed(MainActionMenu.WAIT, first)
	assert_bool(_visible()) \
		.override_failure_message("Button showed with a second squad still unacted") \
		.is_false()

	game.main_action_menu.on_pressed(MainActionMenu.WAIT, second)
	assert_bool(_visible()).is_true()


func test_a_downed_squadmate_does_not_block_the_others() -> void:
	# faction_all_squads_acted only counts squads with an ACTIVE leader (mirrors
	# AIController.take_faction_turn's own filter) -- a squad whose leader is down has nothing
	# left to click either, so it must not hold the button hostage.
	var standing := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var downed := _spawn(Team.Faction.PLAYER, Vector2i(2, 2))
	downed.die()

	game.main_action_menu.on_pressed(MainActionMenu.WAIT, standing)

	assert_bool(_visible()).is_true()


# ==============================================================================
#  The wire -- pressing the button actually ends the turn
# ==============================================================================

func test_pressing_the_button_ends_the_turn() -> void:
	var unit := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	game.main_action_menu.on_pressed(MainActionMenu.WAIT, unit)
	assert_bool(unit.squad.has_acted).is_true()

	game.end_turn_button.end_turn_requested.emit()   # the real .connect() site, not the handler directly
	await await_idle_frame()

	# Only PLAYER units are on the board, so the cycle hands the turn straight back to PLAYER,
	# which resets has_acted -- an observable side effect only reachable if the signal actually
	# drove game.end_turn() through to the turn handoff.
	assert_bool(unit.squad.has_acted) \
		.override_failure_message("end_turn_requested didn't reach game.end_turn() -- the turn never handed off") \
		.is_false()


func test_hides_again_after_the_turn_handoff() -> void:
	var unit := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	game.main_action_menu.on_pressed(MainActionMenu.WAIT, unit)
	assert_bool(_visible()).is_true()

	game.end_turn_button.end_turn_requested.emit()
	await await_idle_frame()

	# Only PLAYER units are on the board, so the cycle hands the turn straight back to PLAYER --
	# freshly reset, nothing has acted yet.
	assert_bool(_visible()) \
		.override_failure_message("Button stayed up into the next turn instead of resetting")\
		.is_false()


# ==============================================================================
#  Sharing the bottom-right corner with the objectives box
# ==============================================================================

func test_the_button_and_the_objectives_box_never_overlap() -> void:
	# Both live bottom-right (#189): the button at the corner, MissionStatusPanel lifted
	# BUTTON_CLEARANCE above its slot. The slot is reserved even while the button is hidden,
	# so this holds whenever both are visible at once.
	for cell: Vector2i in [Vector2i(3, 3)]:
		game.zone_manager.paint_cell("Point", ZoneManager.Kind.CAPTURE, cell)
	var typed: Array[MissionRules.Objective] = []
	typed.assign([MissionRules.Objective.CAPTURE])
	game.mission_controller.set_objectives(typed)

	var unit := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	game.main_action_menu.on_pressed(MainActionMenu.WAIT, unit)
	await await_idle_frame()

	assert_bool(_visible()).is_true()
	assert_bool(game.mission_status_panel._panel.visible).is_true()
	var button_rect: Rect2 = game.end_turn_button._button.get_global_rect()
	var panel_rect: Rect2 = game.mission_status_panel._panel.get_global_rect()
	assert_bool(button_rect.intersects(panel_rect)) \
		.override_failure_message("End Turn button and objectives box overlap: %s vs %s" % [button_rect, panel_rect]) \
		.is_false()


func test_the_objectives_box_clears_the_execute_orders_button() -> void:
	# The other tenant of the right edge: while a plan is open, the queue dock's Execute button is
	# the lowest thing in it, and the objectives box -- lifted above the End Turn slot (#189) --
	# must not ride up into it. Found overlapping in play, 2026-08-11.
	for cell: Vector2i in [Vector2i(3, 3)]:
		game.zone_manager.paint_cell("Point", ZoneManager.Kind.CAPTURE, cell)
	var typed: Array[MissionRules.Objective] = []
	typed.assign([MissionRules.Objective.CAPTURE])
	game.mission_controller.set_objectives(typed)

	# The panel's own render path, fed a minimal view model: any non-empty entry list shows the
	# dock and its Execute button, which is all this layout question needs.
	var entries: Array[ActionQueueDisplayEntry] = [ActionQueueDisplayEntry.header("MOVE")]
	game.squad_action_queue_control.show_display_entries(entries)
	await await_idle_frame()

	assert_bool(game.squad_action_queue_control.visible).is_true()
	assert_bool(game.mission_status_panel._panel.visible).is_true()
	var execute_rect: Rect2 = game.squad_action_queue_control.execute_button.get_global_rect()
	var panel_rect: Rect2 = game.mission_status_panel._panel.get_global_rect()
	assert_bool(execute_rect.intersects(panel_rect)) \
		.override_failure_message("Execute Orders button and objectives box overlap: %s vs %s" % [execute_rect, panel_rect]) \
		.is_false()


# ==============================================================================
#  Locked-board guard
# ==============================================================================

func test_hidden_while_the_board_is_locked() -> void:
	var unit := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	game.main_action_menu.on_pressed(MainActionMenu.WAIT, unit)
	assert_bool(_visible()).is_true()

	game.game_state = game.GameState.AI_TURN
	game.refresh_end_turn_button()

	assert_bool(_visible()).is_false()
