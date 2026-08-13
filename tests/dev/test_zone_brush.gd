# The Tile Brush ZONE mode (2026-08-12 rework): zones overlap, the picker dropdown lists every
# painted zone so authoring can continue one instead of accidentally forking a new one, a zone's
# kind locks at creation, erase is scoped to the picked zone, and BOTH buttons are hold-to-drag.
#
# Cases drive the tool beneath the mouse dispatch (the palette suite's pattern) -- picker handlers
# called the way the controls fire them, and the hold-to-erase cases feed real InputEvents through
# DevController.handle_tile_brush, because the press/motion ROUTING is exactly what regressed
# (erase used to fire on click only). The board cell is the fixed headless hover cell, since
# _mouse_cell() cannot be steered without a real window.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const PATROL := ZoneManager.Kind.PATROL
const CAPTURE := ZoneManager.Kind.CAPTURE

var _main: Node
var game: Node2D
var _brush: TileBrushTool


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	_brush = game.dev_overlay.tile_brush
	_brush._set_paint_mode(TileBrushTool.PaintMode.ZONE)


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func _labels() -> Array[String]:
	var out: Array[String] = []
	for i in _brush.zone_dropdown.item_count:
		out.append(_brush.zone_dropdown.get_item_text(i))
	return out


# Typing into the name field, driven the way the LineEdit fires it.
func _type_name(text: String) -> void:
	_brush._zone_name_edit.text = text
	_brush._on_zone_name_changed(text)


func _press(button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


func _motion() -> InputEventMouseMotion:
	return InputEventMouseMotion.new()


func _hover_cell() -> Vector2i:
	return game.dev_controller._mouse_cell()


# ---- the picker ----

func test_painted_zones_are_listed_with_their_kind() -> void:
	game.zone_manager.paint_cell("gate", PATROL, Vector2i(1, 1))
	game.zone_manager.paint_cell("throne", CAPTURE, Vector2i(4, 4))

	assert_array(_labels()).is_equal(
		["(new zone)", "gate (Patrol)", "throne (Capture)"] as Array[String])


func test_picking_an_existing_zone_syncs_name_and_locks_kind() -> void:
	game.zone_manager.paint_cell("throne", CAPTURE, Vector2i(4, 4))
	_brush._on_zone_dropdown_item_selected(1)

	assert_str(_brush.selected_zone_name()).is_equal("throne")
	assert_str(_brush._zone_name_edit.text).is_equal("throne")
	assert_bool(_brush._zone_kind_option.disabled).is_true()
	assert_int(_brush._zone_kind_option.selected).is_equal(CAPTURE)


func test_new_zone_clears_the_name_and_frees_the_kind() -> void:
	game.zone_manager.paint_cell("throne", CAPTURE, Vector2i(4, 4))
	_brush._zone_kind_option.item_selected.emit(PATROL)   # the user's own pick, made while free
	_brush._on_zone_dropdown_item_selected(1)
	_brush._on_zone_dropdown_item_selected(0)

	assert_str(_brush.selected_zone_name()).is_equal("")
	assert_str(_brush._zone_name_edit.text).is_equal("")
	assert_bool(_brush._zone_kind_option.disabled).is_false()
	assert_int(_brush._zone_kind_option.selected).is_equal(PATROL)


func test_typing_an_existing_name_is_picking_that_zone() -> void:
	# Painting under an existing name always continues that zone, so the picker must say so
	# before the first click does it.
	game.zone_manager.paint_cell("gate", PATROL, Vector2i(1, 1))
	_type_name("gate")

	assert_int(_brush.zone_dropdown.selected).is_equal(1)
	assert_bool(_brush._zone_kind_option.disabled).is_true()


func test_painting_a_new_zone_promotes_the_pick_to_it() -> void:
	# The first painted cell creates the zone; the picker must immediately list it and bind the
	# current pick to it (kind now locked), so continuing to paint continues THAT zone.
	_type_name("fresh")
	game.dev_controller._paint_zone(Vector2i(2, 2))

	assert_array(_labels()).is_equal(["(new zone)", "fresh (Patrol)"] as Array[String])
	assert_int(_brush.zone_dropdown.selected).is_equal(1)
	assert_bool(_brush._zone_kind_option.disabled).is_true()


func test_painting_an_existing_zone_with_another_kind_picked_never_retypes_it() -> void:
	# The reported bug (2026-08-12): paint a named zone, change the kind pick, keep painting the
	# same name -- the whole zone silently converted. Kind locks at creation; the stale pick in
	# _zone_kind must not leak through the paint wire.
	_type_name("gate")
	game.dev_controller._paint_zone(Vector2i(2, 2))
	_brush._zone_kind = CAPTURE
	game.dev_controller._paint_zone(Vector2i(3, 2))

	assert_int(game.zone_manager.kind_of("gate")).is_equal(PATROL)
	assert_array(game.zone_manager.cells_in("gate")).contains_exactly_in_any_order(
		[Vector2i(2, 2), Vector2i(3, 2)])


# ---- the picked-zone highlight ----

func test_the_picked_zone_is_lifted_on_the_highlight_layer() -> void:
	game.zone_manager.paint_cell("gate", PATROL, Vector2i(1, 1))
	game.zone_manager.paint_cell("gate", PATROL, Vector2i(2, 1))
	game.zone_manager.paint_cell("throne", CAPTURE, Vector2i(4, 4))
	_brush._on_zone_dropdown_item_selected(1)

	var highlight: TileMapLayer = game.overlay_manager.zone_highlight_overlay
	assert_array(highlight.get_used_cells()).contains_exactly_in_any_order(
		[Vector2i(1, 1), Vector2i(2, 1)])

	_brush._set_paint_mode(TileBrushTool.PaintMode.TERRAIN)
	assert_array(highlight.get_used_cells()).is_empty()


func test_the_highlight_is_authoring_scaffolding_like_the_patrol_layer() -> void:
	game.overlay_manager.set_zone_visibility(true)
	assert_bool(game.overlay_manager.zone_highlight_overlay.visible).is_true()
	game.overlay_manager.set_zone_visibility(false)
	assert_bool(game.overlay_manager.zone_highlight_overlay.visible).is_false()


# ---- hold-to-drag, at the routing wire ----

func test_erase_rides_a_held_right_button_and_stops_on_release() -> void:
	var cell := _hover_cell()
	_type_name("gate")
	var dc: DevController = game.dev_controller

	game.zone_manager.paint_cell("gate", PATROL, cell)
	dc.handle_tile_brush(_press(MOUSE_BUTTON_RIGHT, true))
	assert_bool(game.zone_manager.contains("gate", cell)).is_false()   # press erases, as before

	game.zone_manager.paint_cell("gate", PATROL, cell)
	dc.handle_tile_brush(_motion())
	assert_bool(game.zone_manager.contains("gate", cell)).is_false()   # motion erases while held

	dc.handle_tile_brush(_press(MOUSE_BUTTON_RIGHT, false))
	game.zone_manager.paint_cell("gate", PATROL, cell)
	dc.handle_tile_brush(_motion())
	assert_bool(game.zone_manager.contains("gate", cell)).is_true()    # released: motion is inert


func test_paint_rides_a_held_left_button_and_stops_on_release() -> void:
	var cell := _hover_cell()
	_type_name("gate")
	var dc: DevController = game.dev_controller

	dc.handle_tile_brush(_press(MOUSE_BUTTON_LEFT, true))
	assert_bool(game.zone_manager.contains("gate", cell)).is_true()

	game.zone_manager.erase_cell_from("gate", cell)
	dc.handle_tile_brush(_motion())
	assert_bool(game.zone_manager.contains("gate", cell)).is_true()    # motion paints while held

	dc.handle_tile_brush(_press(MOUSE_BUTTON_LEFT, false))
	game.zone_manager.erase_cell_from("gate", cell)
	dc.handle_tile_brush(_motion())
	assert_bool(game.zone_manager.contains("gate", cell)).is_false()   # released: motion is inert


# ---- scoped erase through the brush ----

func test_erase_carves_only_the_picked_zone() -> void:
	var cell := _hover_cell()
	game.zone_manager.paint_cell("patrol route", PATROL, cell)
	game.zone_manager.paint_cell("the point", CAPTURE, cell)
	_type_name("patrol route")

	game.dev_controller.handle_tile_brush(_press(MOUSE_BUTTON_RIGHT, true))

	assert_bool(game.zone_manager.contains("patrol route", cell)).is_false()
	assert_bool(game.zone_manager.contains("the point", cell)).is_true()


func test_erase_with_no_zone_picked_is_a_noop() -> void:
	var cell := _hover_cell()
	game.zone_manager.paint_cell("gate", PATROL, cell)
	assert_str(_brush.selected_zone_name()).is_equal("")

	game.dev_controller.handle_tile_brush(_press(MOUSE_BUTTON_RIGHT, true))

	assert_bool(game.zone_manager.contains("gate", cell)).is_true()
