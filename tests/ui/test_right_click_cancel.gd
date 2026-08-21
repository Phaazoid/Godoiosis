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


func test_a_second_right_click_reaches_the_queue() -> void:
	# The other half of the same sequence: once the board is at rest, the press acts on the queue.
	# The newest gesture here is the MOVE, so what it reaches is the re-plan rung (#417 round 2)
	# rather than the undo -- asserted on game_state, because the order count alone cannot tell
	# the two apart: re-planning spends the order on entry, so both leave zero behind.
	var unit := _player_units()[0]
	_queue_move(unit)
	game._on_left_click(unit.movement.cell)
	_pick_menu_action(MainActionMenu.ATTACK, unit)

	game._on_right_click()   # closes the mode
	game._on_right_click()   # reaches the queue: the move re-opens its planning

	assert_int(game.game_state).is_equal(game.GameState.CHOOSING_MOVE)
	assert_int(_active_orders().size()).is_equal(0)


func test_right_click_from_rest_reopens_a_queued_move() -> void:
	# The dev's cycle, rung two: a queued move is not deleted, it is re-planned -- exactly as if
	# you had pressed Move again. Same assertion pair as above, and for the same reason.
	var unit := _player_units()[0]
	_queue_move(unit)
	assert_int(_active_orders().size()).is_equal(1)

	game._on_right_click()

	assert_int(game.game_state).is_equal(game.GameState.CHOOSING_MOVE)
	assert_int(_active_orders().size()).is_equal(0)


# Rung three. Nothing in game.gd implements this -- planning already spent the order on entry, so
# leaving the mode is the outright cancel. Pinned because it is the half of the cycle the dev
# asked for by name, and a future "restore the move on abort" would break it silently.
func test_right_clicking_out_of_the_re_plan_cancels_outright() -> void:
	var unit := _player_units()[0]
	_queue_move(unit)

	game._on_right_click()   # re-opens planning
	assert_int(game.game_state).is_equal(game.GameState.CHOOSING_MOVE)
	game._on_right_click()   # and out

	assert_int(game.game_state).is_equal(game.GameState.IDLE)
	assert_int(_active_orders().size()).is_equal(0)
	assert_that(unit.get_projected_destination()).is_equal(unit.movement.cell)


# The half an order count cannot see: re-entry has to SELECT the unit, because _click_choosing_move
# reads game.selected_unit and nothing else. Without it the mode opens onto nobody and the next
# click queues nothing -- which is #107's bug, one door along.
func test_the_re_planned_unit_is_the_one_the_next_click_moves() -> void:
	var unit := _player_units()[0]
	_queue_move(unit)

	game._on_right_click()

	assert_object(game.selected_unit).is_same(unit)
	var step := _a_step_for(unit)
	assert_that(step).is_not_equal(unit.movement.cell)
	game._on_left_click(step)

	var orders := _active_orders()
	assert_int(orders.size()).is_equal(1)
	assert_object(orders[0].actor).is_same(unit)
	assert_that((orders[0] as MoveAction).destination).is_equal(step)


# ------------------------------------------------------------------------------
#  What one press takes back
# ------------------------------------------------------------------------------

func test_a_group_move_pops_as_one_gesture() -> void:
	# A formation is ONE decision, so one press takes the whole thing -- this is the entire
	# reason BaseAction.batch_id exists. Popping member-by-member would leave a half-dissolved
	# formation the validator then has to refuse.
	#
	# It also pins #417 round 2's SCOPE: the re-plan rung fires for a lone move only, so a
	# formation still pops rather than re-opening planning. And it is where the pop loop's own
	# has() guard is exercised -- cancelling the first move fires revert_if_only_hold, which
	# clears the queue out from under the loop before it reaches the second.
	var units := _player_units()
	assert_int(units.size()).is_greater(2)   # the sandbox must field units[1] and units[2]

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
	#
	# The FILTER is asserted directly below, and that is deliberate: a filler is stamped batch_id 0
	# because setup_hold_move_actions calls squad._queue_action past queue_action's door, so
	# last_gesture_actions is the whole rule. The press half cannot reach it -- see the note there.
	var units := _player_units()
	assert_int(units.size()).is_greater(2)   # the sandbox must field units[1] and units[2]
	var leader := units[1]
	game.squad_manager.join_squad(units[2], leader.squad)
	game.squad_manager.setup_hold_move_actions(leader.squad)
	var holds := leader.squad.action_queue.size()
	assert_int(holds).is_greater(0)          # the fixture really did produce fillers
	assert_int(_real_orders(leader.squad).size()).is_equal(0)

	assert_array(game.squad_manager.last_gesture_actions(leader.squad)).is_empty()

	# A squad holding NOTHING BUT fillers is unreachable in play -- revert_if_only_hold clears the
	# queue and drops active_squad the moment the last real order leaves. So this press runs against
	# a null active_squad and returns at _pop_last_gesture's first guard; it pins that the outer
	# guard holds, NOT that the filter does. Asserted rather than left implied, because a reader
	# would otherwise take the untouched queue below for evidence the filter ran.
	assert_object(game.squad_manager.active_squad).is_null()

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
	# The whole cycle, then one press past the end of it: re-plan, out, nothing. Presses beyond
	# the last order must not crash or resurrect an activation -- re-planning drops the squad
	# through revert_if_only_hold, and a third press meets a null active_squad.
	# (The pop LOOP's own out-from-under guard is exercised by the group-move case above; a lone
	# move never reaches the loop any more.)
	var unit := _player_units()[0]
	_queue_move(unit)

	game._on_right_click()
	game._on_right_click()
	game._on_right_click()

	assert_object(game.squad_manager.active_squad).is_null()
	assert_int(game.game_state).is_equal(game.GameState.IDLE)
