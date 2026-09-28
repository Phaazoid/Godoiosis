# A click on a queue row (#1122), on the real game scene.
#
# The dev's ruling: the click SPENDS the order through the X's own path, then opens the way back in
# -- move planning for a move, the unit's ring for anything else -- with the camera on the unit. A
# row that is not an order only moves the camera. The premise this exists to keep honest: the ring
# hides every main action while one is queued, so a ring opened BEFORE the order is spent offers
# nothing to requeue it with. The first case reads the ring's own tree for exactly that.
#
# Where the GUI path is the claim -- a row taking the press at all, the volley readout keeping the
# press from its row -- the click is REAL: window-space events through Input.parse_input_event, the
# precedent in test_cards_outrank_live_surfaces.gd. Where it is not, the gesture is driven at
# _on_row_pressed / _end_drag as test_queue_row_drag.gd does.
#
# Fixture is tests/ui/test_target_pick_projection.gd's -- see tests/README.md -> Testing the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

var _main: Node
var game: Node2D
var _window_size: Vector2i


# test_cards_outrank_live_surfaces.gd's fixture, because both click for real: the window must hold
# the design space (headless ones are tiny, and the dock sits on its right edge), and the title
# screen boots over everything a frame after Game and eats every click until it is closed.
func before_test() -> void:
	_window_size = get_tree().root.size
	get_tree().root.size = Vector2i(1280, 720)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	await await_idle_frame()
	game.mission_controller._close_mission_select()
	game.scenario_manager.clear_board()
	game.scenario_director.disarm()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		for y in range(4):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()
	get_tree().root.size = _window_size
	await await_idle_frame()   # #93/#114: let the freed subtree settle before the orphan sample


# --- fixture -------------------------------------------------------------------------------------

func _spawn(faction: Team.Faction, cell: Vector2i, stats: Dictionary = {}) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data(stats, faction), cell)
	assert_object(unit).is_not_null()
	return unit


# A player unit with an attack queued at an enemy beside it, through the real door.
func _queue_attack() -> Unit:
	var attacker := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var victim := _spawn(Team.Faction.ENEMY, Vector2i(2, 1))
	var weapon := H.make_weapon(4)
	weapon.template.main_attack.display_name = "Strike"
	attacker.equipped_weapon = weapon
	game.squad_manager.active_squad = attacker.squad
	assert_bool(game.squad_manager.queue_action(attacker.squad, H.stamped_attack(attacker, victim))) \
		.override_failure_message("fixture: the attack was refused, so there is nothing to click").is_true()
	game.refresh_action_queue(attacker.squad)
	await await_idle_frame()
	assert_bool(attacker.has_main_action_queued()).is_true()
	return attacker


func _rows() -> Array[ActionQueueRow]:
	var out: Array[ActionQueueRow] = []
	for node: Node in game.squad_action_queue_control.find_children("*", "", true, false):
		if node is ActionQueueRow and not node.is_queued_for_deletion():
			out.append(node as ActionQueueRow)
	return out


func _row_of(type: BaseAction.ActionType, actor: Unit) -> ActionQueueRow:
	for row in _rows():
		if row.action != null and row.action.action_type == type and row.action.actor == actor:
			return row
	return null


func _open_rings() -> Array[ActionMenuController]:
	var out: Array[ActionMenuController] = []
	for child in game.get_children():
		if child is ActionMenuController and not child.is_queued_for_deletion():
			out.append(child as ActionMenuController)
	return out


func _focused_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	game.view_focus_requested.connect(func(cell: Vector2i) -> void: cells.append(cell))
	return cells


# The gesture without the GUI: press, release where it was pressed.
func _click_through_panel(row: ActionQueueRow) -> void:
	var panel = game.squad_action_queue_control
	panel._on_row_pressed(row)
	panel._end_drag()
	await await_idle_frame()


# --- a real click ----------------------------------------------------------------------------------

# A window-space click through GameContainer, so Godot's own picking decides which control takes
# the press -- which is what the readout case is about. The release is judged by the panel's
# _process off Input.
func _screen_point(control: Control) -> Vector2:
	var view := control.get_viewport()
	var in_view: Vector2 = (view.get_final_transform() * control.get_global_transform_with_canvas()) \
			* (control.size * 0.5)
	var container := _main.get_node("GameContainer") as Control
	return container.get_global_rect().position + in_view


func _real_click(control: Control) -> void:
	var at := _screen_point(control)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await await_idle_frame()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await await_idle_frame()
	await await_idle_frame()


# --- cases -----------------------------------------------------------------------------------------

# The whole wire, with a real click on the row's sprite: the order is spent, the view goes to the
# unit, and its ring opens OFFERING THE ATTACK AGAIN. That last clause is the ordering: a ring opened
# before the spend snapshots an Inspect-only tree.
func test_clicking_an_attack_row_spends_it_and_opens_a_ring_that_offers_the_attack_again() -> void:
	var attacker := await _queue_attack()
	var row := _row_of(BaseAction.ActionType.ATTACK, attacker)
	assert_object(row).is_not_null()
	var focused := _focused_cells()

	await _real_click(row.actor_texture)

	assert_bool(attacker.has_main_action_queued()) \
		.override_failure_message("the click did not spend the order").is_false()
	var rings := _open_rings()
	assert_int(rings.size()).override_failure_message("no ring opened on the click").is_equal(1)
	assert_object(rings[0].local_unit).is_same(attacker)
	assert_object(game.selected_unit).is_same(attacker)
	var names: Array[String] = []
	for node: Dictionary in rings[0]._levels[0]["nodes"]:
		names.append(String(node.get("name", "")))
	var kit: String = game.main_action_menu.category_display(MainActionMenu.Group.ATTACK_GROUP, attacker)["name"]
	assert_array(names).override_failure_message(
			"the ring offers %s -- it was built before the order was spent, so it cannot requeue it" % [names]) \
		.contains([kit])
	assert_array(focused).contains([attacker.get_projected_destination()])


# A move row goes straight into planning (dev ruling), and takes the unit's main with it as the X
# does -- move-before-main would refuse the new move while the attack stood.
func test_clicking_a_move_row_spends_it_and_its_main_and_opens_move_planning() -> void:
	var mover := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var victim := _spawn(Team.Faction.ENEMY, Vector2i(3, 1))
	mover.equipped_weapon = H.make_weapon(4)
	var path: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1)]
	var move := MoveAction.new()
	move.init(mover, path, null)
	var attack := AttackAction.create(mover, Vector2i(2, 1), victim, victim.movement.cell)
	attack.fired_attack = mover.get_fired_attack()
	# Straight into the queue: this case is about the click, not about queueing's gates.
	mover.squad._queue_action(move)
	mover.squad._queue_action(attack)
	game.squad_manager.active_squad = mover.squad
	game.refresh_action_queue(mover.squad)
	await await_idle_frame()
	var row := _row_of(BaseAction.ActionType.MOVE, mover)
	assert_object(row).is_not_null()

	await _click_through_panel(row)

	assert_bool(mover.has_action_type_queued(BaseAction.ActionType.MOVE)).is_false()
	assert_bool(mover.has_main_action_queued()) \
		.override_failure_message("the main survived its move, and the re-planned move will be refused").is_false()
	assert_int(game.game_state).is_equal(game.GameState.CHOOSING_MOVE)
	assert_object(game.selected_unit).is_same(mover)
	assert_int(_open_rings().size()).is_equal(0)


# A row that is not an order has nothing to spend: the click only looks. A real click, because a
# hold row is NOT draggable and such rows ignored the press entirely before #1122.
func test_clicking_a_row_that_is_not_an_order_only_moves_the_camera() -> void:
	var lead := _spawn(Team.Faction.PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: Squad.MEMBER_LDR_COST * 2})
	var idler := _spawn(Team.Faction.PLAYER, Vector2i(0, 1))
	game.squad_manager.join_squad(idler, lead.squad)
	assert_object(idler.squad).is_same(lead.squad)
	var hold := MoveAction.new()
	hold.init_hold_position(idler, null)
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var move := MoveAction.new()
	move.init(lead, path, null)
	lead.squad._queue_action(hold)
	lead.squad._queue_action(move)
	game.squad_manager.active_squad = lead.squad
	game.refresh_action_queue(lead.squad)
	await await_idle_frame()
	var row := _row_of(BaseAction.ActionType.MOVE, idler)
	assert_object(row).is_not_null()
	assert_bool(row.draggable).is_false()
	var queued := lead.squad.action_queue.size()
	var focused := _focused_cells()

	await _real_click(row.actor_texture)

	assert_int(lead.squad.action_queue.size()).is_equal(queued)
	assert_int(_open_rings().size()).is_equal(0)
	assert_array(focused).override_failure_message("a click on a non-order row did not reach the camera") \
		.contains([idler.get_projected_destination()])


# A press that wanders and reorders nothing is an abandoned drag, not a click -- and a click now
# spends the order, so "reordered nothing" alone would delete it.
func test_a_press_that_travels_past_the_slop_is_not_a_click() -> void:
	var attacker := await _queue_attack()
	var row := _row_of(BaseAction.ActionType.ATTACK, attacker)
	var panel = game.squad_action_queue_control

	panel._on_row_pressed(row)
	panel._press_at = panel.get_global_mouse_position() + Vector2(GearDropZone.CLICK_SLOP + 5.0, 0.0)
	panel._end_drag()
	await await_idle_frame()

	assert_bool(attacker.has_main_action_queued()) \
		.override_failure_message("an abandoned drag spent the order").is_true()
	assert_int(_open_rings().size()).is_equal(0)


# A volley header: its readout expands, its row requeues (dev ruling). Real clicks, because the
# claim is that the readout keeps the press from reaching the row.
func test_a_volley_readout_expands_and_the_header_row_requeues() -> void:
	var attacker := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var first := _spawn(Team.Faction.ENEMY, Vector2i(2, 1))
	var second := _spawn(Team.Faction.ENEMY, Vector2i(1, 2))
	attacker.equipped_weapon = H.make_weapon(4)
	var a := H.stamped_attack(attacker, first)
	var b := H.stamped_attack(attacker, second)
	var volley: Array[AttackAction] = [a, b]
	a.volley = volley
	b.volley = volley
	var panel = game.squad_action_queue_control
	var clicked: Array[BaseAction] = []
	panel.row_clicked.connect(func(action: BaseAction) -> void: clicked.append(action))
	var entries: Array[ActionQueueDisplayEntry] = [ActionQueueDisplayEntry.header("ATTACK"),
			ActionQueueDisplayEntry.action_row(a), ActionQueueDisplayEntry.action_row(b)]
	panel.show_display_entries(entries)
	await await_idle_frame()
	var header := _header()
	assert_object(header).is_not_null()

	await _real_click(header.readout_card)

	assert_array(clicked).override_failure_message("a press on the readout reached the row and requeued") \
		.is_empty()
	assert_bool(panel._expanded_actors.get(attacker.get_instance_id(), false)) \
		.override_failure_message("the readout did not expand the volley").is_true()

	header = _header()
	await _real_click(header.actor_texture)

	assert_array(clicked).is_equal([a])
	volley.clear()   # the members hold each other


func _header() -> ActionQueueRow:
	for row in _rows():
		if row.is_volley_header:
			return row
	return null


# The board is not the player's while playback owns it, and neither is the queue.
func test_a_click_while_the_board_is_locked_does_nothing() -> void:
	var attacker := await _queue_attack()
	var row := _row_of(BaseAction.ActionType.ATTACK, attacker)
	game.camera_controller.set_playback_locked(true)

	await _click_through_panel(row)

	game.camera_controller.set_playback_locked(false)
	assert_bool(attacker.has_main_action_queued()).is_true()
	assert_int(_open_rings().size()).is_equal(0)
