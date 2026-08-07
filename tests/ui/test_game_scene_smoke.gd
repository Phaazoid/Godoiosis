# Smoke coverage for the input layer -- game.gd, HoverPresenter and MainActionMenu (#114).
#
# These three files had ZERO automated coverage until this suite, on the belief that the game
# scene segfaults inside the gdUnit4 runner. It does not (measured 2026-07-29): Main.tscn
# instantiates, spawns a board and dispatches clicks under the runner without crashing. The
# real blocker was game.gd's ABSOLUTE dev-overlay path -- `get_node("/root/Main/DevOverlay")`
# only resolves when the scene root is literally named "Main" and sits directly under /root,
# which is what before_test() arranges. Without it ScenarioManager.clear_board() nulls out on
# `game.dev_overlay.unit_editor`, and that error was the thing that read as "unusable".
#
# Scope, per #114: "a mode you can enter must not crash" -- not pixel-level verification. The
# two queueing tests are the ones with teeth: #107 shipped a build where Move crashed instantly
# and Attack silently queued nothing, on a 708/708 green run.
#
# Input is driven through _on_left_click/_on_right_click rather than real InputEvents, because
# Godot does not deliver InputEvents in headless mode (gdUnit4 warns about this on every run).
# Those two ARE the dispatchers -- _unhandled_input does nothing but pick a cell and call them.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	# Named + parented exactly as in production so game.gd's absolute /root/Main/DevOverlay
	# lookup resolves. Reparenting it under the suite instead is what makes dev_overlay null.
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.spawn_sandbox()
	# _ready leaves the board in MENU behind Mission Select (#96). The sandbox row is what
	# normally clears it; go straight to IDLE since the menu itself is not under test here.
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


# Every mode the player can be in, minus the two the board cannot be driven into from a click.
func _player_states() -> Array:
	return [
		game.GameState.IDLE,
		game.GameState.TILE_SELECTED,
		game.GameState.ATTACK_TARGETING,
		game.GameState.CHOOSING_MOVE,
		game.GameState.CHOOSING_GROUP_MOVE,
		game.GameState.PICKING_TARGET,
		game.GameState.DEV_MODE,
	]


func _first_player_unit() -> Unit:
	for unit: Unit in game._all_units():
		if unit.get_faction() == Team.Faction.PLAYER:
			return unit
	return null


# Pick an entry from the open main menu the way the real control does. ActionMenuController
# emits `cancelled` BEFORE `action_selected` even on a genuine pick, so MainActionMenu's
# clear_selection() runs on the way INTO the chosen mode -- that ordering is the whole reason
# #105 and #107 happened, and a test that skips it cannot see either bug.
func _pick_menu_action(action_id: int, unit: Unit) -> void:
	var controller: ActionMenuController = null
	for child in game.get_children():
		if child is ActionMenuController:
			controller = child
	assert_object(controller).is_not_null()   # the menu never opened
	controller.cancelled.emit(controller)
	controller.action_selected.emit(action_id, unit)


# ------------------------------------------------------------------------------
#  The scene stands up at all
# ------------------------------------------------------------------------------

func test_game_scene_instantiates_with_collaborators() -> void:
	# The four collaborators game._build_collaborators() wires; a null here means the scene
	# came up half-built and every test below would be testing nothing.
	assert_object(game.hover_presenter).is_not_null()
	assert_object(game.main_action_menu).is_not_null()
	assert_object(game.order_executor).is_not_null()
	assert_object(game.mission_controller).is_not_null()


func test_dev_overlay_resolves() -> void:
	# Guards the fixture itself: if this fails, /root/Main/DevOverlay stopped resolving and
	# clear_board() is silently erroring in every other test in this file.
	assert_object(game.dev_overlay).is_not_null()


func test_sandbox_board_populates() -> void:
	assert_int(game.units_root.get_child_count()).is_greater(0)
	assert_object(_first_player_unit()).is_not_null()


# ------------------------------------------------------------------------------
#  Selection and cancel
# ------------------------------------------------------------------------------

func test_click_selects_the_unit_under_the_pointer() -> void:
	var unit := _first_player_unit()
	game._on_left_click(unit.movement.cell)
	assert_object(game.selected_unit).is_same(unit)
	assert_int(game.game_state).is_equal(game.GameState.TILE_SELECTED)


func test_right_click_cancels_back_to_idle() -> void:
	var unit := _first_player_unit()
	game._on_left_click(unit.movement.cell)
	game._on_right_click()
	assert_int(game.game_state).is_equal(game.GameState.IDLE)
	assert_object(game.selected_unit).is_null()


func test_clicking_empty_ground_selects_nothing() -> void:
	game._on_left_click(Vector2i(-99, -99))
	assert_object(game.selected_unit).is_null()
	assert_int(game.game_state).is_equal(game.GameState.IDLE)


# ------------------------------------------------------------------------------
#  Modes: entering and leaving one must never crash or strand the board
# ------------------------------------------------------------------------------

func test_exit_current_mode_returns_to_idle_from_every_state() -> void:
	for state: int in _player_states():
		game.selected_unit = _first_player_unit()
		game.game_state = state
		game.exit_current_mode()
		assert_int(game.game_state).is_equal(game.GameState.IDLE)
		assert_object(game.selected_unit).is_null()


func test_left_click_in_every_state_is_survivable() -> void:
	# The dispatcher table in _on_left_click: every arm must handle a live board without
	# crashing. This is the shape of bug #107 -- a mode you can enter that dies on the click.
	var unit := _first_player_unit()
	for state: int in _player_states():
		game.selected_unit = unit
		game.game_state = state
		game._on_left_click(unit.movement.cell)
	assert_bool(true).is_true()   # reaching here without a crash IS the assertion


func test_hover_in_every_state_is_survivable() -> void:
	# HoverPresenter.update_hover_visuals has one branch per GameState and had no coverage at
	# all; _on_left_click calls it before dispatching, so a bad branch breaks clicking too.
	var unit := _first_player_unit()
	for state: int in _player_states():
		game.selected_unit = unit
		game.game_state = state
		game.hover_presenter.update_hover_visuals(unit.movement.cell)
		game.hover_presenter.update_hover_visuals(Vector2i(-99, -99))
	assert_bool(true).is_true()


func test_main_menu_opens_for_a_selected_unit() -> void:
	var unit := _first_player_unit()
	game._on_left_click(unit.movement.cell)
	game.main_action_menu.show_main_menu(unit, Vector2i.ZERO)
	assert_bool(true).is_true()


# ------------------------------------------------------------------------------
#  Queueing through the real click handlers -- the #107 regressions
# ------------------------------------------------------------------------------

func test_selection_survives_a_menu_pick() -> void:
	# The tightest pin on #107. clear_selection() runs on every menu PICK, not just on cancel,
	# so anything that must live into a mode cannot be cleared there -- selected_unit is
	# nulled in exit_current_mode() instead. Putting it back in clear_selection() crashes Move
	# and silently no-ops Attack, which is exactly what shipped on a 708/708 green run.
	var unit := _first_player_unit()
	game._on_left_click(unit.movement.cell)
	game.main_action_menu._on_menu_cancelled(null)
	assert_object(game.selected_unit).is_same(unit)


func test_move_mode_queues_a_move_order() -> void:
	# #107: pressing Move crashed instantly (compute_move_range on a null unit) on a green run.
	var unit := _first_player_unit()
	game._on_left_click(unit.movement.cell)
	_pick_menu_action(MainActionMenu.MOVE, unit)
	assert_int(game.game_state).is_equal(game.GameState.CHOOSING_MOVE)

	var reachable: Array = game.compute_move_range(unit).reachable.keys()
	var destination: Vector2i = unit.movement.cell
	for cell: Vector2i in reachable:
		if cell != unit.movement.cell:
			destination = cell
			break
	assert_that(destination).is_not_equal(unit.movement.cell)   # the board must offer a step

	game._on_left_click(destination)

	var queued := 0
	for action: BaseAction in unit.squad.action_queue:
		if action.actor == unit and action is MoveAction:
			queued += 1
	assert_int(queued).is_equal(1)


func test_attack_targeting_queues_an_attack_order() -> void:
	# #107's other half: Attack entered its mode and then silently queued nothing.
	var attacker := _first_player_unit()
	var victim: Unit = null
	for unit: Unit in game._all_units():
		if unit.get_faction() != attacker.get_faction():
			victim = unit
			break
	assert_object(victim).is_not_null()

	# Stand the two next to each other so the fallback adjacency reach always applies.
	var beside := victim.movement.cell + Vector2i.LEFT
	attacker.movement.cell = beside

	game._on_left_click(attacker.movement.cell)
	_pick_menu_action(MainActionMenu.ATTACK, attacker)
	assert_int(game.game_state).is_equal(game.GameState.ATTACK_TARGETING)
	game._on_left_click(victim.movement.cell)

	var queued := 0
	for action: BaseAction in attacker.squad.action_queue:
		if action.actor == attacker and action is AttackAction:
			queued += 1
	assert_int(queued).is_equal(1)


# ------------------------------------------------------------------------------
#  Dev keys -- DevController owns them, and a mistyped action fires for nobody
# ------------------------------------------------------------------------------

# Real InputEvents are not delivered headless (gdUnit4 warns about it every run), so dev keys go
# to _input directly -- the same trick the click tests use for _on_left_click.
func _dev_key(action: String) -> InputEventAction:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	return press


func test_the_dev_overlay_hotkey_toggles_dev_mode() -> void:
	assert_bool(DevTools.enabled()).is_true()   # the gate on all three keys
	assert_object(game.dev_overlay).is_not_null()
	assert_bool(game.dev_overlay.visible).is_false()

	game.dev_controller._input(_dev_key("toggle_dev_overlay"))
	assert_bool(game.dev_overlay.visible).is_true()
	assert_int(game.game_state).is_equal(game.GameState.DEV_MODE)

	# Second press leaves the overlay up and drops back out of DEV_MODE.
	game.dev_controller._input(_dev_key("toggle_dev_overlay"))
	assert_int(game.game_state).is_equal(game.GameState.IDLE)


func test_the_reset_hotkey_rebuilds_the_board() -> void:
	# F2 moved file AND callback (_unhandled_input -> _input), so it is the key most likely to have
	# been silently dropped. The sandbox clears last_loaded_path, which would make reload a no-op,
	# so load a real fixture first -- otherwise this passes without reloading anything.
	game.scenario_manager.load_scenario("res://Scenarios/fixtures/SquadJoinLeave.tres")
	await await_idle_frame()
	var before: Unit = _first_player_unit()
	assert_object(before).is_not_null()

	game.dev_controller._input(_dev_key("dev_reset_scenario"))
	await await_idle_frame()
	# clear_board frees every unit, so the old instance going invalid IS the reload.
	assert_bool(is_instance_valid(before)).is_false()
	assert_object(_first_player_unit()).is_not_null()


# ------------------------------------------------------------------------------
#  Selection lifecycle -- the selection must never outlive its unit (#149)
# ------------------------------------------------------------------------------

func test_selection_released_when_selected_unit_dies() -> void:
	# The selection is STORED (#107) and nothing released it when its unit was freed.
	var unit := _first_player_unit()
	game._on_left_click(unit.movement.cell)
	assert_object(game.selected_unit).is_same(unit)

	unit.die()
	await await_idle_frame()
	# Asserted separately so a failure says WHICH half broke: queue_free is deferred, and
	# without the frame above the reference is still valid and the case proves nothing.
	assert_bool(is_instance_valid(unit)).is_false()
	# The TYPED read is the whole assertion -- a dangling reference compares `== null` as true
	# (measured), so an untyped check here cannot see the bug. Only resolving the ObjectID to
	# type-check it raises "Trying to assign invalid previously freed instance", which is the
	# production crash shape.
	var still_selected: Unit = game.selected_unit
	assert_object(still_selected).is_null()


func test_bug_report_plan_squad_survives_a_dead_selection() -> void:
	# The reported #149 crash: F3 during an AI turn read the dangling selection. The null
	# active_squad is a PRECONDITION -- with one set, _plan_squad returns before it ever looks.
	var unit := _first_player_unit()
	game._on_left_click(unit.movement.cell)
	assert_object(game.squad_manager.active_squad).is_null()

	unit.die()
	await await_idle_frame()
	var reporter: BugReporter = game.bug_reporter
	assert_object(reporter._plan_squad()).is_null()


func test_selection_released_when_the_board_is_cleared() -> void:
	# clear_board() frees every unit with a bare queue_free -- no unit_died -- so it needs its
	# own release. In play that is: select a unit, Esc, Restart, F3.
	var unit := _first_player_unit()
	game._on_left_click(unit.movement.cell)
	assert_object(game.selected_unit).is_same(unit)

	game.scenario_manager.clear_board()
	await await_idle_frame()
	var still_selected: Unit = game.selected_unit   # typed on purpose -- see the case above
	assert_object(still_selected).is_null()
