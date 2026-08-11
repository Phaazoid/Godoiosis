# The action-queue panel's dock (#160), on the real scene: the panel sits against the RIGHT
# viewport edge, FOLLOWS that edge when the viewport resizes (the co-dev's Mac report — the
# shipped scene pinned it at absolute x=1000 offsets, the #132 sharp-edge class), and the
# full-rect scene root stays click-transparent — a root with mouse_filter STOP would eat every
# board click while every content-level suite stayed green (#131's lesson shape).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

# The panel's authored gap to the right edge (offset_right = -7 in the scene).
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
	var container: SubViewportContainer = _main.get_node("GameContainer")
	var viewport: SubViewport = _main.get_node("GameContainer/GameView")
	container.size = Vector2(1600, 900)
	await await_idle_frame()
	await await_idle_frame()

	# Fixture sanity: if stretch stopped propagating, this case would otherwise pass vacuously.
	assert_int(viewport.size.x) \
		.override_failure_message("fixture assumption broke: resizing GameContainer did not resize GameView (still %d wide)" % viewport.size.x) \
		.is_equal(1600)
	assert_float(_panel_right_edge()) \
		.override_failure_message("the queue panel did not follow the right edge: panel ends at %.0f of %d" % [_panel_right_edge(), viewport.size.x]) \
		.is_equal_approx(1600.0 - EDGE_MARGIN, 0.5)


func test_the_full_rect_root_never_eats_board_clicks() -> void:
	# The one subtle consequence of the fix: the root became full-rect so its child can anchor to
	# the viewport edge, and a full-rect Control with the default STOP filter would swallow every
	# click meant for the board underneath — silently, with all content suites green.
	assert_int(game.squad_action_queue_control.mouse_filter) \
		.override_failure_message("the queue panel's full-rect root is not click-transparent — every board click under it is being eaten") \
		.is_equal(Control.MOUSE_FILTER_IGNORE)
