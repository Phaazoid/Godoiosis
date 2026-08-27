# The dev-tools scope tree (#382). Three kinds of law.
#
# The LEAVES laws pin the declaration complete: every leaf resolves to a real page, every page in
# the stack has exactly one leaf (an orphan page is a tool that silently vanished — the Game tab
# shipped without a tooltip under the index-based scheme this replaced), and every leaf explains
# itself.
#
# The WIRE cases drive the TREE selection, not current_tab — the tree is the real input path now,
# and driving tab_changed directly would test the old wire. What must keep working through it:
# the zone overlay shows only on the Tile Brush leaf, the brush disarms on leaving, and the
# click-a-unit jump moves the tree too.
#
# The HEADER cases pin the (modified) marker's narrow meaning: terrain and zone AUTHORING marks,
# save/load clears, and unit movement deliberately does not mark — a mid-battle board is always
# "changed" in the snapshot sense, and a marker that is always on says nothing.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const PROLOG := "missions/Prolog"

var _main: Node
var game: Node2D
var overlay: DevOverlay


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	overlay = game.dev_overlay
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func _leaf(label: String) -> TreeItem:
	var scope_item := overlay.tool_tree.get_root().get_first_child()
	while scope_item != null:
		var item := scope_item.get_first_child()
		while item != null:
			if item.get_text(0) == label:
				return item
			item = item.get_next()
		scope_item = scope_item.get_next()
	return null


func _select(label: String) -> void:
	var item := _leaf(label)
	assert_object(item).override_failure_message("no tree leaf named '%s'" % label).is_not_null()
	item.select(0)   # fires item_selected, the same path a click takes
	await await_idle_frame()


# --- The LEAVES laws -------------------------------------------------------------------------

func test_every_leaf_resolves_to_a_real_page() -> void:
	var dead: Array[String] = []
	for leaf: Dictionary in DevOverlay.LEAVES:
		if overlay.get_node_or_null(leaf["page"]) == null:
			dead.append("%s -> %s" % [leaf["label"], leaf["page"]])
	assert_array(dead).override_failure_message(
		"Leaves pointing at no page: %s" % ", ".join(dead)).is_empty()


# Every page in the stack has exactly one leaf. Walks BOTH containers — DevTabs' direct pages and
# AuthoringTabs' nested ones — so a tool added to either cannot ship unreachable.
func test_every_page_has_exactly_one_leaf() -> void:
	var pages: Array[Control] = []
	var tabs: TabContainer = overlay.get_node("%DevTabs")
	for i in tabs.get_tab_count():
		var page := tabs.get_tab_control(i)
		if page == overlay.unit_authoring:
			var authoring: TabContainer = overlay.get_node("%AuthoringTabs")
			for j in authoring.get_tab_count():
				pages.append(authoring.get_tab_control(j))
			continue
		pages.append(page)
	var claimed: Array[Control] = []
	for leaf: Dictionary in DevOverlay.LEAVES:
		claimed.append(overlay.get_node_or_null(leaf["page"]) as Control)
	for page in pages:
		assert_int(claimed.count(page)).override_failure_message(
			"page '%s' has %d leaves -- every tool needs exactly one way in" % [page.name, claimed.count(page)]
		).is_equal(1)


func test_every_leaf_has_a_tooltip() -> void:
	var untipped: Array[String] = []
	for leaf: Dictionary in DevOverlay.LEAVES:
		if String(leaf.get("tip", "")).strip_edges() == "":
			untipped.append(leaf["label"])
	assert_array(untipped).override_failure_message(
		"Leaves with no tooltip: %s" % ", ".join(untipped)).is_empty()


func test_boot_selection_is_spawn() -> void:
	assert_str(overlay.current_tab_title()).is_equal("Scenario / Spawn")


# --- The wires ------------------------------------------------------------------------------

# The zone overlay follows the LEAF, driven through the tree: visible on Tile Brush (window up),
# gone the moment you leave. This is the #382 restatement of the rule the tab strip carried.
func test_zones_show_only_on_the_tile_brush_leaf() -> void:
	overlay.visible = true
	await _select("Tile Brush")
	assert_bool(game.overlay_manager.zones_authoring_visible).is_true()
	await _select("Properties")
	assert_bool(game.overlay_manager.zones_authoring_visible).is_false()


# Leaving the Tile Brush leaf disarms the brush — without this the brush keeps painting every
# cell the cursor crosses from any other leaf, with nothing held down.
func test_leaving_the_tile_brush_leaf_disarms_the_brush() -> void:
	await _select("Tile Brush")
	# Armed through the CHECKBOX, the real path -- deactivate() disarms by unpressing it, which
	# no-ops against a brush_active set directly (the tests/README direct-set-precondition trap).
	var check: CheckBox = overlay.tile_brush.get_node("Panel/TileBrushRow/TileBoxCheck")
	check.button_pressed = true
	assert_bool(overlay.tile_brush.brush_active).override_failure_message(
		"precondition: the checkbox did not arm the brush").is_true()
	await _select("Game")
	assert_bool(overlay.tile_brush.brush_active).override_failure_message(
		"the brush stayed armed after navigating away -- it will paint from any leaf").is_false()


# The brush's page clause, which the disarm case above CANNOT see: that one arms through the real
# checkbox, so leaving the page unticks it and brush_active is already false. A flag set from
# anywhere else -- a fixture, a future tool, a restored panel state -- would still have armed a
# brush on a page the dev is not looking at.
#
# Added because a mutant deleting the clause PASSED the whole suite. brush_armed() reads the STATE
# (which page is up) rather than trusting the disarm EVENT to have fired.
func test_a_stale_brush_flag_does_not_arm_from_another_page() -> void:
	game.set_dev_mode(true)
	await _select("Game")
	overlay.tile_brush.brush_active = true   # deliberately NOT through the checkbox
	assert_bool(game.dev_controller.brush_armed()).override_failure_message(
		"the brush armed itself from the Game page -- a stale flag is enough").is_false()

	await _select("Tile Brush")
	overlay.tile_brush.brush_active = true
	assert_bool(game.dev_controller.brush_armed()).override_failure_message(
		"the brush refuses to arm on its own page; the clause is refusing everything").is_true()


# --- brush_pick_row(): where a click is AIMED (#582) ------------------------------------------

# The toggle that lets the brush author a cell the camera cannot see. It is gated on the same arming
# the rest of the brush is, and it rides the LEVEL row -- so it must go quiet in every mode that does
# not ask for a height, and the moment the brush is not armed at all.
func test_the_aim_row_follows_the_brush_height_and_only_while_it_is_armed() -> void:
	game.set_dev_mode(true)
	await _select("Tile Brush")
	var brush: TileBrushTool = overlay.tile_brush
	brush.brush_active = true
	brush.paint_mode = TileBrushTool.PaintMode.TERRAIN

	assert_int(game.dev_controller.brush_pick_row()).override_failure_message(
		"the aim answered while the toggle was off; ordinary picking must stand") \
		.is_equal(BoardPicker.NO_COLUMN)

	brush.pick_at_brush_height = true
	brush.set_elevation(-Terrain.UNITS_PER_LEVEL - 1)
	assert_int(game.dev_controller.brush_pick_row()).override_failure_message(
		"the aim did not follow the brush's own Height") \
		.is_equal(BoardSpace.top_row_of(brush.selected_elevation()) + 1)
	assert_int(game.dev_controller.brush_pick_row()).override_failure_message(
		"a sunken aim came back at or above the floor; the case proves nothing") \
		.is_less(BoardSpace.FLAT_TOP_ROW)

	# The gates, one at a time: a mode with no level row, then no armed brush at all.
	brush.paint_mode = TileBrushTool.PaintMode.ZONE
	assert_int(game.dev_controller.brush_pick_row()).override_failure_message(
		"the aim survived a mode that never asks for a height") \
		.is_equal(BoardPicker.NO_COLUMN)
	brush.paint_mode = TileBrushTool.PaintMode.TERRAIN
	brush.brush_active = false
	assert_int(game.dev_controller.brush_pick_row()).override_failure_message(
		"the aim survived a disarmed brush") \
		.is_equal(BoardPicker.NO_COLUMN)


# --- showing(): the one answer to which page owns input (2026-08-23) -------------------------

# It replaced four hand-rolled spellings, and the NESTED pair is why it has to be a function rather
# than a comparison: Spawn and Character Editor share the Unit Authoring container, so either is
# showing only when Unit Authoring is the current top-level tab AND the current authoring tab.
# Comparing against %DevTabs alone reports BOTH as showing whenever Unit Authoring is up.
func test_showing_resolves_the_nested_authoring_pair() -> void:
	await _select("Spawn")
	assert_bool(overlay.showing(overlay.spawn)).is_true()
	assert_bool(overlay.showing(overlay.character_editor)).override_failure_message(
		"Character Editor reads as showing while Spawn is the page -- the nested tab is ignored") \
		.is_false()

	await _select("Characters")
	assert_bool(overlay.showing(overlay.character_editor)).is_true()
	assert_bool(overlay.showing(overlay.spawn)).is_false()

	await _select("Tile Brush")
	assert_bool(overlay.showing(overlay.tile_brush)).is_true()
	assert_bool(overlay.showing(overlay.spawn)).override_failure_message(
		"Spawn reads as showing from another leaf entirely").is_false()


# SPACE spawns from the SPAWN page and nowhere else (dev, 2026-08-23: "when I press space in the
# brush mode, it spawns a unit"). Driven through game.gd's real input arm rather than by calling
# the spawner, because the gate is the thing under test -- and the roster count is what a spawn
# actually costs, so a case asserting only that no error was raised would pass against the bug.
#
# The TARGET cell is authored via pointer_source (the #222 seam the 3D picker feeds), never left
# to the mouse derivation: headless, the hover cell is f(camera transform, wherever the display
# server puts the mouse), and the not-armed press below is itself a center_on_position -- so an
# un-authored target sampled a mid-glide camera and forked by ENVIRONMENT, red on CI while green
# on every local run (2026-08-26). Injecting the seam still drives the presenter's real update;
# setting last_hovered_cell directly would be reclaimed by its _process one frame later.
func test_space_spawns_only_from_the_spawn_page() -> void:
	game.set_dev_mode(true)
	var target := _spawnable_cell()
	game.hover_presenter.pointer_source = func() -> Vector2i: return target

	await _select("Tile Brush")
	var before: int = game.units_root.get_child_count()
	game._unhandled_input(_space())
	await await_idle_frame()
	var after: int = game.units_root.get_child_count()
	assert_int(after).override_failure_message(
		"SPACE spawned a unit while the Tile Brush page was up").is_equal(before)

	await _select("Spawn")
	# Two gates between the press and a unit, asserted separately so a red names its half -- the
	# old single message blamed the gate while the gate was fine and the CELL was refused.
	assert_bool(game.dev_controller.spawn_armed()).override_failure_message(
		"the Spawn page is up but the gate is not armed").is_true()
	game._unhandled_input(_space())
	await await_idle_frame()
	var after_on_spawn: int = game.units_root.get_child_count()
	assert_int(after_on_spawn).override_failure_message(
		"SPACE was armed and aimed at %s (walkable, empty) and no unit appeared -- the spawn itself failed"
			% str(target)) \
		.is_greater(before)


# First cell the board's own predicates accept -- the same is_walkable spawn_unit asks -- so this
# case and the spawn gate cannot disagree about legality, and no authored content is pinned.
func _spawnable_cell() -> Vector2i:
	for cell: Vector2i in game.grid.get_used_cells():
		if game._board().is_walkable(cell) and game.get_unit_at_cell(cell) == null:
			return cell
	assert_bool(false).override_failure_message(
		"precondition: no walkable empty cell on the fixture board -- nothing above proves anything") \
		.is_true()
	return GridUtils.NO_CELL


func _space() -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	return key


# The click-a-unit jump goes through show_leaf, so the TREE moves with the page — a raw
# current_tab write would leave the tree pointing at the leaf you left.
func test_show_leaf_syncs_the_tree_selection() -> void:
	await _select("Game")
	overlay.show_leaf(overlay.unit_editor)
	assert_str(overlay.current_tab_title()).is_equal("Scenario / Unit Editor")
	var selected := overlay.tool_tree.get_selected()
	assert_object(selected).is_not_null()
	assert_str(selected.get_text(0)).is_equal("Unit Editor")


# Spawn and Character share the Unit Authoring container in the scene; the tree flattens them.
# Selecting either must set BOTH containers, or the page shown is whatever the inner container
# happened to hold last.
func test_selecting_character_reaches_through_the_authoring_container() -> void:
	await _select("Characters")
	var tabs: TabContainer = overlay.get_node("%DevTabs")
	assert_object(tabs.get_current_tab_control()).is_same(overlay.unit_authoring)
	var authoring: TabContainer = overlay.get_node("%AuthoringTabs")
	assert_object(authoring.get_current_tab_control()).is_same(overlay.character_editor)
	assert_str(overlay.current_tab_title()).is_equal("Project / Characters")


# --- The header's (modified) marker -----------------------------------------------------------

func _load_prolog() -> void:
	game.scenario_manager.load_scenario(ScenarioManager.scenario_path(PROLOG))
	overlay.scenario_header.refresh_on_show()
	await await_idle_frame()


func test_a_terrain_paint_marks_the_scenario_modified() -> void:
	await _load_prolog()
	assert_bool(overlay.scenario_header.is_modified()).override_failure_message(
		"a fresh load already reads modified -- the stamp is not taken at load").is_false()
	var cells: Array[Vector2i] = game.grid.get_used_cells()
	var source_id: int = game.grid.get_cell_source_id(cells[0])
	var coords: Vector2i = game.grid.get_cell_atlas_coords(cells[0])
	game.grid.paint(cells[1], source_id, coords)
	assert_bool(overlay.scenario_header.is_modified()).override_failure_message(
		"painting terrain did not mark the scenario modified").is_true()


func test_a_zone_paint_marks_the_scenario_modified() -> void:
	await _load_prolog()
	game.zone_manager.paint_cell("law-zone", ZoneManager.Kind.PATROL, game.grid.get_used_cells()[0])
	assert_bool(overlay.scenario_header.is_modified()).is_true()


func test_unit_movement_does_not_mark_the_scenario_modified() -> void:
	await _load_prolog()
	var unit: Unit = null
	for child in game.units_root.get_children():
		if child is Unit:
			unit = child
			break
	assert_object(unit).override_failure_message("Prolog spawned no units; the case is vacuous").is_not_null()
	unit.movement.set_cell(unit.movement.cell + Vector2i(1, 0))
	assert_bool(overlay.scenario_header.is_modified()).override_failure_message(
		"unit movement marked the scenario modified -- a mid-battle board would always read modified"
	).is_false()


# The marker gap the verticality fixture surfaced (#259 rework): the Unit Editor's own Save wrote
# the live unit and told nobody, so "(modified)" never lit and the dev had no cue an Update was
# owed. The save also flags the unit dev_edited -- the authored-save divergence the flow suite
# (test_cast_references.gd) pins from the capture side.
func test_a_unit_editor_save_marks_the_scenario_modified() -> void:
	await _load_prolog()
	var unit: Unit = null
	for child in game.units_root.get_children():
		if child is Unit:
			unit = child
			break
	assert_object(unit).override_failure_message("Prolog spawned no units; the case is vacuous").is_not_null()
	overlay.unit_editor.edit_unit(unit)
	await await_idle_frame()
	overlay.unit_editor._save_button.pressed.emit()   # the real button wire, not the handler
	assert_bool(overlay.scenario_header.is_modified()).override_failure_message(
		"the Unit Editor's Save did not mark the scenario modified").is_true()
	assert_bool(unit.dev_edited).override_failure_message(
		"the saved unit is not flagged dev_edited -- an authored Update would discard the edit").is_true()


# Round 2 of the sweep: the header lights the moment an edit is STAGED (the dev reads Update's
# marker as "anything to save?"), and the header's capture FLUSHES staged edits through the
# capturing signal, so an Update taken mid-edit saves exactly what the panel shows.
func test_a_staged_unit_edit_lights_the_header_and_the_capture_flushes_it() -> void:
	await _load_prolog()
	var unit: Unit = null
	for child in game.units_root.get_children():
		if child is Unit:
			unit = child
			break
	assert_object(unit).override_failure_message("Prolog spawned no units; the case is vacuous").is_not_null()
	overlay.unit_editor.edit_unit(unit)
	await await_idle_frame()
	overlay.unit_editor._stage_unit_name("Renamed by the sweep")
	assert_bool(overlay.scenario_header.is_modified()).override_failure_message(
		"staging an edit did not light the header -- Update gives no cue a save is owed").is_true()
	overlay.scenario_header.capturing.emit()   # exactly what Update fires before capturing
	assert_str(unit.get_unit_name()).override_failure_message(
		"the capture did not flush the staged edit -- Update saves a board the panel disagrees with"
	).is_equal("Renamed by the sweep")
	assert_bool(overlay.unit_editor._dirty).is_false()


# A LIVE write (no Save step by design) must mark too, and diverge the unit -- element states are
# unit state a snapshot carries, so an authored Update re-referencing it away would drop the edit.
func test_an_element_state_toggle_marks_the_scenario_and_diverges_the_unit() -> void:
	await _load_prolog()
	var unit: Unit = null
	for child in game.units_root.get_children():
		if child is Unit:
			unit = child
			break
	assert_object(unit).override_failure_message("Prolog spawned no units; the case is vacuous").is_not_null()
	overlay.unit_editor.edit_unit(unit)
	await await_idle_frame()
	overlay.unit_editor._on_element_state_toggled(unit, Elemental.State.WET, true)
	assert_bool(overlay.scenario_header.is_modified()).is_true()
	assert_bool(unit.dev_edited).is_true()


func test_update_clears_the_modified_marker() -> void:
	await _load_prolog()
	var cells: Array[Vector2i] = game.grid.get_used_cells()
	game.grid.paint(cells[1], game.grid.get_cell_source_id(cells[0]), game.grid.get_cell_atlas_coords(cells[0]))
	assert_bool(overlay.scenario_header.is_modified()).is_true()
	# The save itself, not the button: the dialog is the guard suite's business, and a real save
	# here would overwrite the tracked mission. Stamp mechanics only.
	overlay.scenario_header._stamp_clean()
	overlay.scenario_header.refresh_loaded_label()
	assert_bool(overlay.scenario_header.is_modified()).is_false()
	assert_bool(overlay.scenario_header.loaded_label.text.ends_with("(modified)")).is_false()


func test_a_load_clears_the_modified_marker() -> void:
	await _load_prolog()
	game.zone_manager.paint_cell("law-zone", ZoneManager.Kind.PATROL, game.grid.get_used_cells()[0])
	assert_bool(overlay.scenario_header.is_modified()).is_true()
	await _load_prolog()
	assert_bool(overlay.scenario_header.is_modified()).override_failure_message(
		"a reload did not clear the marker -- the board and the file agree again by definition"
	).is_false()
