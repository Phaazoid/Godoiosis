# CaptureAction — the ORDER that claims an objective zone (#96 slice 3), first covered 2026-08-01.
#
# This class had ZERO test references of any kind. tests/flow/test_mission_controller.gd pins the
# capture STATE thoroughly (whole-zone claim, no double-register, wrong-kind and unknown zones), but
# nothing touched the action that produces it: not the stamp, not the queue gate, not execute(), and
# not the re-validation clause written for it in SquadPlanValidator. The registry law
# (tests/law/test_action_registry.gd) covers CAPTURE only structurally — it iterates the ActionType
# enum, so being listed in SIDE_CHANNEL_ORDER passes it automatically.
#
# What makes that a gap worth closing rather than a formality: this action exists to hold a FROZEN
# STAMP. Its cell, zone name and controller are captured at queue time precisely so a re-planned
# move cannot quietly capture somewhere else (Law #2 — the queue previewed THIS cell). That is the
# same shape as AttackAction.fired_attack, and #102 is the record of what happens when a stored
# order and a live lookup disagree about which thing an order refers to.
#
# Real scene, because init() reads game.zone_manager through the MissionController and the
# re-validation runs inside a real squad plan. Fixture is the #114 one — the instanced root MUST be
# named "Main" under /root; see tests/README.md → Testing the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

const POINT := "Alpha Point"
const POINT_CELL := Vector2i(4, 4)

var _main: Node
var game: Node2D
var mc: MissionController


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	# An empty board: clear_board() routes through mission_controller.reset(), the real
	# mission-start path, so no captured-zone state survives from whatever loaded before.
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	mc = game.mission_controller
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()   # off-map or unwalkable — the test's own setup is wrong
	return unit


func _paint(zone_name: String, kind: ZoneManager.Kind, cells: Array) -> void:
	for cell: Vector2i in cells:
		game.zone_manager.paint_cell(zone_name, kind, cell)


# A capture point at POINT_CELL with a player unit standing on it — the ordinary situation.
func _stand_on_a_point() -> Unit:
	_paint(POINT, ZoneManager.Kind.CAPTURE, [POINT_CELL])
	return _spawn(Team.Faction.PLAYER, POINT_CELL)


func _capture_order(unit: Unit, cell: Vector2i) -> CaptureAction:
	var action := CaptureAction.new()
	action.init(unit, cell, mc)
	return action


# --- the stamp ---

func test_init_stamps_the_zone_under_the_target_cell() -> void:
	var unit := _stand_on_a_point()
	var action := _capture_order(unit, POINT_CELL)

	assert_str(action.zone_name).is_equal(POINT)
	assert_that(action.cell).is_equal(POINT_CELL)
	assert_object(action.controller).is_same(mc)
	assert_that(action.action_type).is_equal(BaseAction.ActionType.CAPTURE)


func test_the_stamp_is_frozen_against_a_later_move() -> void:
	# The whole reason the fields exist. Walking the actor off the point afterwards must not
	# re-point the order at wherever it ended up — the order still names what the queue previewed.
	var unit := _stand_on_a_point()
	var action := _capture_order(unit, POINT_CELL)

	unit.movement.cell = Vector2i(9, 9)

	assert_that(action.cell).is_equal(POINT_CELL)
	assert_str(action.zone_name).is_equal(POINT)


func test_the_stamp_survives_the_zone_being_repainted_underneath_it() -> void:
	# A stamp that re-read the board would follow an edit made after the order was authored. The
	# order describes a decision already taken, so it must not.
	var unit := _stand_on_a_point()
	var action := _capture_order(unit, POINT_CELL)

	game.zone_manager.erase_cell(POINT_CELL)
	_paint("Bravo Point", ZoneManager.Kind.CAPTURE, [POINT_CELL])

	assert_str(action.zone_name).is_equal(POINT)


func test_the_description_names_the_stamped_zone_not_the_current_cell() -> void:
	var unit := _stand_on_a_point()
	var action := _capture_order(unit, POINT_CELL)
	unit.movement.cell = Vector2i(9, 9)

	assert_str(action.get_description()).contains(POINT)


# --- the queue-time gate (Law #3) ---

func test_a_capture_on_a_real_point_can_be_performed() -> void:
	var unit := _stand_on_a_point()
	assert_bool(_capture_order(unit, POINT_CELL).actor_can_perform()).is_true()


func test_a_cell_in_no_zone_cannot_be_captured() -> void:
	var unit := _stand_on_a_point()
	var action := _capture_order(unit, Vector2i(9, 9))   # nothing painted here

	assert_str(action.zone_name).is_equal("")
	assert_bool(action.actor_can_perform()).is_false()


func test_an_already_captured_zone_cannot_be_captured_again() -> void:
	var unit := _stand_on_a_point()
	var action := _capture_order(unit, POINT_CELL)
	assert_bool(action.actor_can_perform()).is_true()

	mc.capture(POINT)
	assert_bool(action.actor_can_perform()).is_false()   # the order is now pointless, not illegal


func test_a_capture_with_no_controller_cannot_be_performed() -> void:
	# Defensive: the controller is stamped because an action has no game ref of its own. If that
	# stamp is ever missed, the gate must refuse rather than execute() null-checking its way to a
	# silent no-op that still consumes the unit's main action.
	var unit := _stand_on_a_point()
	var action := CaptureAction.new()
	action.actor = unit
	action.action_type = BaseAction.ActionType.CAPTURE
	action.zone_name = POINT

	assert_bool(action.actor_can_perform()).is_false()


func test_the_queue_gate_does_not_check_the_zones_KIND() -> void:
	# DOCUMENTING ACTUAL BEHAVIOUR, not endorsing it. MainActionMenu gates the CAPTURE entry on
	# mission_controller.is_capture_zone_at(), which checks Kind == CAPTURE; actor_can_perform()
	# only checks that the cell is in SOME named zone. So the queue-time chokepoint is LOOSER than
	# the menu, and an order aimed at a PATROL zone queues and then executes as a silent no-op
	# (MissionController.capture() rejects the kind).
	#
	# Unreachable today: the menu is the only producer, CAPTURE sits in every archetype's
	# MAIN_ACTION_NEVER, and the Play API has no capture command. It stops being unreachable the
	# moment any of those three changes. Flagged for the dev rather than fixed here — gameplay code
	# is hand-typed, and the fix is a one-line kind check in actor_can_perform().
	var unit := _stand_on_a_point()
	_paint("Patrol Route", ZoneManager.Kind.PATROL, [Vector2i(6, 6)])
	var action := _capture_order(unit, Vector2i(6, 6))

	assert_str(action.zone_name).is_equal("Patrol Route")
	assert_bool(action.actor_can_perform()).is_true()    # <- the asymmetry
	action.execute()
	assert_bool(mc.is_zone_captured("Patrol Route")).is_false()   # ...and it does nothing


# --- execution ---

func test_execute_captures_the_stamped_zone() -> void:
	var unit := _stand_on_a_point()
	var action := _capture_order(unit, POINT_CELL)
	assert_bool(mc.is_zone_captured(POINT)).is_false()

	action.execute()
	assert_bool(mc.is_zone_captured(POINT)).is_true()


func test_execute_claims_the_zone_the_order_named_even_after_the_actor_moved() -> void:
	# Law #2 end to end: preview and execution must agree, and what was previewed is the stamp.
	var unit := _stand_on_a_point()
	_paint("Bravo Point", ZoneManager.Kind.CAPTURE, [Vector2i(8, 8)])
	var action := _capture_order(unit, POINT_CELL)

	unit.movement.cell = Vector2i(8, 8)   # standing somewhere else entirely by execution time
	action.execute()

	assert_bool(mc.is_zone_captured(POINT)).is_true()
	assert_bool(mc.is_zone_captured("Bravo Point")).is_false()


# --- the action registry ---

func test_capture_is_a_main_action_and_locks_the_unit() -> void:
	var unit := _stand_on_a_point()
	var action := _capture_order(unit, POINT_CELL)

	assert_bool(action.is_main_action()).is_true()
	assert_bool(BaseAction.SIDE_CHANNEL_ORDER.has(BaseAction.ActionType.CAPTURE)).is_true()
	assert_bool(game.squad_manager.queue_action(unit.squad, action)).is_true()
	assert_bool(unit.has_main_action_queued()).is_true()


# --- re-validation: the reason the stamp is frozen rather than live ---

func test_a_queued_capture_stays_valid_while_the_actor_holds_the_point() -> void:
	var unit := _stand_on_a_point()
	var action := _capture_order(unit, POINT_CELL)
	assert_bool(game.squad_manager.queue_action(unit.squad, action)).is_true()

	game.squad_manager.validate_squad_plan(unit.squad)
	assert_bool(action.is_valid).is_true()


# A unit standing NEXT to the point with a move onto it already queued, then a capture stamped at
# the projected destination — exactly what game.queue_capture builds, since it reads
# get_projected_destination() rather than the unit's current cell.
func _walk_onto_the_point() -> Array:
	_paint(POINT, ZoneManager.Kind.CAPTURE, [POINT_CELL])
	var start := POINT_CELL + Vector2i(1, 0)
	var unit := _spawn(Team.Faction.PLAYER, start)

	var path: Array[Vector2i] = [start, POINT_CELL]
	var move := MoveAction.new()
	move.init(unit, path, null)
	assert_bool(game.squad_manager.queue_action(unit.squad, move)).is_true()
	assert_that(unit.get_projected_destination()).is_equal(POINT_CELL)

	var capture := _capture_order(unit, unit.get_projected_destination())
	assert_bool(game.squad_manager.queue_action(unit.squad, capture)).is_true()
	return [unit, capture]


func test_a_capture_queued_behind_a_move_claims_the_tile_the_move_ends_on() -> void:
	var pair := _walk_onto_the_point()
	var capture: CaptureAction = pair[1]

	assert_that(capture.cell).is_equal(POINT_CELL)
	assert_str(capture.zone_name).is_equal(POINT)
	game.squad_manager.validate_squad_plan((pair[0] as Unit).squad)
	assert_bool(capture.is_valid).is_true()


func test_cancelling_the_move_under_it_invalidates_the_queued_capture() -> void:
	# SquadPlanValidator._revalidate_captures, and the payoff of freezing the stamp. Cancelling the
	# move drops the unit back to a hold at its ORIGINAL cell, so the order it authored — capture
	# THAT tile — is no longer something it can do. It goes RED rather than silently re-pointing at
	# wherever the unit ended up: invalid is a state you fall into, never one you choose.
	#
	# Note the ordering this test had to be built around, which is itself the rule working: a
	# capture is a MAIN action, so once queued it locks the move option and you cannot re-plan a
	# move underneath it. Cancelling is the only way to strand one, which is why that is the case
	# with teeth here.
	var pair := _walk_onto_the_point()
	var unit: Unit = pair[0]
	var capture: CaptureAction = pair[1]

	game.squad_manager.cancel_move_for_unit(unit)

	assert_bool(capture.is_valid).override_failure_message(
		"A queued capture survived the move under it being cancelled — either _revalidate_captures stopped running, or the stamp is being re-read live."
		).is_false()
	assert_str("\n".join(capture.validation_errors)).contains("capture point")
	# The stamp itself is untouched: the order still names what it always named.
	assert_that(capture.cell).is_equal(POINT_CELL)
	assert_str(capture.zone_name).is_equal(POINT)
