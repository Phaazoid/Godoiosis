# The Unit Editor's sub-tab split (dev ask 2026-08-11): three pages (Stats / Gear & Jobs /
# Body & Affinity) between an always-visible header+Save row and the five action buttons.
# The load-bearing claims: the action buttons stay DIRECT children of unit_editor_container
# (the lifecycle suite's flat finder is the other pin), the stats grid is the inspect panel's
# two-column (columns = 4) shape, and the active sub-tab survives the full-panel repaint that
# every staged toggle triggers -- without that, each affinity click yanks the dev back to tab 0.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

var _main: Node
var game: Node2D
var _editor: UnitEditorTool

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
	var overlay: DevOverlay = game.dev_overlay
	_editor = overlay.unit_editor
	await await_idle_frame()

func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()

func _spawn(cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), cell)
	assert_object(unit).is_not_null()
	return unit

func _subtabs() -> TabContainer:
	return _editor.unit_editor_container.get_node_or_null("SubTabs") as TabContainer

func test_three_subtabs_with_a_two_column_stats_grid() -> void:
	var unit := _spawn(Vector2i(1, 0))
	_editor.edit_unit(unit)

	var tabs := _subtabs()
	assert_object(tabs).is_not_null()
	assert_int(tabs.get_tab_count()).is_equal(3)
	var grids: Array[Node] = tabs.get_tab_control(0).find_children("*", "GridContainer", true, false)
	assert_int(grids.size()).is_equal(1)
	assert_int((grids[0] as GridContainer).columns).is_equal(4)

func test_the_action_buttons_stay_direct_children() -> void:
	# The lifecycle suite's flat search is the contract; this names it explicitly.
	var unit := _spawn(Vector2i(1, 0))
	_editor.edit_unit(unit)

	for label in ["Delete Unit", "Down Unit", "Revive Unit"]:
		var found := false
		for child in _editor.unit_editor_container.get_children():
			if child is Button and (child as Button).text == label:
				found = true
		assert_bool(found).override_failure_message("%s is not a direct child" % label).is_true()

func test_scroll_position_survives_a_repaint() -> void:
	# The 2026-08-11 nitpick: a staged toggle rebuilds the page ScrollContainers, snapping the
	# scrollbar to the top mid-edit. The restore is deferred, so the assert waits a frame.
	var unit := _spawn(Vector2i(1, 0))
	_editor.edit_unit(unit)
	var tabs := _subtabs()
	tabs.current_tab = 2
	await await_idle_frame()

	var page := tabs.get_tab_control(2) as ScrollContainer
	assert_object(page).is_not_null()
	var range_max: int = int(page.get_v_scroll_bar().max_value - page.size.y)
	assert_int(range_max).override_failure_message(
		"the Body & Affinity page does not overflow -- this case cannot exercise scrolling").is_greater(0)
	var target: int = mini(50, range_max)
	page.scroll_vertical = target
	await await_idle_frame()
	assert_int(page.scroll_vertical).is_equal(target)   # the set took; the case is not vacuous

	var fire_box: CheckBox = null
	for child in _editor.unit_editor_container.find_children("*", "CheckBox", true, false):
		if (child as CheckBox).text == "FIRE":
			fire_box = child as CheckBox
	assert_object(fire_box).is_not_null()
	fire_box.button_pressed = true   # repaints the whole panel
	await await_idle_frame()
	await await_idle_frame()

	var new_page := _subtabs().get_tab_control(2) as ScrollContainer
	assert_int(new_page.scroll_vertical).is_equal(target)

func test_the_active_subtab_survives_a_repaint() -> void:
	var unit := _spawn(Vector2i(1, 0))
	_editor.edit_unit(unit)
	var tabs := _subtabs()
	tabs.current_tab = 2

	# An affinity toggle repaints the whole panel -- the classic yank-back-to-tab-0 trigger.
	var fire_box: CheckBox = null
	for child in _editor.unit_editor_container.find_children("*", "CheckBox", true, false):
		if (child as CheckBox).text == "FIRE":
			fire_box = child as CheckBox
	assert_object(fire_box).is_not_null()
	fire_box.button_pressed = true

	assert_int(_subtabs().current_tab).is_equal(2)
