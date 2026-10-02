# Only the mouse changes the dev-tools page (#1184, dev 2026-10-01: "sometimes, keyboard presses
# will change what page I'm on. that shouldn't happen").
#
# The cause was focus, not a dev key: a click left the scope tree holding keyboard focus, and Godot's
# Tree moves its selection on the arrow keys and on letters (allow_search) -- so C, the brush's
# turn-the-rise key, landed on Characters. A clicked sub-tab bar did the same on left/right.
#
# A HEADLESS click does not hand out focus (measured: the click selects the leaf and the focus owner
# stays null), so each case clicks to pick and then grants the focus a real click would -- through
# _focus_as_a_click_would, which asks the control's own focus_mode exactly as the viewport does. A
# FOCUS_NONE control refuses it, which is the fix: nothing that switches pages can hold the keys.
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")

var _scene: Node3D
var _overlay: DevOverlay


func before_test() -> void:
	_scene = SCENE.instantiate() as Node3D
	_scene.auto_play = false   # no board needed: the pages build from tables, not from cells
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	_overlay = _scene.get_node("Main/DevOverlay") as DevOverlay
	_overlay.show()
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_scene)
	_scene.free()


# Every key that moves a Tree or a TabBar selection, plus every letter (Tree incremental search).
func _keys() -> Array[int]:
	var keys: Array[int] = [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_HOME, KEY_END,
		KEY_PAGEUP, KEY_PAGEDOWN]
	for code in range(KEY_A, KEY_Z + 1):
		keys.append(code)
	return keys


func _press(code: int) -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = code as Key
		key.physical_keycode = code as Key
		if code >= KEY_A and code <= KEY_Z:
			key.unicode = code + 32   # lower case, what a plain press types
		key.pressed = pressed
		_overlay.push_input(key)


func _click(control: Control, local: Vector2) -> void:
	var at := control.get_global_transform() * local
	for pressed: bool in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.position = at
		button.global_position = at
		button.pressed = pressed
		_overlay.push_input(button)
	await await_idle_frame()


# What a real click leaves focused: the control, unless its focus_mode says a click cannot focus it.
func _focus_as_a_click_would(control: Control) -> void:
	if control.focus_mode != Control.FOCUS_NONE:
		control.grab_focus()


func _leaf(label: String) -> TreeItem:
	var scope_item := _overlay.tool_tree.get_root().get_first_child()
	while scope_item != null:
		var item := scope_item.get_first_child()
		while item != null:
			if item.get_text(0) == label:
				return item
			item = item.get_next()
		scope_item = scope_item.get_next()
	return null


func test_no_key_moves_the_page_after_a_tree_click() -> void:
	var tree := _overlay.tool_tree
	var item := _leaf("Tile Brush")
	await _click(tree, tree.get_item_area_rect(item).get_center())
	_focus_as_a_click_would(tree)
	assert_bool(_overlay.showing(_overlay.tile_brush)) \
		.override_failure_message("the click did not select the Tile Brush leaf").is_true()
	var moved: Array[String] = []
	for code in _keys():
		_press(code)
		await await_idle_frame()
		if not _overlay.showing(_overlay.tile_brush):
			moved.append("%s -> %s" % [OS.get_keycode_string(code), _overlay.current_tab_title()])
			_overlay.show_leaf(_overlay.tile_brush)
	assert_array(moved).override_failure_message(
		"these keys moved the page off the Tile Brush:\n  %s" % "\n  ".join(moved)).is_empty()


func test_no_key_moves_the_sub_tab_after_a_sub_tab_click() -> void:
	_overlay.show_leaf(_overlay.game_tool)
	await await_idle_frame()
	var tabs: TabContainer = _overlay.game_tool._tabs
	var bar := tabs.get_tab_bar()
	await _click(bar, bar.get_tab_rect(1).get_center())
	_focus_as_a_click_would(bar)
	assert_int(tabs.current_tab).override_failure_message("the click did not pick sub-tab 1").is_equal(1)
	var moved: Array[String] = []
	for code in _keys():
		_press(code)
		await await_idle_frame()
		if tabs.current_tab != 1 or not _overlay.showing(_overlay.game_tool):
			moved.append("%s -> sub-tab %d on '%s'" \
				% [OS.get_keycode_string(code), tabs.current_tab, _overlay.current_tab_title()])
			_overlay.show_leaf(_overlay.game_tool)
			tabs.current_tab = 1
	assert_array(moved).override_failure_message(
		"these keys moved the Game sub-tab:\n  %s" % "\n  ".join(moved)).is_empty()


# The LAW behind both cases, so a fourth sub-tabbed page cannot bring the bug back: nothing in the
# built window that switches what you are looking at can take keyboard focus. A TabContainer with
# its tabs hidden (DevTabs, AuthoringTabs) is exempt -- a bar you cannot see cannot be clicked.
# A unit is opened in the Unit Editor first, because its sub-tabs exist only once one is.
func test_nothing_that_switches_pages_can_take_the_keyboard() -> void:
	var game: Node = _overlay.game
	game.scenario_manager.load_scenario(ScenarioManager.scenario_path("missions/Prolog"))
	await await_idle_frame()
	var unit: Unit = null
	for child in game.units_root.get_children():
		if child is Unit:
			unit = child
			break
	assert_object(unit).override_failure_message("Prolog spawned no units; the case is vacuous").is_not_null()
	_overlay.unit_editor.edit_unit(unit)
	await await_idle_frame()
	var offenders: Array[String] = []
	var tab_containers := 0
	var stack: Array[Node] = [_overlay]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Tree and (node as Tree).focus_mode != Control.FOCUS_NONE:
			offenders.append("Tree %s" % _overlay.get_path_to(node))
		elif node is TabContainer and (node as TabContainer).tabs_visible:
			tab_containers += 1
			if (node as TabContainer).tab_focus_mode != Control.FOCUS_NONE:
				offenders.append("TabContainer %s" % _overlay.get_path_to(node))
	assert_int(tab_containers).override_failure_message(
		"found %d visible sub-tab bars; expected Game, Moods and the Unit Editor" % tab_containers) \
		.is_greater_equal(3)
	assert_array(offenders).override_failure_message(
		"these can hold the keys and switch the page:\n  %s" % "\n  ".join(offenders)).is_empty()
