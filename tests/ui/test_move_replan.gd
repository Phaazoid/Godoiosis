# Re-planning a move (#417): a unit that already has a move queued still gets the Move row, and
# picking it CANCELS that order before re-entering move planning. Backing out of the re-plan
# therefore leaves the unit with no move at all -- the old order is spent on entry, not held in
# reserve.
#
# Why the whole sequence rather than populate() alone. Three things only the real path shows:
#   * the pick runs through ActionMenuController's cancelled-before-action_selected ordering,
#     which fires game.clear_selection() on the way INTO move mode (the #105/#107 trap);
#   * cancel_move_for_unit leaves a hold-position filler behind, so without revert_if_only_hold
#     a solo unit that backs out strands its squad ACTIVE behind a panel with no X and no undo;
#   * Squad._queue_action displaces same-actor same-type orders, so "replaces" is a claim about
#     the queue's CONTENTS, not just about the newest move's destination.
# So every case here drives select -> press the real button -> click a tile, and asserts on the queue.
#
# Group Move is deliberately still withdrawn once a move is queued -- #417 scoped to Move, since
# queue_group_move's all-or-nothing rollback cancels EVERY member's move. Pinned below so the
# scope is a decision rather than a gap.
#
# Real game scene (the #114 fixture -- root MUST be named "Main").
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

const START := Vector2i(1, 0)
const FIRST_DEST := Vector2i(2, 0)
const SECOND_DEST := Vector2i(3, 0)

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
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn_player(cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), cell)
	assert_object(unit).is_not_null()
	game.turn_manager.set_active_faction(Team.Faction.PLAYER)
	return unit


# The unit's REAL moves -- hold-position fillers are not orders (Unit.has_action_type_queued skips
# them for the same reason), so a test counting rows would count the filler this feature creates.
func _real_moves(unit: Unit) -> Array:
	var moves: Array = []
	for action in unit.squad.action_queue:
		if action.actor == unit and action is MoveAction and not (action as MoveAction).is_hold_position:
			moves.append(action)
	return moves


# Select through the one select door and open the unit's real menu. Clicking the PROJECTED cell is
# the player's gesture: with a move queued, the ghost is what's under the pointer.
#
# The queued-for-deletion skip is load-bearing, not hygiene: a pressed menu cleans up with
# queue_free(), which does not detach until the frame ends, so opening a second menu in the same
# case leaves TWO controllers parented to game. Taking the first one found meant re-pressing the
# STALE menu -- the assertions passed anyway (same unit, same rows) while the live menu was never
# touched, which is exactly the shape of a case that cannot fail.
func _open_menu(unit: Unit) -> Node:
	game._click_idle(unit.get_projected_destination())
	assert_object(game.selected_unit) \
		.override_failure_message("clicking the unit did not select it").is_same(unit)
	for child in game.get_children():
		if child is ActionMenuController and not child.is_queued_for_deletion():
			return child
	return null


func _find_button(node: Node, label: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text == label:
			return child as Button
		var found := _find_button(child, label)
		if found != null:
			return found
	return null


# Press a row the way a player does: the Button's own signal, so the controller's
# cancelled-then-action_selected ordering runs. Returns false when the row isn't on the menu.
func _press_row(unit: Unit, label: String) -> bool:
	var controller := _open_menu(unit)
	assert_object(controller).override_failure_message("no action menu opened").is_not_null()
	var button := _find_button(controller, label)
	if button == null:
		return false
	assert_bool(button.disabled) \
		.override_failure_message("the %s row was listed but greyed" % label).is_false()
	button.pressed.emit()
	await await_idle_frame()   # let the pressed menu's queue_free() land before the next one opens
	return true


# The player's whole move gesture: select, press Move, click a tile.
func _order_move(unit: Unit, dest: Vector2i) -> void:
	assert_bool(await _press_row(unit, "Move")) \
		.override_failure_message("the Move row was not on the menu").is_true()
	assert_int(game.game_state).override_failure_message("pressing Move did not enter move mode") \
		.is_equal(game.GameState.CHOOSING_MOVE)
	game._click_choosing_move(dest)


# ==============================================================================


func test_move_is_still_offered_once_a_move_is_queued() -> void:
	var unit := _spawn_player(START)
	await _order_move(unit, FIRST_DEST)
	assert_int(_real_moves(unit).size()) \
		.override_failure_message("fixture failed to queue the first move").is_equal(1)

	assert_array(game.main_action_menu.populate(unit)) \
		.override_failure_message("Move vanished from the menu once a move was queued") \
		.contains([MainActionMenu.MOVE])


# The cancel-on-entry half. Pressing Move a second time must leave the OLD order gone before the
# player has picked anything -- that is what makes backing out mean "no move".
func test_picking_move_again_drops_the_queued_order() -> void:
	var unit := _spawn_player(START)
	await _order_move(unit, FIRST_DEST)

	assert_bool(await _press_row(unit, "Move")) \
		.override_failure_message("the Move row was not on the menu").is_true()

	assert_int(game.game_state).is_equal(game.GameState.CHOOSING_MOVE)
	assert_array(_real_moves(unit)) \
		.override_failure_message("the queued move survived re-entering move planning").is_empty()


# Backing out falls back to NO action -- and the squad must go inactive with it, or it sits active
# behind a queue panel holding nothing but a hold filler, which has no cancel button.
func test_backing_out_of_a_re_plan_leaves_the_unit_with_no_move() -> void:
	var unit := _spawn_player(START)
	await _order_move(unit, FIRST_DEST)
	assert_object(game.squad_manager.active_squad) \
		.override_failure_message("fixture failed to activate the squad").is_same(unit.squad)

	assert_bool(await _press_row(unit, "Move")).is_true()
	game.exit_current_mode()   # right-clicking out of the pick

	assert_array(_real_moves(unit)) \
		.override_failure_message("backing out left a move queued").is_empty()
	assert_object(game.squad_manager.active_squad) \
		.override_failure_message("the squad stayed active on a hold-only queue").is_null()
	assert_that(unit.get_projected_destination()) \
		.override_failure_message("the unit is still projected onto its abandoned destination") \
		.is_equal(START)


# Re-planning REPLACES. Counting is the assertion that matters: a version that queued the new move
# beside the old one would still report the new destination on whichever it found first.
func test_re_planning_replaces_rather_than_stacking() -> void:
	var unit := _spawn_player(START)
	await _order_move(unit, FIRST_DEST)
	await _order_move(unit, SECOND_DEST)

	var moves: Array = _real_moves(unit)
	assert_int(moves.size()) \
		.override_failure_message("re-planning stacked a second move instead of replacing").is_equal(1)
	var move: MoveAction = moves[0]
	assert_that(move.destination).is_equal(SECOND_DEST)
	assert_bool(move.is_valid).is_true()
	assert_that(unit.get_projected_destination()).is_equal(SECOND_DEST)


# The scoping decision, pinned: #417 relaxed Move alone. Both rows read one gate (#443), so this is
# what stops the Group Move clause being deleted as an apparent leftover.
func test_group_move_stays_withdrawn_once_a_move_is_queued() -> void:
	var leader := _spawn_player(START)
	var member := _spawn_player(Vector2i(0, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(member, leader.squad)

	assert_array(game.main_action_menu.populate(leader)) \
		.override_failure_message("fixture: Group Move was never offered to begin with") \
		.contains([MainActionMenu.GROUP_MOVE])

	await _order_move(leader, FIRST_DEST)

	var options: Array = game.main_action_menu.populate(leader)
	assert_array(options).override_failure_message("Move should still be offered (#417)") \
		.contains([MainActionMenu.MOVE])
	assert_bool(options.has(MainActionMenu.GROUP_MOVE)) \
		.override_failure_message("Group Move was offered over a queued move -- #417 scoped to Move") \
		.is_false()
