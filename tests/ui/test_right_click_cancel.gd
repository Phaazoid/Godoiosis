# Right-click's LIFO undo (#228), driven through the real dispatcher.
#
# Deliberately NOT at the squad layer. tests/squad/test_cancel_semantics.gd re-implements
# _on_queue_cancel_requested's cascade in a local helper rather than calling it, so it is
# structurally blind to anything that changes game.gd's handler -- and the handler IS the
# feature here. This suite drives game._on_right_click() on a live board, which is also what
# makes it cover BOTH views at once: the 3D picker calls that same dispatcher (battle3d._cancel).
#
# The two cases with teeth are ORDERING ones, and neither can be reached by setting game_state
# directly: right-click has to close an open mode BEFORE it will pop anything, and a group move
# has to come off the queue as ONE gesture rather than one member per press.
#
# Fixture is test_game_scene_smoke.gd's (#114): Main.tscn named + parented exactly as in
# production, or game.gd's absolute /root/Main/DevOverlay lookup nulls out.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.spawn_sandbox()
	# _ready leaves the board in MENU behind Mission Select (#96); the sandbox row normally
	# clears it.
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	# clear_board()/spawn_unit() leave nodes parentless for one frame BY DESIGN; without this
	# gdUnit4 samples them as orphans. A real leak survives the frame and still reports.
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


# ------------------------------------------------------------------------------
#  Helpers
# ------------------------------------------------------------------------------

func _player_units() -> Array[Unit]:
	var found: Array[Unit] = []
	for unit: Unit in game._all_units():
		if unit.get_faction() == Team.Faction.PLAYER:
			found.append(unit)
	return found


func _first_enemy() -> Unit:
	for unit: Unit in game._all_units():
		if unit.get_faction() == Team.Faction.ENEMY:
			return unit
	return null


# Pick from the open menu the way the real control does: ActionMenuController emits `cancelled`
# BEFORE `action_selected` even on a genuine pick, so clear_selection() runs on the way INTO the
# mode. A test that sets game_state instead cannot see that ordering (#105/#107).
func _pick_menu_action(action_id: int, unit: Unit) -> void:
	var controller: ActionMenuController = null
	for child in game.get_children():
		if child is ActionMenuController:
			controller = child
	assert_object(controller).is_not_null()
	controller.cancelled.emit(controller)
	controller.action_selected.emit(action_id, unit)


# A cell this unit can actually reach, asked of the real move range rather than assumed -- the
# sandbox board is authored content and its walkable neighbours are not this suite's business.
func _a_step_for(unit: Unit) -> Vector2i:
	for cell: Vector2i in game.compute_move_range(unit).reachable.keys():
		if cell != unit.movement.cell:
			return cell
	return unit.movement.cell


# Queue one move through the whole player path: select -> menu -> click a destination.
# Selects at the PROJECTED cell, not the live one: the board draws one sprite per unit at its
# projected position, so a unit with a move already queued is not clickable where it stands (#126).
func _queue_move(unit: Unit) -> void:
	game._on_left_click(unit.get_projected_destination())
	_pick_menu_action(MainActionMenu.MOVE, unit)
	var step := _a_step_for(unit)
	assert_that(step).is_not_equal(unit.movement.cell)   # the board must offer a step at all
	game._on_left_click(step)


# Park a unit on a walkable, unoccupied neighbour of `cell`, so an adjacency-range attack has
# something to aim at. Board arrangement only — the ordering under test is the right-click
# sequence, not how the two ended up adjacent. Asks the real board rather than assuming a
# neighbour is free: the sandbox is authored content.
func _park_beside(unit: Unit, cell: Vector2i) -> bool:
	for step: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var spot := cell + step
		if not game._board().is_walkable(spot):
			continue
		if game.get_unit_at_cell(spot) != null:
			continue
		unit.movement.set_cell(spot)
		return true
	return false


# Orders in a squad's queue that the player actually gave -- hold-position fillers are queued by
# setup_hold_move_actions for every member that isn't moving, and are not anybody's order.
func _real_orders(squad: Squad) -> Array[BaseAction]:
	var orders: Array[BaseAction] = []
	if squad == null or not is_instance_valid(squad):
		return orders
	for action: BaseAction in squad.action_queue:
		if action is MoveAction and (action as MoveAction).is_hold_position:
			continue
		orders.append(action)
	return orders


func _active_orders() -> Array[BaseAction]:
	return _real_orders(game.squad_manager.active_squad)


# ------------------------------------------------------------------------------
#  Precedence: the open mode wins, and only then the queue
# ------------------------------------------------------------------------------

func test_right_click_closes_an_open_mode_and_leaves_the_queue_alone() -> void:
	# The whole point of the dev's "mode first" call: changing your mind mid-aim must never cost
	# you an order you queued earlier. Fire the real sequence -- queue, THEN open a mode.
	var unit := _player_units()[0]
	_queue_move(unit)
	assert_int(_active_orders().size()).is_equal(1)

	game._on_left_click(unit.movement.cell)
	_pick_menu_action(MainActionMenu.ATTACK, unit)
	assert_int(game.game_state).is_not_equal(game.GameState.IDLE)   # a mode really is open

	game._on_right_click()

	assert_int(game.game_state).is_equal(game.GameState.IDLE)
	assert_int(_active_orders().size()).is_equal(1)   # the order survived the mode exit


func test_a_second_right_click_pops_the_order() -> void:
	# The other half of the same sequence: once the board is at rest, the press undoes.
	var unit := _player_units()[0]
	_queue_move(unit)
	game._on_left_click(unit.movement.cell)
	_pick_menu_action(MainActionMenu.ATTACK, unit)

	game._on_right_click()   # closes the mode
	game._on_right_click()   # pops the order

	assert_int(_active_orders().size()).is_equal(0)


func test_right_click_from_rest_pops_the_last_order() -> void:
	var unit := _player_units()[0]
	_queue_move(unit)
	assert_int(_active_orders().size()).is_equal(1)

	game._on_right_click()

	assert_int(_active_orders().size()).is_equal(0)


# ------------------------------------------------------------------------------
#  What one press takes back
# ------------------------------------------------------------------------------

func test_a_group_move_pops_as_one_gesture() -> void:
	# A formation is ONE decision, so one press takes the whole thing -- this is the entire
	# reason BaseAction.batch_id exists. Popping member-by-member would leave a half-dissolved
	# formation the validator then has to refuse.
	var units := _player_units()
	assert_int(units.size()).is_greater(1)   # the sandbox must field a squad-able pair

	# join_squad is the production call the squad-up target pick closes over (game.gd:792).
	var leader := units[1]
	var member := units[2]
	game.squad_manager.join_squad(member, leader.squad)
	assert_int(leader.squad.get_members().size()).is_equal(2)

	game._on_left_click(leader.movement.cell)
	_pick_menu_action(MainActionMenu.GROUP_MOVE, leader)
	assert_int(game.game_state).is_equal(game.GameState.CHOOSING_GROUP_MOVE)

	var destination := Vector2i.ZERO
	for cell: Vector2i in game.compute_move_range(leader).reachable.keys():
		if cell != leader.movement.cell and game.group_move_followable.has(cell):
			destination = cell
			break
	assert_that(destination).is_not_equal(Vector2i.ZERO)   # the board must offer a followable cell

	game._on_left_click(destination)
	var squad := leader.squad
	assert_int(_real_orders(squad).size()).is_equal(2)   # both members were ordered

	game._on_right_click()

	assert_int(_real_orders(squad).size()).is_equal(0)   # ONE press, both moves gone


func test_hold_fillers_are_never_what_a_press_pops() -> void:
	# Activating a squad queues a hold for every member with no move. Those are not orders, and
	# cancelling one only makes cancel_move_for_unit queue another -- a press that "undid" one
	# would look like a dead button. Nothing to undo must stay nothing to undo.
	var units := _player_units()
	var leader := units[1]
	game.squad_manager.join_squad(units[2], leader.squad)
	game.squad_manager.setup_hold_move_actions(leader.squad)
	var holds := leader.squad.action_queue.size()
	assert_int(holds).is_greater(0)          # the fixture really did produce fillers
	assert_int(_real_orders(leader.squad).size()).is_equal(0)

	assert_array(game.squad_manager.last_gesture_actions(leader.squad)).is_empty()

	game._on_right_click()

	assert_int(leader.squad.action_queue.size()).is_equal(holds)   # untouched


func test_popping_a_main_leaves_the_co_queued_move_standing() -> void:
	# The cancel cascade is ONE-WAY, and a LIFO pop inherits that direction rather than
	# re-authoring it (game.gd routes every removal through _on_queue_cancel_requested).
	#
	# Note the other direction is UNREACHABLE here by design, not untested: MoveAction's
	# move-before-main rule refuses a move to a unit that has locked a main, so the queue can
	# never end up [main, move] with the move newest -- a pop always meets the main first.
	var attacker := _player_units()[0]
	var victim := _first_enemy()
	assert_object(victim).is_not_null()

	_queue_move(attacker)                                        # gesture 1
	assert_bool(_park_beside(victim, attacker.get_projected_destination())).is_true()

	game._on_left_click(attacker.get_projected_destination())
	_pick_menu_action(MainActionMenu.ATTACK, attacker)
	game._on_left_click(victim.movement.cell)                    # gesture 2

	var squad := attacker.squad
	var mains := 0
	for action: BaseAction in squad.action_queue:
		if action.is_main_action():
			mains += 1
	assert_int(mains).is_equal(1)   # the attack really queued, or this case tests nothing

	game._on_right_click()

	var left := _real_orders(squad)
	assert_int(left.size()).is_equal(1)                                    # only the attack went
	assert_int(left[0].action_type).is_equal(BaseAction.ActionType.MOVE)   # the move stands


# ------------------------------------------------------------------------------
#  Nothing to undo
# ------------------------------------------------------------------------------

func test_right_click_on_an_empty_board_state_is_a_no_op() -> void:
	assert_object(game.squad_manager.active_squad).is_null()

	game._on_right_click()

	assert_int(game.game_state).is_equal(game.GameState.IDLE)
	assert_object(game.squad_manager.active_squad).is_null()


func test_pressing_past_the_last_order_stays_quiet() -> void:
	# Repeated presses after the queue empties must not crash or resurrect an activation --
	# revert_if_only_hold clears the queue out from under the pop loop when the last real order
	# goes, and a stale entry re-queueing a hold would silently reactivate the squad.
	var unit := _player_units()[0]
	_queue_move(unit)

	game._on_right_click()
	game._on_right_click()
	game._on_right_click()

	assert_object(game.squad_manager.active_squad).is_null()
	assert_int(game.game_state).is_equal(game.GameState.IDLE)
