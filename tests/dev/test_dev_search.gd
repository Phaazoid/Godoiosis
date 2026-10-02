# The dev-tools search box (#1184). Three kinds of case.
#
# COVERAGE asks the index about things it does not itself decide: every LEAVES leaf, every sub-tab
# the knob panels built, every section GameTool draws, and every knob row a panel drew and is
# showing -- found by its TEXT, so a row the value rule misses is a red case rather than a missing
# entry nobody notices. Rows built in a .tscn and label/input pairs in a grid are asked about too,
# because the rule is structural and those are the two shapes a builder tag would never reach.
#
# The WIRE cases type into the real LineEdit and click the real row through the window's own input,
# then assert the visible consequence: the page, the tree selection, the sub-tab, the row on screen.
#
# Ranking is asked as PROPERTIES over hand-made entries, never as an order over the live window,
# which is authored content (the content razor).
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")

var _scene: Node3D
var _overlay: DevOverlay
var _box: DevSearchBox


func before_test() -> void:
	_scene = SCENE.instantiate() as Node3D
	_scene.auto_play = false   # no board needed: the pages build from tables, not from cells
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	_overlay = _scene.get_node("Main/DevOverlay") as DevOverlay
	_overlay.show()
	_box = _overlay.search_box
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_scene)
	_scene.free()


# --- Helpers ---------------------------------------------------------------------------------

func _offered(kind: DevSearch.Kind, entry_name: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in DevSearch.index(_overlay):
		if entry["kind"] == kind and entry["name"] == entry_name:
			found.append(entry)
	return found


# Every control under `root` whose own text is `text` -- what a panel drew for a label.
func _drawn_with_text(root: Node, text: String) -> Array[Control]:
	var found: Array[Control] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if (node is Label and (node as Label).text == text) \
				or (node is Button and (node as Button).text == text):
			found.append(node as Control)
	return found


# Showing on its page: nothing between it and the page is hidden, except by being on a tab that is
# not the current one -- the page's own question, asked independently of DevSearch.
func _showing_on_page(control: Control) -> bool:
	var page := _overlay.page_of(control)
	var node: Node = control
	while node != null and node != page:
		if node is Control and not (node as Control).visible and not (node.get_parent() is TabContainer):
			return false
		node = node.get_parent()
	return page != null


func _type(text: String) -> void:
	_box.grab_focus()
	for character in text:
		for pressed: bool in [true, false]:
			var key := InputEventKey.new()
			key.unicode = character.unicode_at(0)
			key.pressed = pressed
			_overlay.push_input(key)
	await await_idle_frame()


func _press(code: Key) -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = code
		key.physical_keycode = code
		key.pressed = pressed
		_overlay.push_input(key)
	await await_idle_frame()


func _click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.position = at
		button.global_position = at
		button.pressed = pressed
		_overlay.push_input(button)
	await await_idle_frame()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# The last knob row on a Game sub-tab that is not the current one -- far enough down its page that
# reaching it needs a scroll, and behind a sub-tab switch.
func _a_buried_game_row() -> Dictionary:
	var tabs: TabContainer = _overlay.game_tool._tabs
	for t in range(tabs.get_tab_count() - 1, -1, -1):
		if t == tabs.current_tab:
			continue
		var page := tabs.get_tab_control(t)
		var last: Dictionary = {}
		for entry: Dictionary in DevSearch.index(_overlay):
			if entry["kind"] == DevSearch.Kind.VALUE and page.is_ancestor_of(entry["control"]):
				last = entry
		if not last.is_empty():
			return {"entry": last, "tab": t}
	return {}


# --- Coverage --------------------------------------------------------------------------------

func test_every_leaf_is_offered_as_a_tab() -> void:
	for leaf: Dictionary in DevOverlay.LEAVES:
		var page := _overlay.get_node(leaf["page"]) as Control
		var hits := _offered(DevSearch.Kind.TAB, leaf["label"]).filter(
			func(e: Dictionary) -> bool: return e["control"] == page)
		assert_int(hits.size()).override_failure_message(
			"leaf '%s' is not offered as a tab" % leaf["label"]).is_equal(1)


func test_every_knob_sub_tab_is_offered() -> void:
	var checked := 0
	for tabs: TabContainer in [_overlay.game_tool._tabs, _overlay.moods_tool._tabs]:
		for t in tabs.get_tab_count():
			var hits := _offered(DevSearch.Kind.TAB, tabs.get_tab_title(t)).filter(
				func(e: Dictionary) -> bool: return e["control"] == tabs.get_tab_control(t))
			assert_int(hits.size()).override_failure_message(
				"sub-tab '%s' is not offered" % tabs.get_tab_title(t)).is_equal(1)
			checked += 1
	assert_int(checked).override_failure_message("no sub-tabs were built; the case is vacuous") \
		.is_greater(2)


func test_every_section_the_game_tab_draws_is_offered() -> void:
	var missing: Array[String] = []
	for group: String in GameTool.section_order():
		var drawn := _drawn_with_text(_overlay.game_tool, group).filter(_showing_on_page)
		if drawn.is_empty():
			continue   # a section the page is not showing right now is not offered, by ruling
		if _offered(DevSearch.Kind.SECTION, group).is_empty():
			missing.append(group)
	assert_array(missing).override_failure_message(
		"sections drawn but not offered:\n  %s" % "\n  ".join(missing)).is_empty()


func test_every_showing_knob_row_is_offered_by_its_label() -> void:
	var labels: Array[String] = []
	for table: Array[Dictionary] in [GameKnobs.KNOBS, GameKnobs.CLASS_KNOBS, LookKnobs.KNOBS,
			ObjectKnobs.GLOBALS, ObjectKnobs.FIELDS]:
		for knob: Dictionary in table:
			labels.append(knob["label"])
	var offered := {}
	for entry: Dictionary in DevSearch.index(_overlay):
		if entry["kind"] == DevSearch.Kind.VALUE:
			offered[entry["name"]] = true
	var missing: Array[String] = []
	var checked := 0
	for label in labels:
		var drawn := _drawn_with_text(_overlay, label).filter(_showing_on_page)
		if drawn.is_empty():
			continue   # not drawn, or drawn and hidden by its page -- neither is offered
		checked += 1
		if not offered.has(label):
			missing.append(label)
	assert_int(checked).override_failure_message(
		"only %d knob rows were found drawn; the case is close to vacuous" % checked).is_greater(400)
	assert_array(missing).override_failure_message(
		"knob rows showing but not offered:\n  %s" % "\n  ".join(missing)).is_empty()


func test_a_row_built_in_the_scene_file_is_offered() -> void:
	var sprite_row: Control = _overlay.spawn.get_node("SpriteRow")
	var label := (sprite_row.get_child(0) as Label).text
	var hits := _offered(DevSearch.Kind.VALUE, label).filter(
		func(e: Dictionary) -> bool: return e["control"] == sprite_row)
	assert_int(hits.size()).override_failure_message(
		"Spawn's .tscn-authored '%s' row is not offered" % label).is_equal(1)


func test_every_label_input_pair_in_a_grid_is_offered() -> void:
	var grid: GridContainer = _overlay.spawn.get_node("%StatInput")
	var cells := grid.get_children()
	var checked := 0
	for i in cells.size() - 1:
		if cells[i] is Label and (cells[i + 1] is Range or cells[i + 1] is LineEdit):
			var label := (cells[i] as Label).text.strip_edges().trim_suffix(":").strip_edges()
			var hits := _offered(DevSearch.Kind.VALUE, label).filter(
				func(e: Dictionary) -> bool: return e["control"] == cells[i])
			assert_int(hits.size()).override_failure_message(
				"stat '%s' in Spawn's grid is not offered" % label).is_equal(1)
			checked += 1
	assert_int(checked).override_failure_message("Spawn's stat grid held no pairs; vacuous") \
		.is_greater(grid.columns / 2)


func test_a_row_hidden_on_its_page_is_not_offered() -> void:
	var hidden: Array[Node] = []
	for filtered: Dictionary in _overlay.game_tool._filtered:
		for node: Node in filtered["controls"]:
			if node is Control and not (node as Control).visible:
				hidden.append(node)
	assert_int(hidden.size()).override_failure_message(
		"the Playback filter hid no rows; this case has nothing to ask").is_greater(0)
	for entry: Dictionary in DevSearch.index(_overlay):
		var control: Control = entry["control"]
		for node in hidden:
			assert_bool(control == node or node.is_ancestor_of(control)).override_failure_message(
				"'%s' is offered from a row the Playback filter hides" % entry["name"]).is_false()


func test_a_value_names_the_section_above_it() -> void:
	var checked := 0
	for knob: Dictionary in GameKnobs.KNOBS:
		var hits := _offered(DevSearch.Kind.VALUE, knob["label"])
		if hits.size() != 1:
			continue   # absent (hidden) or shared by two rows -- ask an unambiguous one
		assert_str(hits[0]["where"]).override_failure_message(
			"'%s' does not name its section '%s'" % [knob["label"], knob["group"]]) \
			.ends_with(" › " + String(knob["group"]))
		checked += 1
	assert_int(checked).override_failure_message("no unambiguous Game row to ask; vacuous") \
		.is_greater(20)


# --- Ranking ---------------------------------------------------------------------------------

func _hand_entry(kind: DevSearch.Kind, entry_name: String, where := "Page") -> Dictionary:
	return {"kind": kind, "name": entry_name, "where": where, "control": null}


func test_a_name_that_starts_with_the_query_outranks_one_that_merely_contains_it() -> void:
	var inside := _hand_entry(DevSearch.Kind.VALUE, "Line glow")
	var start := _hand_entry(DevSearch.Kind.VALUE, "Glow width")
	var ranked := DevSearch.rank([inside, start], "glow")
	assert_str(ranked[0]["name"]).is_equal("Glow width")


func test_a_match_on_the_location_alone_comes_after_every_name_match() -> void:
	var by_place := _hand_entry(DevSearch.Kind.TAB, "Alpha", "Game › Water")
	var by_name := _hand_entry(DevSearch.Kind.VALUE, "Deep water tint")
	var ranked := DevSearch.rank([by_place, by_name], "water")
	assert_str(ranked[0]["name"]).is_equal("Deep water tint")
	assert_int(ranked.size()).is_equal(2)


func test_every_word_must_match_somewhere() -> void:
	var foam := _hand_entry(DevSearch.Kind.VALUE, "Foam width", "Game › Water › Water (deep)")
	assert_int(DevSearch.rank([foam], "foam deep").size()).is_equal(1)
	assert_int(DevSearch.rank([foam], "foam shallow").size()).is_equal(0)


func test_color_finds_a_label_spelled_colour() -> void:
	var foam := _hand_entry(DevSearch.Kind.VALUE, "Foam colour")
	assert_int(DevSearch.rank([foam], "color").size()).is_equal(1)


# --- The wire --------------------------------------------------------------------------------

func test_typing_then_clicking_a_result_brings_its_row_into_view() -> void:
	var target := _a_buried_game_row()
	assert_bool(target.is_empty()).override_failure_message("no Game row behind another sub-tab") \
		.is_false()
	var entry: Dictionary = target["entry"]
	var row: Control = entry["control"]
	_overlay.show_leaf(_overlay.spawn)
	await _type(entry["name"])
	assert_bool(_box.list_showing()).override_failure_message("typing showed no list").is_true()
	var at := _box.results().find(entry)
	assert_bool(at >= 0 and at < DevSearchBox.MAX_ROWS).override_failure_message(
		"'%s' is not among the rows shown for its own name" % entry["name"]).is_true()
	await _click(_box.row_control(at))
	await _frames(3)
	assert_bool(_overlay.showing(_overlay.game_tool)).override_failure_message(
		"the Game page is not showing").is_true()
	assert_str(_overlay.current_tab_title()).is_equal("Project / Game")
	var tabs: TabContainer = _overlay.game_tool._tabs
	assert_int(tabs.current_tab).override_failure_message("the row's sub-tab is not current") \
		.is_equal(target["tab"])
	var scroll := tabs.get_tab_control(tabs.current_tab) as ScrollContainer
	var seen := scroll.get_global_rect()
	var spot := row.get_global_rect()
	assert_bool(spot.position.y >= seen.position.y - 1.0 and spot.end.y <= seen.end.y + 1.0) \
		.override_failure_message("the row %s is outside the page's view %s" % [spot, seen]).is_true()
	assert_bool(_box.has_focus()).override_failure_message(
		"the box kept focus, which would leave the dev keys dead").is_false()
	assert_bool(_box.list_showing()).is_false()


func test_choosing_a_value_flashes_its_row() -> void:
	var target := _a_buried_game_row()
	var entry: Dictionary = target["entry"]
	var row: Control = entry["control"]
	var resting := row.modulate
	await _type(entry["name"])
	await _click(_box.row_control(_box.results().find(entry)))
	await _frames(2)
	assert_bool(row.modulate != resting).override_failure_message("the row did not flash").is_true()


func test_enter_takes_the_highlighted_result() -> void:
	await _type("squad")
	assert_int(_box.results().size()).override_failure_message("'squad' found fewer than two") \
		.is_greater(1)
	var second: Dictionary = _box.results()[1]
	await _press(KEY_DOWN)
	await _press(KEY_ENTER)
	await _frames(2)
	assert_object(_overlay.page_of(second["control"])).is_not_null()
	assert_bool(_overlay.showing(_overlay.page_of(second["control"]))).override_failure_message(
		"Enter did not take the highlighted result ('%s')" % second["name"]).is_true()


func test_escape_clears_the_box() -> void:
	await _type("squad")
	await _press(KEY_ESCAPE)
	assert_str(_box.text).is_empty()
	assert_bool(_box.list_showing()).is_false()


func test_a_click_outside_closes_the_list() -> void:
	await _type("squad")
	await _click(_overlay.tool_tree)
	assert_bool(_box.list_showing()).is_false()


# Typing a query must not fire a dev key -- V cycles the 3D selector depth from either window.
# The second half presses V with the box let go, so the first half is not passing vacuously.
func test_typing_in_the_box_fires_no_dev_key() -> void:
	var overlays := LookKnobs.target_of(_overlay.host_3d, GameKnobs.SELECTOR_DEPTH) as BoardOverlays
	assert_object(overlays).override_failure_message("no 3D selector to watch").is_not_null()
	var before := overlays.selector_depth
	_box.grab_focus()
	var typed := InputEventKey.new()
	typed.keycode = KEY_V
	typed.physical_keycode = KEY_V
	typed.unicode = "v".unicode_at(0)
	typed.pressed = true
	_overlay.push_input(typed)
	await await_idle_frame()
	assert_int(overlays.selector_depth).override_failure_message("typing 'v' fired the dev key") \
		.is_equal(before)
	_box.release_focus()
	_overlay.push_input(typed)
	await await_idle_frame()
	assert_int(overlays.selector_depth).override_failure_message(
		"V with the box let go did nothing either; the first half proves nothing").is_not_equal(before)
