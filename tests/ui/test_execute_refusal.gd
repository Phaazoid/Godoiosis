# #1121: pressing Execute over refused (red) orders shakes the red rows, flashes their units, scrolls
# to the first of them and says why in a box above the button -- instead of doing nothing at all.
#
# Before #1121 the button was truly `disabled` while any order was red, so the press never arrived
# and OrderExecutor's human refusal branch was unreachable. So EVERY PRESS HERE IS A REAL CLICK,
# through Input.parse_input_event and the SubViewport chain (test_cards_outrank_live_surfaces'
# helpers): emitting `pressed` directly bypasses `disabled` and would pass against the very bug.
#
# Two orderings the reachable press exposed, each with a case: the button must SURVIVE a refused
# press (_execute hides it after the emit), and the shake must land on the rows the refusal's own
# refresh just rebuilt, never on the freed ones before it.
#
# The refused plan is built the only way queueing allows (test_ai_turn_terminates' shape): a member
# steps away while that is legal, then the leader retreats and the member's order goes red.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true, move_cost=1 in TestTiles.tres
const RETREAT := Vector2i(1, 0)       # where the leader falls back to

var _main: Node
var game: Node2D
var panel: SquadActionQueueControl


func before_test() -> void:
	# Headless windows can be tiny, and a click has to land inside this one.
	get_tree().root.size = Vector2i(1280, 720)
	PlayerSettings.reset_for_test()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	await await_idle_frame()   # game._ready defers the title screen by a frame
	game.mission_controller._close_mission_select()
	game.scenario_manager.clear_board()
	game.scenario_director.disarm()
	game.game_state = game.GameState.IDLE
	game.ai_controller.set_faction_ai_enabled(Team.Faction.PLAYER, false)
	for x in range(12):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	panel = game.squad_action_queue_control
	# A headless window is never told the mouse entered it (test_objective_rows' line).
	get_tree().root.notification(Node.NOTIFICATION_VP_MOUSE_ENTER)
	await await_idle_frame()


func after_test() -> void:
	PlayerSettings.reset_for_test()
	await DialogFixtures.end_all_dialog(self)
	get_tree().root.remove_child(_main)
	_main.free()
	await await_idle_frame()


# --- fixtures --------------------------------------------------------------------------------------

func _spawn(cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), cell)
	assert_object(unit).override_failure_message("fixture: spawn refused %s" % cell).is_not_null()
	unit.equipped_weapon = H.make_weapon()
	return unit


func _queue_move(unit: Unit, destination: Vector2i) -> void:
	var reach := RulesService.compute_move_range(unit, game._board())
	var move := MoveAction.new()
	move.init(unit, RulesService.reconstruct_path(reach.came_from, unit.movement.cell, destination),
		GridUtils.get_terrain_icon_at_cell(game.grid, destination))
	assert_bool(game.squad_manager.queue_action(unit.squad, move)) \
		.override_failure_message("fixture: the move to %s was refused" % destination).is_true()


func _move_of(unit: Unit) -> BaseAction:
	for action in unit.squad.action_queue:
		if action.actor == unit and action.action_type == BaseAction.ActionType.MOVE:
			return action
	return null


# A leader at (5,0) with members at the given cells, each stepping one cell right while that is
# still legal. The leash is set so every step lands ONE past it once the leader retreats to RETREAT,
# while the member's own cell stays inside it -- which is what lets a case fix one member by
# cancelling its step. `helpers` step left instead, toward the retreat, and stay legal throughout.
func _squad(stranded: Array[Vector2i], helpers: Array[Vector2i] = []) -> Dictionary:
	var leader := _spawn(Vector2i(5, 0))
	leader.unit_instance.stats[Stats.Stat.LDR] = 8
	var members: Array[Unit] = []
	for cell in stranded:
		members.append(_spawn(cell))
	for cell in helpers:
		members.append(_spawn(cell))
	await await_idle_frame()
	for member in members:
		game.squad_manager.join_squad(member, leader.squad)
	var nearest_step := Vector2i(99, 0)
	for cell in stranded:
		if cell.x + 1 < nearest_step.x:
			nearest_step = cell + Vector2i.RIGHT
	leader.unit_instance.stats[Stats.Stat.COH] = GridUtils.manhattan_distance(RETREAT, nearest_step) - 1
	# Right-most first, so each step lands on a cell the member ahead has already left.
	var order := stranded.duplicate()
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x > b.x)
	for cell in order:
		_queue_move(_unit_at(members, cell), cell + Vector2i.RIGHT)
	# ...and helpers left-most first, for the same reason the other way.
	var lefts := helpers.duplicate()
	lefts.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	for cell in lefts:
		_queue_move(_unit_at(members, cell), cell + Vector2i.LEFT)
	return {"leader": leader, "members": members, "squad": leader.squad}


func _unit_at(units: Array[Unit], cell: Vector2i) -> Unit:
	for unit in units:
		if unit.movement.cell == cell:
			return unit
	return null


func _retreat(board: Dictionary) -> void:
	_queue_move(board.leader, RETREAT)
	assert_bool(game.squad_manager.squad_has_invalid_actions(board.squad)) \
		.override_failure_message("fixture: the retreat left every order legal").is_true()


# --- driving it for real -----------------------------------------------------------------------------

func _pump() -> void:
	Input.flush_buffered_events()
	await await_idle_frame()
	Input.flush_buffered_events()
	await await_idle_frame()
	await await_idle_frame()


# Where a Control inside GameView sits in the WINDOW: through the viewport's own stretch and out
# through GameContainer, the chain Viewport.push_input inverts on the way in.
func _screen_point(control: Control) -> Vector2:
	var view := control.get_viewport()
	var in_view: Vector2 = (view.get_final_transform() * control.get_global_transform_with_canvas()) \
			* (control.size * 0.5)
	var container := _main.get_node("GameContainer") as Control
	return container.get_global_rect().position + in_view


func _click(control: Control) -> void:
	var at := _screen_point(control)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(event)
	await _pump()


func _press_execute() -> void:
	await _click(panel.execute_button)


func _box_lines() -> PackedStringArray:
	return panel._refusal_text.get_parsed_text().strip_edges().split("\n", false)


# ==================================================================================================
#  The button
# ==================================================================================================

func test_a_refused_plan_keeps_execute_pressable_and_dull() -> void:
	var board: Dictionary = await _squad([Vector2i(6, 0)])
	var button := panel.execute_button
	assert_bool(game.squad_manager.squad_has_invalid_actions(board.squad)) \
		.override_failure_message("fixture: the step alone is already refused").is_false()
	assert_bool(button.disabled).is_false()
	assert_that(button.modulate).override_failure_message("a legal plan wears the dull look") \
		.is_not_equal(SquadActionQueueControl.EXECUTE_DULL)

	_retreat(board)

	assert_bool(button.disabled) \
		.override_failure_message("a refused plan disabled Execute, so the press can never arrive").is_false()
	assert_that(button.modulate).override_failure_message("a refused plan lost the dull look") \
		.is_equal(SquadActionQueueControl.EXECUTE_DULL)


# The split's other half: whether Execute is on offer is asked FIRST. A plan that is refused AND not
# on offer is truly disabled -- a press there must never arrive at all.
func test_a_refused_plan_not_on_offer_stays_truly_disabled() -> void:
	var board: Dictionary = await _squad([Vector2i(6, 0)])
	_retreat(board)
	game.game_state = game.GameState.AI_TURN
	game.refresh_action_queue(board.squad)
	assert_bool(panel.execute_button.disabled) \
		.override_failure_message("a locked board's Execute took the press because its plan was refused") \
		.is_true()


# ==================================================================================================
#  The press
# ==================================================================================================

func test_a_refused_press_says_why_and_runs_nothing() -> void:
	var board: Dictionary = await _squad([Vector2i(6, 0)])
	_retreat(board)
	var squad: Squad = board.squad
	var member: Unit = board.members[0]
	var leader: Unit = board.leader
	var queued := squad.action_queue.size()
	var flash_before: Tween = member.visuals.visual_tween

	await _press_execute()

	assert_object(game.order_executor.executing_plan).override_failure_message("a pass started").is_null()
	assert_int(squad.action_queue.size()).override_failure_message("the refusal dropped orders") \
		.is_equal(queued)
	assert_that(member.movement.cell).is_equal(Vector2i(6, 0))
	assert_that(leader.movement.cell).is_equal(Vector2i(5, 0))
	assert_bool(panel.execute_button.visible) \
		.override_failure_message("the refused press hid Execute, leaving no way to press it again").is_true()

	assert_bool(panel._refusal_box.visible).override_failure_message("the refusal said nothing").is_true()
	var refused: Array[BaseAction] = game.squad_manager.refused_orders(squad)
	assert_int(refused.size()).override_failure_message("fixture: nothing is refused").is_greater(0)
	var lines := _box_lines()
	assert_int(lines.size()).override_failure_message("want one line per refused order, got %s" % str(lines)) \
		.is_equal(refused.size())
	for i in mini(lines.size(), refused.size()):
		var order := refused[i]
		assert_str(lines[i]).contains(order.actor.get_unit_name())
		assert_int(order.validation_errors.size()).is_greater(0)
		for reason in order.validation_errors:
			assert_str(lines[i]).contains(reason)

	assert_object(member.visuals.visual_tween) \
		.override_failure_message("the refused unit was not flashed on the board").is_not_null()
	assert_bool(member.visuals.visual_tween != flash_before).is_true()


# The rows that shake are the red rows the refusal's own refresh LEFT STANDING -- a shake started
# before that refresh plays on rows it frees.
func test_the_rows_that_shake_are_the_red_rows_the_press_left_standing() -> void:
	var board: Dictionary = await _squad([Vector2i(6, 0)], [Vector2i(4, 0)])
	_retreat(board)

	await _press_execute()

	var red_rows: Array[ActionQueueRow] = panel._refused_rows()
	assert_int(red_rows.size()).override_failure_message("fixture: no red row on screen").is_greater(0)
	var wrappers: Array[Control] = []
	for row in red_rows:
		wrappers.append(row.get_parent() as Control)
	assert_int(panel._shaking.size()) \
		.override_failure_message("%d rows shook for %d red rows" % [panel._shaking.size(), red_rows.size()]) \
		.is_equal(wrappers.size())
	for wrapper in wrappers:
		assert_bool(panel._shaking.has(wrapper)) \
			.override_failure_message("a red row on screen did not shake").is_true()


func test_the_box_follows_the_plan_until_nothing_is_red() -> void:
	var board: Dictionary = await _squad([Vector2i(6, 0), Vector2i(7, 0)])
	_retreat(board)
	var members: Array[Unit] = board.members
	var inner := _unit_at(members, Vector2i(6, 0))
	var outer := _unit_at(members, Vector2i(7, 0))
	assert_int(game.squad_manager.refused_orders(board.squad).size()) \
		.override_failure_message("fixture: want both steps refused").is_equal(2)
	assert_bool(panel._refusal_box.visible).override_failure_message("the box showed before any press") \
		.is_false()

	await _press_execute()
	assert_int(_box_lines().size()).is_equal(2)

	# Fix ONE: the inner member stays put, inside the leash. The box stays, one line shorter.
	game._on_queue_cancel_requested(_move_of(inner))
	await await_idle_frame()
	assert_bool(panel._refusal_box.visible) \
		.override_failure_message("fixing one refusal took the box away while another is still red").is_true()
	assert_int(_box_lines().size()).is_equal(1)
	assert_str(_box_lines()[0]).contains(outer.get_unit_name())

	# Fix the rest: the leader stays put too, and nothing is red.
	game._on_queue_cancel_requested(_move_of(board.leader))
	await await_idle_frame()
	assert_bool(game.squad_manager.squad_has_invalid_actions(board.squad)) \
		.override_failure_message("fixture: cancelling the retreat left something red").is_false()
	assert_bool(panel._refusal_box.visible).override_failure_message("the box outlived the refusals") \
		.is_false()

	# Break it again: the box waits for the next press rather than coming back on its own.
	_retreat(board)
	await await_idle_frame()
	assert_bool(panel._refusal_box.visible) \
		.override_failure_message("the box came back without a press").is_false()
	await _press_execute()
	assert_bool(panel._refusal_box.visible).is_true()


# The box and a shaking row both take height, so the red row can start below the fold -- the press
# scrolls it into view. The dock is shortened so the list overflows at all.
func test_a_refused_press_scrolls_the_first_red_row_into_view() -> void:
	var board: Dictionary = await _squad([Vector2i(6, 0)], [Vector2i(4, 0), Vector2i(3, 0)])
	_retreat(board)
	var dock := panel.background_panel
	dock.offset_bottom = dock.offset_top + 200.0
	for i in 3:
		await await_idle_frame()
	var red_row: ActionQueueRow = panel._refused_rows()[0]
	var scroll := panel.outer_scroll
	# Park the list at whichever end hides the red row.
	scroll.scroll_vertical = 0
	await await_idle_frame()
	if scroll.get_global_rect().encloses(red_row.get_global_rect()):
		scroll.scroll_vertical = 100000
		await await_idle_frame()
	assert_bool(scroll.get_global_rect().encloses(red_row.get_global_rect())) \
		.override_failure_message("fixture: the red row is in view at both ends -- the list does not overflow") \
		.is_false()

	await _press_execute()
	for i in 3:
		await await_idle_frame()

	red_row = panel._refused_rows()[0]
	assert_bool(scroll.get_global_rect().encloses(red_row.get_global_rect())) \
		.override_failure_message("the red row is still out of view: row %s, list %s"
			% [red_row.get_global_rect(), scroll.get_global_rect()]) \
		.is_true()


# #217: the shake is motion, so the photosensitivity setting stills it. The box and the red rows
# still carry the refusal.
func test_photosensitivity_stills_the_shake_and_keeps_the_box() -> void:
	PlayerSettings.set_on(PlayerSettings.Setting.PHOTOSENSITIVITY, true)
	var board: Dictionary = await _squad([Vector2i(6, 0)])
	_retreat(board)

	await _press_execute()

	assert_int(panel._shaking.size()).override_failure_message("a row shook with photosensitivity on") \
		.is_equal(0)
	assert_bool(panel._refusal_box.visible).is_true()
