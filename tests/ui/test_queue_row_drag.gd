# The queue panel's drag WIRE (#412), on the real game scene.
#
# The seam itself (Squad.reorder_by_actor) is pinned in tests/squad/test_queue_reorder.gd. What that
# suite structurally cannot see is whether the panel's drag ever REACHES it: the row-draggable gate,
# the signal's shape, game's handler, and the fact that a finished drag rewrites the actual queue.
# That chain is four correct-in-isolation pieces, which is exactly the shape #103 shipped for
# thirteen months — and a drag that silently does nothing is invisible to every green suite.
#
# The gesture is driven at _on_row_drag_requested / _end_drag rather than through synthesized mouse
# events, because the live drag runs in _process against Input.is_mouse_button_pressed, which a
# headless run cannot hold down. Everything between those two calls (the re-parent) is what a real
# drag leaves behind, so it is reproduced literally.
#
# Fixture is tests/ui/test_target_pick_projection.gd's — see tests/README.md -> Testing the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

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
		for y in range(3):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: Squad.MEMBER_LDR_COST * 2},
			Team.Faction.PLAYER), cell)
	assert_object(unit).is_not_null()
	return unit


func _move(unit: Unit) -> MoveAction:
	var path: Array[Vector2i] = [unit.movement.cell, unit.movement.cell + Vector2i(1, 0)]
	var move := MoveAction.new()
	move.init(unit, path, null)
	return move


# Two squadmates with a queued move each, plus a hold for a third — the panel's MOVE section then
# holds two draggable rows and one that must never move.
func _panel_with_moves() -> Array[Unit]:
	var lead := _spawn(Vector2i(0, 0))
	var mate := _spawn(Vector2i(0, 1))
	var idler := _spawn(Vector2i(0, 2))
	game.squad_manager.join_squad(mate, lead.squad)
	game.squad_manager.join_squad(idler, lead.squad)
	var hold := MoveAction.new()
	hold.init_hold_position(idler, null)
	lead.squad._queue_action(hold)
	lead.squad._queue_action(_move(lead))
	lead.squad._queue_action(_move(mate))
	game.squad_manager.active_squad = lead.squad
	game.refresh_action_queue(lead.squad)
	await await_idle_frame()
	var trio: Array[Unit] = [lead, mate, idler]
	return trio


func _move_section() -> VBoxContainer:
	# The panel builds one section per header, in build_for's order; MOVE is first. WALKED by type
	# rather than read off sections_box's direct children (#685 wrapped each section in a styled
	# card, so the ScrollContainer sits a level deeper) -- the same shape
	# tests/ui/test_watch_note_reaches_the_panel.gd walks for rows, and for the same reason: what
	# this suite pins is the drag, not the panel's nesting.
	var panel = game.squad_action_queue_control
	var scroll := _first_scroll(panel.sections_box)
	if scroll == null or scroll.get_child_count() == 0:
		return null
	return scroll.get_child(0) as VBoxContainer


func _first_scroll(node: Node) -> ScrollContainer:
	for child in node.get_children():
		var scroll := child as ScrollContainer
		if scroll != null:
			return scroll
		var deeper := _first_scroll(child)
		if deeper != null:
			return deeper
	return null


func _rows_of(section: VBoxContainer) -> Array[ActionQueueRow]:
	var rows: Array[ActionQueueRow] = []
	for wrapper in section.get_children():
		if wrapper.get_child_count() > 0:
			var row := wrapper.get_child(0) as ActionQueueRow
			if row != null:
				rows.append(row)
	return rows


func test_a_move_row_is_draggable_and_a_hold_row_is_not() -> void:
	await _panel_with_moves()
	var section := _move_section()
	assert_object(section).is_not_null()

	var draggable := 0
	var fillers := 0
	for row in _rows_of(section):
		if (row.action as MoveAction).is_hold_position:
			fillers += 1
			assert_bool(row.draggable).override_failure_message(
					"a hold-position filler must not be draggable — nobody ordered it").is_false()
		else:
			draggable += 1
			assert_bool(row.draggable).override_failure_message(
					"a queued move's row must be draggable (#412)").is_true()
	assert_int(draggable).is_equal(2)
	assert_int(fillers).is_equal(1)


# The wire, end to end: a finished drag on the MOVE section has to rewrite the QUEUE, not just the
# rows. Everything in between — the signal's action-type argument, game's handler, the reorder seam —
# is exercised by asserting on squad.action_queue afterwards.
func test_finishing_a_drag_on_the_move_section_reorders_the_queue() -> void:
	var units := await _panel_with_moves()
	var squad: Squad = units[0].squad
	var section := _move_section()
	var panel = game.squad_action_queue_control

	var rows := _rows_of(section)
	var dragged: ActionQueueRow = null
	for row in rows:
		if not (row.action as MoveAction).is_hold_position:
			dragged = row
			break
	assert_object(dragged).is_not_null()
	assert_object(dragged.action.actor).is_same(units[0])   # the lead's row starts first

	# Press, drop it past its sibling, release — what a real drag leaves behind.
	panel._on_row_drag_requested(dragged)
	var wrapper: Control = dragged.get_parent()
	section.move_child(wrapper, section.get_child_count() - 1)
	panel._drag_dirty = true
	panel._end_drag()
	await await_idle_frame()

	var ordered: Array[Unit] = []
	for action in squad.action_queue:
		if action.action_type == BaseAction.ActionType.MOVE and action.is_reorderable():
			ordered.append(action.actor)
	assert_array(ordered).override_failure_message(
			"the drag never reached Squad.reorder_by_actor — the queue is unchanged").is_equal([units[1], units[0]])
