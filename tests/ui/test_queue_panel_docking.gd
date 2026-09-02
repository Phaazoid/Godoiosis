# The action-queue panel's dock (#160), on the real scene: the panel sits against the RIGHT
# viewport edge, FOLLOWS that edge when the viewport resizes (the co-dev's Mac report — the
# shipped scene pinned it at absolute x=1000 offsets, the #132 sharp-edge class), and the
# full-rect scene root stays click-transparent — a root with mouse_filter STOP would eat every
# board click while every content-level suite stayed green (#131's lesson shape).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

# The panel's authored gap to the right edge (offset_right = -7 in the scene). A DESIGN-SPACE
# number since #659 — on screen it is this times the window's scale factor.
const EDGE_MARGIN := 7.0

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _panel_right_edge() -> float:
	var panel: Panel = game.squad_action_queue_control.get_node("BackgroundPanel")
	return panel.get_global_rect().end.x


func test_the_panel_docks_to_the_right_edge() -> void:
	var viewport: SubViewport = _main.get_node("GameContainer/GameView")
	assert_float(_panel_right_edge()).is_equal_approx(viewport.size.x - EDGE_MARGIN, 0.5)


func test_the_dock_follows_a_viewport_resize() -> void:
	# The reported bug: resize the window bigger and the panel stays put. A window resize reaches
	# the game as GameContainer resizing (SubViewportContainer stretch is ON, which is what sizes
	# GameView) — drive that directly and the dock must follow.
	#
	# THE EDGE IS A DESIGN-SPACE NUMBER SINCE #659, not a physical one: GameView carries a 2D
	# content scale now, so Controls lay out in a fixed 1280x720 space that is stretched to the
	# window. get_visible_rect() is that space; `size` is still the physical window. The RULE this
	# case pins is unchanged — the dock follows the edge — only the unit it is measured in moved,
	# so do not "fix" this back to viewport.size.
	var container: SubViewportContainer = _main.get_node("GameContainer")
	var viewport: SubViewport = _main.get_node("GameContainer/GameView")
	container.size = Vector2(1600, 900)
	await await_idle_frame()
	await await_idle_frame()

	# Fixture sanity: if stretch stopped propagating, this case would otherwise pass vacuously.
	assert_int(viewport.size.x) \
		.override_failure_message("fixture assumption broke: resizing GameContainer did not resize GameView (still %d wide)" % viewport.size.x) \
		.is_equal(1600)
	var design_width: float = viewport.get_visible_rect().size.x
	assert_float(_panel_right_edge()) \
		.override_failure_message("the queue panel did not follow the right edge: panel ends at %.0f of %.0f"
			% [_panel_right_edge(), design_width]) \
		.is_equal_approx(design_width - EDGE_MARGIN, 0.5)

	# ...and the same edge in PHYSICAL pixels, which is the half a player actually sees: the gap
	# scales with everything else, so the panel keeps its authored 7px margin rather than a margin
	# that thins to a hairline as the window grows.
	var panel: Panel = game.squad_action_queue_control.get_node("BackgroundPanel")
	# get_final_transform() composed with the canvas-aware global transform, NOT get_screen_transform():
	# that one drops the viewport content scale for a Control under a CanvasLayer (measured). This is
	# the chain a click traverses, so it is what "on screen" means here.
	var to_screen: Transform2D = viewport.get_final_transform() * panel.get_global_transform_with_canvas()
	var physical_end: float = to_screen.get_origin().x + panel.size.x * to_screen.get_scale().x
	var expected_end: float = 1600.0 - EDGE_MARGIN * (900.0 / 720.0)
	assert_float(physical_end) \
		.override_failure_message("on screen the panel ends at %.0f of 1600, expected %.0f"
			% [physical_end, expected_end]) \
		.is_equal_approx(expected_end, 1.0)


func test_the_full_rect_root_never_eats_board_clicks() -> void:
	# The one subtle consequence of the fix: the root became full-rect so its child can anchor to
	# the viewport edge, and a full-rect Control with the default STOP filter would swallow every
	# click meant for the board underneath — silently, with all content suites green.
	assert_int(game.squad_action_queue_control.mouse_filter) \
		.override_failure_message("the queue panel's full-rect root is not click-transparent — every board click under it is being eaten") \
		.is_equal(Control.MOUSE_FILTER_IGNORE)
