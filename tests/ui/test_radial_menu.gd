# The action ring's BEHAVIOUR (#467), on the real game scene — the geometry has its own pure suite
# next door, this one is about what the widget does with it.
#
# Every case here exists because the design has a property nothing else in the tree can see, and
# each is a property a plausible "simplification" would quietly remove:
#   * the hit area is UNBOUNDED, so a pointer nowhere near the drawn ring still selects;
#   * a CATEGORY pick keeps the menu alive and the unit selected, which is the whole recoverability
#     ruling and also the #105/#107 trap (state wiped on the way INTO the next mode);
#   * right-click collapses ONE ring, driven through the real gui_input rather than by calling
#     back() — a signal with no listener is legal GDScript (#103);
#   * a category whose one child is its own VERB collapses, and one whose child has a different
#     name does not — the pair is what says the rule is about the name rather than the count;
#   * the tree is SNAPSHOTTED at open, so a preview cannot disagree with what commits.
#
# Fixture is tests/ui/test_menu_catalogue_rows.gd's — see tests/README.md -> Testing the game scene.
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
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), cell)
	assert_object(unit).is_not_null()
	return unit


# Open a unit's ring the way a click does, so the selection is stored through the one select door.
func _open(unit: Unit) -> ActionMenuController:
	game._click_idle(unit.get_projected_destination())
	await await_idle_frame()
	var controller: ActionMenuController = null
	for child in game.get_children():
		if child is ActionMenuController and not child.is_queued_for_deletion():
			controller = child
	assert_object(controller).override_failure_message("clicking the unit opened no menu").is_not_null()
	return controller


# Well past the outermost ring the widget could ever draw — derived, never a typed-in number, so
# retuning the look cannot turn this into a claim about pixels.
func _far() -> float:
	return (ActionMenuController.RING_INNER_RADIUS
		+ 4.0 * (ActionMenuController.RING_THICKNESS + ActionMenuController.RING_GAP)) * 5.0


func _names(rows: Array) -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in rows:
		out.append(String(row.get("name", "")))
	return out


func _index_of_a_category(controller: ActionMenuController) -> int:
	var rows: Array = controller.level_nodes()
	for i in range(rows.size()):
		var children: Array = rows[i].get("children", [])
		if not children.is_empty():
			return i
	return -1


func _click(controller: ActionMenuController, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = controller.centre()
	controller._root.gui_input.emit(event)


# ==============================================================================
#  The hit area is unbounded
# ==============================================================================

# THE headline property: a flick in a direction is a selection wherever the pointer physically is.
# Bound the hit test to the drawn wedges and this reds — which is the mutant to check it with.
func test_a_pointer_far_outside_the_ring_still_selects_the_slice_it_points_at() -> void:
	var unit := _spawn(Vector2i(1, 0))
	var controller := await _open(unit)

	var rows: Array = controller.level_nodes()
	assert_int(rows.size()).override_failure_message("the ring opened empty").is_greater(0)

	for i in range(rows.size()):
		controller.aim_at(controller.point_in_slice(i, _far()))
		assert_str(String(controller.selected_node().get("name", ""))) \
			.override_failure_message("a far pointer aimed at slice %d selected something else" % i) \
			.is_equal(String(rows[i].get("name", "")))


func test_the_dead_centre_selects_nothing_and_a_click_there_dismisses() -> void:
	var unit := _spawn(Vector2i(1, 0))
	var controller := await _open(unit)

	controller.aim_at(controller.centre())
	assert_bool(controller.selected_node().is_empty()) \
		.override_failure_message("the dead zone selected a slice").is_true()

	_click(controller, MOUSE_BUTTON_LEFT)
	await await_idle_frame()
	assert_bool(is_instance_valid(controller) and not controller.is_queued_for_deletion()) \
		.override_failure_message("a click in the dead centre did not dismiss the ring").is_false()


# ==============================================================================
#  A category pick keeps the menu — and the selection
# ==============================================================================

# The recoverability ruling, and the #105/#107 trap in one case. The dropdown emitted `cancelled`
# (hence clear_selection) and freed itself on EVERY pick; doing that on the way into a category is
# what would make a wrong turn cost a dismiss-and-reopen.
func test_opening_a_category_keeps_the_ring_alive_and_the_board_selected() -> void:
	var unit := _spawn(Vector2i(1, 0))
	var controller := await _open(unit)
	assert_int(game.game_state) \
		.override_failure_message("the fixture did not reach TILE_SELECTED, so this case is vacuous") \
		.is_equal(game.GameState.TILE_SELECTED)

	# Count the signal, because `cancelled` IS the mechanism: clear_selection() does not null
	# selected_unit (exit_current_mode does, #149), so asserting on the unit alone cannot see this
	# and passed against a mutant that emitted here. What it resets is the game STATE and the
	# selection overlays -- the board unlocking underneath an open menu.
	var cancels := [0]
	controller.cancelled.connect(func(_me) -> void: cancels[0] += 1)

	var category := _index_of_a_category(controller)
	assert_int(category).override_failure_message("the ring offered no category at all").is_greater(-1)

	controller.aim_at(controller.point_in_slice(category, _far()))
	controller.commit()

	assert_bool(is_instance_valid(controller) and not controller.is_queued_for_deletion()) \
		.override_failure_message("opening a category tore the ring down").is_true()
	assert_int(controller.level_count()) \
		.override_failure_message("committing a category grew no ring").is_equal(2)
	assert_int(cancels[0]) \
		.override_failure_message("a category pick emitted `cancelled` -- the #105/#107 trap, which clears the board's selection on the way INTO the next ring") \
		.is_equal(0)
	assert_int(game.game_state) \
		.override_failure_message("the board fell out of TILE_SELECTED while its own menu was still open") \
		.is_equal(game.GameState.TILE_SELECTED)
	# The typed read is the assertion, not a null check: a freed Unit compares == null but dies on
	# assignment, which is the #149 lesson.
	var still: Unit = game.selected_unit
	assert_object(still).override_failure_message("the unit was deselected on the way INTO its own submenu").is_same(unit)


func test_right_click_collapses_one_ring_at_a_time_and_then_dismisses() -> void:
	var unit := _spawn(Vector2i(1, 0))
	var controller := await _open(unit)

	var category := _index_of_a_category(controller)
	assert_int(category).is_greater(-1)
	controller.aim_at(controller.point_in_slice(category, _far()))
	controller.commit()
	assert_int(controller.level_count()).is_equal(2)

	_click(controller, MOUSE_BUTTON_RIGHT)
	assert_int(controller.level_count()) \
		.override_failure_message("right-click did not collapse the open ring").is_equal(1)
	assert_bool(is_instance_valid(controller) and not controller.is_queued_for_deletion()) \
		.override_failure_message("backing out of a submenu dismissed the whole menu").is_true()

	_click(controller, MOUSE_BUTTON_RIGHT)
	await await_idle_frame()
	assert_bool(is_instance_valid(controller) and not controller.is_queued_for_deletion()) \
		.override_failure_message("right-click at the top level did not dismiss the ring").is_false()


# ==============================================================================
#  A category of one, when the one IS the category (#467 round 2)
# ==============================================================================

# "There is no reason to put Move under Move" (dev). A lone unit has no Group Move, so the Move
# category holds nothing but the Move verb and must hand it up as a TERMINAL slice -- committing it
# plans a move rather than growing a ring of one.
func test_move_is_a_terminal_slice_when_group_move_is_not_offered() -> void:
	var unit := _spawn(Vector2i(1, 0))
	assert_bool(unit.has_squad()) \
		.override_failure_message("a squadmate would offer Group Move and this case would prove nothing") \
		.is_false()

	var controller := await _open(unit)
	var move := _row_named(controller.level_nodes(), "Move")
	assert_bool(move.is_empty()).override_failure_message("the ring offered no Move at all").is_false()
	assert_bool((move.get("children", []) as Array).is_empty()) \
		.override_failure_message("Move opened a ring holding nothing but Move").is_true()


# Inspect is top level, and it is the same rule doing it: a group of one holding the verb of its own
# name. Nothing about Inspect is special-cased, which is the point.
func test_inspect_is_a_terminal_top_level_slice() -> void:
	var unit := _spawn(Vector2i(1, 0))
	var controller := await _open(unit)

	var inspect := _row_named(controller.level_nodes(), "Inspect")
	assert_bool(inspect.is_empty()) \
		.override_failure_message("Inspect was not on the inner ring").is_false()
	assert_bool((inspect.get("children", []) as Array).is_empty()) \
		.override_failure_message("Inspect grew a ring of one").is_true()


# The other side of the same rule, and the reason it is not just "collapse when there is one child":
# a lone Squad Up says something the word Squad does not, so it keeps its ring.
func test_a_lone_child_with_its_own_name_keeps_its_ring() -> void:
	var unit := _spawn(Vector2i(1, 0))
	_spawn(Vector2i(2, 0))   # somebody to squad up WITH
	var controller := await _open(unit)

	var squad := _row_named(controller.level_nodes(), "Squad")
	assert_bool(squad.is_empty()).override_failure_message("Squad Up was not offered at all").is_false()
	assert_bool((squad.get("children", []) as Array).is_empty()) \
		.override_failure_message("the Squad category collapsed into the verb inside it") \
		.is_false()


func _row_named(rows: Array, text: String) -> Dictionary:
	for row: Dictionary in rows:
		if String(row.get("name", "")) == text:
			return row
	return {}


# ==============================================================================
#  The tree is a snapshot
# ==============================================================================

# A ghosted category shows its contents BEFORE it is opened, so those contents are read once, at
# open. Re-query on hover and a preview can disagree with what commits — which is the bug this
# case exists to make impossible rather than the performance note it looks like.
func test_the_ring_does_not_re_derive_itself_while_it_is_open() -> void:
	var unit := _spawn(Vector2i(1, 0))
	var controller := await _open(unit)

	var before := _names(controller.level_nodes())
	assert_int(before.size()).override_failure_message("the ring opened empty").is_greater(0)

	# Spend the squad's turn underneath the open menu: populate() would answer differently now,
	# since every main-action row is gated on it.
	game.squad_manager.set_has_acted(unit.squad, true)
	var fresh: Array = game.main_action_menu.build_tree(unit)
	assert_array(_names(fresh)) \
		.override_failure_message("the fixture did not actually change what populate() answers") \
		.is_not_equal(before)

	controller.aim_at(controller.point_in_slice(0, _far()))
	assert_array(_names(controller.level_nodes())) \
		.override_failure_message("the open ring re-derived itself from live state") \
		.is_equal(before)


# ==============================================================================
#  A committed order brings the camera back (#471)
# ==============================================================================

# The fixture's 8-cell strip is SMALLER than the view, and _clamp_axis centres the map outright in
# that case -- the camera physically cannot be anywhere but the middle, so a case driving it there
# asserts nothing at all. Painted per case rather than in before_test: every other case here is
# about the widget and does not want a 40x20 board.
func _paint_a_pannable_board() -> void:
	for x in range(40):
		for y in range(20):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	game.camera_controller.refresh_bounds(game.grid)


# The first TERMINAL slice the ring is offering. Deliberately not a NAMED verb: which rows a unit
# gets is gating, and this case is about what a commit DOES, not about which row did it.
func _index_of_a_terminal(controller: ActionMenuController) -> int:
	var rows: Array = controller.level_nodes()
	for i in range(rows.size()):
		var children: Array = rows[i].get("children", [])
		if children.is_empty() and not bool(rows[i].get("disabled", false)):
			return i
	return -1


# #471. The ring does not lock the board, so the player can pan anywhere while choosing -- and the
# order they commit is about the UNIT, which may by then be off screen. This is the 2D half of the
# wire; tests/presentation/test_camera_follow.gd pins the half only the 3D rig can see.
func test_committing_an_order_brings_the_camera_back_to_the_acting_unit() -> void:
	_paint_a_pannable_board()
	var unit := _spawn(Vector2i(20, 10))
	var camera: CameraController = game.camera_controller
	camera.snap_to_position(GridUtils.cell_world(game.grid, Vector2i(36, 17)))
	var away: Vector2 = camera.global_position
	var home := GridUtils.cell_world(game.grid, unit.get_projected_destination())
	assert_bool(away.distance_to(home) > 1.0).override_failure_message(
			"the camera clamp parked the view on the unit anyway; the case proves nothing").is_true()

	var controller := await _open(unit)
	var terminal := _index_of_a_terminal(controller)
	assert_int(terminal).override_failure_message("the ring offered no terminal slice").is_greater(-1)
	controller.aim_at(controller.point_in_slice(terminal, _far()))
	controller.commit()
	await await_idle_frame()

	assert_vector(camera.global_position).override_failure_message(
			"a committed order left the camera where the player had panned it").is_equal(home)


# The other half of the rule, and the reason the return hangs off `action_selected` rather than off
# the menu closing: backing out with no order leaves the view exactly where the player put it.
func test_dismissing_the_ring_leaves_the_camera_where_the_player_panned_it() -> void:
	_paint_a_pannable_board()
	var unit := _spawn(Vector2i(20, 10))
	var camera: CameraController = game.camera_controller
	camera.snap_to_position(GridUtils.cell_world(game.grid, Vector2i(36, 17)))
	var away: Vector2 = camera.global_position
	assert_bool(away.distance_to(GridUtils.cell_world(game.grid, unit.get_projected_destination())) > 1.0) \
		.override_failure_message("the camera clamp parked the view on the unit anyway; the case proves nothing") \
		.is_true()

	var controller := await _open(unit)
	controller.aim_at(controller.centre())   # the dead zone: a click here dismisses
	_click(controller, MOUSE_BUTTON_LEFT)
	await await_idle_frame()

	assert_bool(is_instance_valid(controller) and not controller.is_queued_for_deletion()) \
		.override_failure_message("the fixture did not actually dismiss the ring").is_false()
	assert_vector(camera.global_position).override_failure_message(
			"backing out of the ring yanked the camera to the unit anyway").is_equal(away)
