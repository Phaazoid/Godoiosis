# Does the dev-tools window actually FIT what it opens (#403)?
#
# The bug this pins had two authorities for one question. Scenes/DevOverlay.tscn declared the
# window's size and Scenes/Main.tscn OVERRODE it on the instance -- so #382's widening went into
# the file that loses, and the running window stayed 900 wide while the Moods and Game colour rows
# needed 849 of the 678 the tree left them. The panels ran off the right edge, and the value
# everyone edited had no effect on anything.
#
# Three of these are laws rather than examples.
#
# "opens at the size its own scene declares" is the seam law: two instantiation paths -- the scene
# alone, and the scene as Main.tscn instances it -- must agree. Any second authority makes them
# disagree, whichever file it lives in.
#
# "every page fits" is the regression itself, and it is deliberately measured on the page's
# CONTENT rather than on its ScrollContainer. Since #403 the knob panels scroll horizontally, so
# the container's own minimum collapses to nothing and an assertion pointed there would pass over
# any width at all -- a check that cannot fire. The widest ROW is what a dev has to see at once,
# so that is what is compared against the width the window leaves the page.
#
# "the tree keeps its width" pins the thing the issue FEARED and measurement disproved: an
# HSplitContainer does not squeeze its first child to make room for its second, so a page wider
# than the window spills off the right edge and never displaces the tree. Pinned so a later change
# to the split cannot quietly make the original report true.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const OVERLAY_SCENE := "res://Scenes/DevOverlay.tscn"

var _scene: Node3D
var _overlay: DevOverlay


func before_test() -> void:
	_scene = (load(SCENE_PATH) as PackedScene).instantiate() as Node3D
	_scene.auto_play = false   # no board needed: every page builds from tables, not from cells
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	_overlay = _scene.get_node("Main/DevOverlay") as DevOverlay


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


# --- Helpers ---------------------------------------------------------------------------

# The widest thing on a page that has to be seen at once. A plain max over every descendant, so it
# reads the same whether a panel scrolls horizontally or not: a ScrollContainer set to scroll
# reports almost no minimum of its own, but the row VBox inside it still reports the real width.
func _content_width(node: Node) -> float:
	var widest := 0.0
	var control := node as Control
	if control != null:
		widest = control.get_combined_minimum_size().x
	for child in node.get_children():
		widest = maxf(widest, _content_width(child))
	return widest


# What the window leaves a page: its own width, less the chrome that is never a page's to use.
func _width_left_for_a_page() -> float:
	var body := _overlay.get_node("Panel/MarginContainer/VBoxContainer/Body") as HSplitContainer
	var margins := _overlay.get_node("Panel/MarginContainer") as MarginContainer
	return float(_overlay.size.x) \
		- margins.get_theme_constant("margin_left") - margins.get_theme_constant("margin_right") \
		- _overlay.tool_tree.get_combined_minimum_size().x \
		- body.get_theme_constant("separation")


# --- Laws ------------------------------------------------------------------------------

func test_the_window_opens_at_the_size_its_own_scene_declares() -> void:
	var alone := (load(OVERLAY_SCENE) as PackedScene).instantiate() as Window
	var declared := alone.size
	alone.free()
	assert_vector(Vector2(_overlay.size)).override_failure_message(
		"The running dev window is %s but Scenes/DevOverlay.tscn declares %s -- something between "
		% [_overlay.size, declared]
		+ "them overrides it, so editing the declared size does nothing (#403).") \
		.is_equal(Vector2(declared))


func test_every_page_fits_the_width_the_window_leaves_it() -> void:
	var available := _width_left_for_a_page()
	assert_float(available).override_failure_message(
		"the window leaves a page no room at all -- the chrome maths is wrong").is_greater(0.0)
	for leaf: Dictionary in DevOverlay.LEAVES:
		var page := _overlay.get_node(leaf["page"]) as Control
		_overlay.show_leaf(page)
		await await_idle_frame()
		var needed := _content_width(page)
		assert_float(needed).override_failure_message(
			"The '%s / %s' page needs %.0fpx but the window leaves it %.0f -- it runs off the "
			% [leaf["scope"], leaf["label"], needed, available]
			+ "right edge at the default size. Widen Scenes/DevOverlay.tscn, or narrow the row "
			+ "(a DevWidgets.add_color row is the widest thing the knob panels build).") \
			.is_less_equal(available)


func test_the_tree_keeps_its_width_on_every_page() -> void:
	var declared := _overlay.tool_tree.get_combined_minimum_size().x
	for leaf: Dictionary in DevOverlay.LEAVES:
		var page := _overlay.get_node(leaf["page"]) as Control
		_overlay.show_leaf(page)
		await await_idle_frame()
		await await_idle_frame()
		assert_float(_overlay.tool_tree.size.x).override_failure_message(
			"Opening '%s' squeezed the tool tree to %.0fpx of its %.0f -- the split is now taking "
			% [leaf["label"], _overlay.tool_tree.size.x, declared]
			+ "the tree's room to fit the page, which is what #403 was reported as.") \
			.is_greater_equal(declared)
		assert_float(_overlay.tool_tree.position.x).override_failure_message(
			"Opening '%s' moved the tool tree off the left of the window" % leaf["label"]) \
			.is_equal(0.0)


# The clamp is a pure function so it can be asked about screens this machine does not have. A
# window WIDER than the usable rect is the case that bites: the upper bound drops below the lower.
func test_a_window_wider_than_the_screen_is_not_parked_off_the_left_edge() -> void:
	var usable := Rect2i(0, 0, 1152, 864)
	var placed := DevOverlay.clamp_to_screen(Vector2i(1296, 0), Vector2i(1200, 720), usable)
	assert_int(placed.x).override_failure_message(
		"a window wider than the screen was placed at x=%d -- the tool tree lives in its leftmost "
		% placed.x + "210px, so a negative x is the tree literally off-screen (#403)").is_equal(0)
	assert_int(placed.y).is_equal(0)
	# The ordinary case still lands beside the game rather than hard against the left edge.
	var roomy := DevOverlay.clamp_to_screen(Vector2i(1296, 0), Vector2i(1200, 720),
		Rect2i(0, 0, 2560, 1440))
	assert_int(roomy.x).is_equal(1296)
