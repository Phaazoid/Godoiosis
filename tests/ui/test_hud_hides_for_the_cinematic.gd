# The cinematic owns the frame (#722): four HUD surfaces stand down while a pass shows a fight,
# and MissionStatusPanel does not.
#
# Read at the RENDERED node, test_end_turn_button.gd's doctrine. Two kinds of case here and the
# split is deliberate:
#   - the GATE cases set CameraController.playback_cinematic directly. That is a direct-set
#     precondition and is blind to whether anything ever publishes it, which is what the last case
#     is for.
#   - the WIRE case drives a real OrderExecutor pass. Nothing else can see a missing publish, and
#     nothing else can see the ordering trap: the release fires BEFORE executing_plan is cleared,
#     so a re-apply routed through refresh_action_queue would leave the queue panel hidden for the
#     rest of the mission and every gate case above would still pass.
#
# Real game scene (the #114 fixture -- root MUST be named "Main" under /root).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

var _main: Node
var game: Node2D
var _was_zoom: int


func before_test() -> void:
	_was_zoom = PlayerSettings.choice_of(PlayerSettings.Setting.BATTLE_ZOOM_MODE)
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
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, _was_zoom)
	get_tree().root.remove_child(_main)
	_main.free()
	await await_idle_frame()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


# Put all four surfaces up, so no assertion below can pass vacuously. Three of the four have a
# CONTENT gate that has to be satisfied first; End Turn is up on its own.
func _raise_the_hud(unit: Unit) -> void:
	game.refresh_action_queue(unit.squad)
	game.unit_info_panel.set_unit(unit, false, game._board())
	game.hover_info_panel.show_hover(unit, null, "Ground", [] as Array[String], Vector2.ZERO)
	game.refresh_end_turn_button()
	assert_bool(game.squad_action_queue_control.visible).override_failure_message(
			"fixture: the queue panel was already down, so hiding it proves nothing").is_true()
	assert_bool(game.unit_info_panel.visible).override_failure_message(
			"fixture: the inspect panel was already down").is_true()
	assert_bool(game.hover_info_panel.visible).override_failure_message(
			"fixture: the hover card was already down").is_true()
	assert_bool(game.end_turn_button.visible).override_failure_message(
			"fixture: End Turn was already down").is_true()


# A unit with an order in the queue, so refresh_action_queue has rows to draw. The aim hits nobody,
# which is fine for the gate cases: they never run the plan. `_queue_action` is the raw door, since
# the queue-time whiff gate would refuse an aim at empty ground.
func _unit_with_a_plan(cell := Vector2i(2, 2)) -> Unit:
	var unit := _spawn(Team.Faction.PLAYER, cell)
	unit.squad._queue_action(AttackAction.declare(unit, cell, cell + Vector2i(1, 0)))
	return unit


# ...and a plan that will actually PLAY. An aim at nobody is marked invalid by the validator, and
# execute_orders hands a human squad control back before it claims the camera at all -- so a pass
# built on one publishes nothing and every recording below would be empty for the wrong reason.
# ORTHOGONAL, because a unit with no weapon falls back to Manhattan-1 reach.
func _attacker_with_a_real_target() -> Unit:
	var attacker := _spawn(Team.Faction.PLAYER, Vector2i(2, 2))
	_spawn(Team.Faction.ENEMY, Vector2i(3, 2))
	attacker.squad._queue_action(AttackAction.declare(attacker, Vector2i(2, 2), Vector2i(3, 2)))
	return attacker


# ==============================================================================
#  The gate
# ==============================================================================

func test_a_cinematic_takes_the_four_surfaces_down() -> void:
	var unit := _unit_with_a_plan()
	_raise_the_hud(unit)

	game.camera_controller.playback_cinematic = true

	assert_bool(game.squad_action_queue_control.visible).override_failure_message(
			"the queue panel drew over the cinematic").is_false()
	assert_bool(game.unit_info_panel.visible).override_failure_message(
			"the inspect panel drew over the cinematic").is_false()
	assert_bool(game.hover_info_panel.visible).override_failure_message(
			"the hover card drew over the cinematic").is_false()
	assert_bool(game.end_turn_button.visible).override_failure_message(
			"End Turn drew over the cinematic").is_false()


# The dev's ruling, and the reason this is not `ui_layer.visible = false`: the objectives, the build
# stamp and #182's tutorial instruction row have to survive the moment the lesson is demonstrated.
#
# is_visible_in_tree(), NOT visible: a UILayer-wide hide would leave this node's own `visible` true
# and take the panel off the screen anyway, so the weaker assertion cannot see the implementation
# this ruling exists to refuse.
func test_the_mission_status_panel_stays_up_through_a_cinematic() -> void:
	var unit := _unit_with_a_plan()
	_raise_the_hud(unit)
	assert_bool(game.mission_status_panel.is_visible_in_tree()).override_failure_message(
			"fixture: the status panel was already off screen").is_true()

	game.camera_controller.playback_cinematic = true

	assert_bool(game.mission_status_panel.is_visible_in_tree()).override_failure_message(
			"the mission status panel went down with the rest of the HUD").is_true()


func test_the_hud_comes_back_when_the_pass_ends() -> void:
	var unit := _unit_with_a_plan()
	_raise_the_hud(unit)

	game.camera_controller.playback_cinematic = true
	game.camera_controller.playback_cinematic = false

	assert_bool(game.squad_action_queue_control.visible).override_failure_message(
			"the queue panel never came back").is_true()
	assert_bool(game.unit_info_panel.visible).override_failure_message(
			"the inspect panel never came back").is_true()
	assert_bool(game.hover_info_panel.visible).override_failure_message(
			"the hover card never came back").is_true()
	assert_bool(game.end_turn_button.visible).override_failure_message(
			"End Turn never came back").is_true()


# A surface whose content rule said "down" must STAY down when the cinematic ends -- the release
# re-applies each gate, it does not raise anything.
func test_the_release_does_not_raise_a_surface_its_own_rule_had_taken_down() -> void:
	var unit := _unit_with_a_plan()
	_raise_the_hud(unit)
	game.unit_info_panel.clear()

	game.camera_controller.playback_cinematic = true
	game.camera_controller.playback_cinematic = false

	assert_bool(game.unit_info_panel.visible).override_failure_message(
			"a closed inspect panel was reopened by the end of a cinematic").is_false()


# THE CASE THE OUTSIDE-WRITE IMPLEMENTATION FAILS. HoverPresenter re-runs this gate on every
# cursor-CELL change, and a player's own Execute never leaves game_state IDLE -- so a one-shot
# `visible = false` at the claim edge is undone by the first mouse move over the board.
func test_the_hover_card_cannot_reappear_mid_cinematic() -> void:
	var unit := _unit_with_a_plan()
	_raise_the_hud(unit)
	game.camera_controller.playback_cinematic = true

	game.hover_info_panel.show_hover(unit, null, "Ground", [] as Array[String], Vector2.ZERO)

	assert_bool(game.hover_info_panel.visible).override_failure_message(
			"a hover during playback put the card back over the cinematic").is_false()

	# ...and the content answer it was given survived, so the card returns when the pass does.
	game.camera_controller.playback_cinematic = false
	assert_bool(game.hover_info_panel.visible).override_failure_message(
			"the hover the cinematic swallowed was lost rather than deferred").is_true()


# Hidden is not closed. HoverPresenter asks is_showing()/is_showing_unit() to decide where the
# hover card parks and whether it would be a second card for the same unit, so a panel that
# answered "no unit is open" while merely hidden would move the card mid-pass.
func test_a_hidden_inspect_panel_still_says_which_unit_it_holds() -> void:
	var unit := _unit_with_a_plan()
	_raise_the_hud(unit)
	game.camera_controller.playback_cinematic = true

	assert_bool(game.unit_info_panel.is_showing()).override_failure_message(
			"a hidden inspect panel claimed to hold nothing").is_true()
	assert_bool(game.unit_info_panel.is_showing_unit(unit)).override_failure_message(
			"a hidden inspect panel let go of its unit").is_true()


# ==============================================================================
#  The wire -- a real pass, which is the only thing that can see a missing publish
# ==============================================================================

# A pass CANNOT BE SAMPLED MID-FLIGHT HEADLESSLY, and the first draft of this case tried: Pacing
# collapses every beat to zero, so the whole pass runs to completion inside one call and there is no
# frame between the two edges to look at (CLAUDE.md records the same finding from #672). The
# non-vacuity guard is what said so rather than the case quietly passing on an unobserved pass.
#
# So RECORD the edges instead of racing them. `visibility_changed` fires on each real change (Godot
# early-outs on an unchanged `visible`), which makes the transitions readable afterwards and does
# not care whether the pass spanned a frame. End Turn is the surface watched because it has no
# content rule of its own -- it is up unless a cinematic put it down, so a recording can never fill
# up with someone else's writes.
func test_a_real_cinematic_pass_takes_the_hud_down_and_puts_it_back() -> void:
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, PlayerSettings.BattleZoom.ALWAYS)
	var attacker := _attacker_with_a_real_target()
	game.refresh_action_queue(attacker.squad)
	_raise_the_hud(attacker)
	var seen := _record_visibility(game.end_turn_button)

	await game.order_executor.execute_orders(attacker)

	assert_bool(attacker.squad.has_acted).override_failure_message(
			"fixture: the pass never ran, so an empty recording would prove nothing").is_true()
	assert_array(seen).override_failure_message(
			"a cinematic pass never moved the HUD at all -- nothing published playback_cinematic") \
		.is_equal([false, true])
	assert_bool(game.end_turn_button.visible).override_failure_message(
			"the HUD never came back after the pass").is_true()

	# ...and the queue panel's own gate still works afterwards. THE ORDERING TRAP: the release fires
	# BEFORE executing_plan is cleared, so a re-apply routed through refresh_action_queue (which
	# refuses to run mid-pass, #361) would leave this panel latched hidden for the rest of the
	# mission. The pass emptied this squad's queue, so a fresh plan is what asks the question.
	var next := _unit_with_a_plan(Vector2i(6, 6))
	game.refresh_action_queue(next.squad)
	assert_bool(game.squad_action_queue_control.visible).override_failure_message(
			"the queue panel stayed hidden after a cinematic -- the hide latched").is_true()


# The setting is honoured for free, because playback_cinematic is derived from the beat profiles:
# with the zoom OFF every beat is BOARD, so the pass paces plainly and the HUD never moves.
func test_a_pass_with_the_battle_zoom_off_leaves_the_hud_alone() -> void:
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, PlayerSettings.BattleZoom.OFF)
	var attacker := _attacker_with_a_real_target()
	game.refresh_action_queue(attacker.squad)
	_raise_the_hud(attacker)
	var seen := _record_visibility(game.end_turn_button)

	await game.order_executor.execute_orders(attacker)

	assert_bool(attacker.squad.has_acted).override_failure_message(
			"fixture: the pass never ran, so an empty recording would prove nothing").is_true()
	assert_array(seen).override_failure_message(
			"the HUD moved for a pass the player asked to play plain").is_empty()


# Every change to `node.visible` from now on, in order. An ARRAY rather than a bool because a
# GDScript lambda captures a local by VALUE -- a flag set in here would never reach the caller.
func _record_visibility(node: Control) -> Array[bool]:
	var seen: Array[bool] = []
	node.visibility_changed.connect(func() -> void: seen.append(node.visible))
	return seen
