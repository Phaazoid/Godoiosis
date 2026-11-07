# The matchup card (#1629): a right-click on a queued attack opens the exchange it makes, and a tile
# reaction's word (#1528) reaches the screen on it.
#
# Every gesture is a REAL right-click, window-space events through Input.parse_input_event (the
# precedent in test_queue_row_click.gd), because the claims are about who takes the click: the row,
# the card, or the board's cancel behind them. What a card shows is read off the plan the queue
# holds, never pinned, and its pieces are found by node name, never by their wording.
#
# Fixture is test_queue_row_click.gd's -- see tests/README.md -> Testing the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const DEEP_WATER := Vector2i(5, 6)

var _main: Node
var game: Node2D
var _window_size: Vector2i


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
	await await_idle_frame()


# --- fixture -------------------------------------------------------------------------------------

func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: 40}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


func _queue(attacker: Unit, action: AttackAction) -> void:
	game.squad_manager.active_squad = attacker.squad
	assert_bool(game.squad_manager.queue_action(attacker.squad, action)) \
		.override_failure_message("fixture: the attack was refused: %s" % [action.validation_errors]).is_true()
	game.refresh_action_queue(attacker.squad)
	await await_idle_frame()


# A player unit with an attack queued at an enemy beside it.
func _queue_attack() -> Unit:
	var attacker := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var victim := _spawn(Team.Faction.ENEMY, Vector2i(2, 1))
	attacker.equipped_weapon = H.make_weapon(4)
	await _queue(attacker, H.stamped_attack(attacker, victim))
	return attacker


func _panel() -> SquadActionQueueControl:
	return game.squad_action_queue_control


func _card() -> MatchupCard:
	var card := _panel()._matchup
	return card if card != null and is_instance_valid(card) and card.is_inside_tree() else null


func _rows() -> Array[ActionQueueRow]:
	var out: Array[ActionQueueRow] = []
	for node: Node in _panel().find_children("*", "", true, false):
		if node is ActionQueueRow and not node.is_queued_for_deletion():
			out.append(node as ActionQueueRow)
	return out


func _attack_row(actor: Unit) -> ActionQueueRow:
	for row in _rows():
		if row.action is AttackAction and not row.action is CounterAttackAction and row.action.actor == actor:
			return row
	return null


# --- a real right-click ----------------------------------------------------------------------------

func _screen_point(control: Control) -> Vector2:
	var view := control.get_viewport()
	var in_view: Vector2 = (view.get_final_transform() * control.get_global_transform_with_canvas()) \
			* (control.size * 0.5)
	var container := _main.get_node("GameContainer") as Control
	return container.get_global_rect().position + in_view


func _right_click_at(at: Vector2) -> void:
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
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_RIGHT if pressed else 0
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await await_idle_frame()
	await await_idle_frame()


func _right_click(control: Control) -> void:
	await _right_click_at(_screen_point(control))


# A point on the board itself: a board cell's centre, run through the same chain as a control's, and
# taken only where the game view's own picking finds no control under the pointer.
func _board_point() -> Vector2:
	var grid: TileMapLayer = game.grid
	var view := grid.get_viewport()
	var container := _main.get_node("GameContainer") as Control
	for x in range(8):
		for y in range(4):
			var at := container.get_global_rect().position \
					+ (view.get_final_transform() * grid.get_global_transform_with_canvas()) \
					* grid.map_to_local(Vector2i(x, y))
			var motion := InputEventMouseMotion.new()
			motion.position = at
			motion.global_position = at
			Input.parse_input_event(motion)
			Input.flush_buffered_events()
			await await_idle_frame()
			if view.gui_get_hovered_control() == null:
				return at
	assert_bool(false).override_failure_message("fixture: every board cell sits under a HUD surface").is_true()
	return Vector2.ZERO


func _named(root: Node, prefix: String) -> Array[Node]:
	var out: Array[Node] = []
	for node in root.find_children(prefix + "*", "", true, false):
		out.append(node)
	return out


# --- cases -----------------------------------------------------------------------------------------

# #1528: a fire aim at frozen water melts it, and the word the tile reaction says reaches the card.
# The expected words are the plan's own (deposits_of), so a reaction reworded moves nothing here.
func test_a_tile_reactions_word_reaches_the_card() -> void:
	var ice := Vector2i(2, 1)
	(game.grid as BoardGrid).paint(ice, GRASS_SOURCE, DEEP_WATER)
	var freeze := ResolvedCellEffect.new()
	freeze.cell = ice
	freeze.states_added.assign([Terrain.TileState.FROZEN])
	game.terrain_states.apply(freeze)
	var attacker := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	attacker.equipped_weapon = H.make_weapon(4)
	var attack := (attacker.equipped_weapon as WeaponInstance).template.main_attack
	attack.elemental_damage_type = Elemental.Element.FIRE
	attack.targets = EquippableData.TargetMode.MAP
	await _queue(attacker, AttackAction.declare(attacker, attacker.movement.cell, ice))
	var row := _attack_row(attacker)
	assert_object(row).override_failure_message("fixture: the aim drew no attack row").is_not_null()

	await _right_click(row.actor_texture)

	var card := _card()
	assert_object(card).override_failure_message("the right-click opened no card").is_not_null()
	var expected: Array[String] = []
	for effect in card.plan.deposits_of(card.lead):
		for word in effect.popups:
			if not expected.has(word):
				expected.append(word)
	assert_array(expected).override_failure_message(
			"fixture: fire on frozen water fired no tile reaction with a word, so this proves nothing").is_not_empty()
	var shown: Array[String] = []
	for pill in _named(card, "GroundPill"):
		shown.append((pill.find_child("Word", true, false) as Label).text)
	for word in expected:
		var found := false
		for text in shown:
			found = found or text.begins_with(word)
		assert_bool(found).override_failure_message(
				"the tile word '%s' never reached the card (pills: %s)" % [word, shown]).is_true()


# The row takes both edges of the right-click, so the board's cancel behind it never sees it.
func test_a_right_click_on_an_attack_row_opens_the_card_and_keeps_every_order() -> void:
	var attacker := await _queue_attack()
	var orders: Array = attacker.squad.action_queue.duplicate()

	await _right_click(_attack_row(attacker).actor_texture)

	assert_object(_card()).override_failure_message("the right-click opened no card").is_not_null()
	assert_array(attacker.squad.action_queue).override_failure_message(
			"the right-click reached the board's cancel and popped an order").is_equal(orders)
	assert_int(game.game_state).is_equal(game.GameState.IDLE)


func test_a_right_click_on_the_board_closes_the_card_and_keeps_the_plan() -> void:
	var attacker := await _queue_attack()
	await _right_click(_attack_row(attacker).actor_texture)
	assert_object(_card()).override_failure_message("fixture: no card opened").is_not_null()
	var orders: Array = attacker.squad.action_queue.duplicate()

	await _right_click_at(await _board_point())

	assert_object(_card()).override_failure_message("a board right-click left the card open").is_null()
	assert_array(attacker.squad.action_queue).override_failure_message(
			"closing the card also popped an order").is_equal(orders)


# A volley's header opens the whole volley: one member row per row the header folds.
func test_a_volley_header_opens_a_row_per_member() -> void:
	var attacker := _spawn(Team.Faction.PLAYER, Vector2i(3, 3))
	for x in [2, 3, 4]:
		_spawn(Team.Faction.ENEMY, Vector2i(x, 1))
	attacker.equipped_weapon = H.make_weapon(4)
	var spread: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0)]
	P.stamped((attacker.equipped_weapon as WeaponInstance).template.main_attack, 3, spread)
	await _queue(attacker, AttackAction.declare(attacker, attacker.movement.cell, Vector2i(3, 1)))
	var header: ActionQueueRow = null
	for row in _rows():
		if row.is_volley_header:
			header = row
	assert_object(header).override_failure_message("fixture: the spread drew no volley header").is_not_null()
	var lead := header.action as AttackAction
	var folded := 0
	for entry in _panel()._last_entries:
		if entry != null and entry.action is AttackAction and not entry.action is CounterAttackAction \
				and AttackAction.same_volley(lead, entry.action as AttackAction):
			folded += 1

	await _right_click(header.actor_texture)

	var card := _card()
	assert_object(card).override_failure_message("the header's right-click opened no card").is_not_null()
	assert_bool(card.whole_volley).is_true()
	assert_int(_named(card, "Member").size()).override_failure_message(
			"the card's member rows do not match the %d rows the header folds" % folded).is_equal(folded)


func test_a_plan_change_closes_the_card_and_a_restyle_keeps_it() -> void:
	var attacker := await _queue_attack()
	await _right_click(_attack_row(attacker).actor_texture)
	var lead := _card().lead

	_panel().restyle()
	await await_idle_frame()

	assert_object(_card()).override_failure_message("a restyle closed the card").is_not_null()
	assert_object(_card().lead).is_same(lead)

	game.refresh_action_queue(attacker.squad)
	await await_idle_frame()

	assert_object(_card()).override_failure_message("the card outlived the plan it was read from").is_null()


# The attacker faces right and its target left, judged by the world's own reading of a flip.
func test_the_two_figures_face_each_other() -> void:
	var attacker := await _queue_attack()
	await _right_click(_attack_row(attacker).actor_texture)
	var card := _card()

	var left := card.find_child("Attacker", true, false).find_child("Portrait", true, false) as TextureRect
	var right := card.find_child("Target", true, false).find_child("Portrait", true, false) as TextureRect

	assert_bool(StatusWorld.faces_right(left.flip_h)).override_failure_message("the attacker faces away").is_true()
	assert_bool(StatusWorld.faces_right(right.flip_h)).override_failure_message("the target faces away").is_false()


# The card catches its own right-click: it closes, and the board's cancel never sees the press.
func test_a_right_click_on_the_card_closes_it_without_popping_an_order() -> void:
	var attacker := await _queue_attack()
	await _right_click(_attack_row(attacker).actor_texture)
	var card := _card()
	assert_object(card).override_failure_message("fixture: no card opened").is_not_null()
	var orders: Array = attacker.squad.action_queue.duplicate()

	await _right_click(card)

	assert_object(_card()).override_failure_message("a right-click on the card left it open").is_null()
	assert_array(attacker.squad.action_queue).override_failure_message(
			"the card's right-click fell through and popped an order").is_equal(orders)
