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
