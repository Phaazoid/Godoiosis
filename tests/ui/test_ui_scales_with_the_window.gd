# Does the battle UI GROW with the window (#659)?
#
# The reported bug, from two 4K bug reports: the board fills the screen and the UI does not. Every
# Control lives under GameView, stretch is ON so that viewport's size tracks the window, and the
# panels were therefore laid out in physical pixels -- 300px of inspect panel is 23% of a 720p
# screen and 8% of a 4K one. GameSurface answers it by giving GameView a 2D content scale, so the
# UI lays out in a fixed DESIGN space that is stretched to the window.
#
# Two of these cases are shaped the way they are because the obvious shape is blind.
#
# "changes aspect" in the second-resize case is the whole case. For any 16:9 window the design
# space is 1280x720 whatever the factor is, so a handler reading a STALE size still lands on the
# right answer and a 16:9 -> 16:9 resize pair cannot tell the two apart. Only a non-16:9 window
# makes the design space depend on which size was read.
#
# And the share-of-SCREEN case measures through get_screen_transform() rather than comparing
# authored sizes, because size_2d_override without size_2d_override_stretch lays the UI out in the
# design space and then draws it at 1:1 in the corner -- every assertion about the design space
# passes on that build, and only a physical measurement (or a real click) can see it.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

const NATIVE := Vector2(1280.0, 720.0)   # GameContainer.custom_minimum_size, the design resolution

var _main: Node
var _container: SubViewportContainer
var _view: SubViewport


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	_container = _main.get_node("GameContainer") as SubViewportContainer
	_view = _main.get_node("GameContainer/GameView") as SubViewport
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()
	await await_idle_frame()


# Drive a window resize the way one actually reaches the game: the container is full-rect, so the
# window resizing IS the container resizing. Asserts the container took it -- without that a
# headless quirk could hold every case at the design size and pass the suite vacuously.
func _resize_to(width: float, height: float) -> void:
	_container.size = Vector2(width, height)
	await await_idle_frame()
	await await_idle_frame()
	assert_vector(_container.size) \
		.override_failure_message("fixture assumption broke: the container refused %.0fx%.0f (it is %.0fx%.0f)"
			% [width, height, _container.size.x, _container.size.y]) \
		.is_equal(Vector2(width, height))


func _design_space() -> Vector2:
	return _view.get_visible_rect().size


func test_the_ui_lays_out_in_the_design_space_at_any_window_size() -> void:
	await _resize_to(2560.0, 1440.0)
	assert_vector(_design_space()) \
		.override_failure_message("at 2560x1440 the UI lays out in %s, not the 1280x720 design space"
			% _design_space()) \
		.is_equal(NATIVE)

	await _resize_to(1920.0, 1080.0)
	assert_vector(_design_space()).is_equal(NATIVE)


# EXPAND, not fit, asked as a PROPERTY rather than by re-deriving the formula: the design space
# never drops below the native resolution on either axis, so the extra room a non-16:9 window has
# arrives as extra design space and no panel is ever crowded off an edge.
#
# The two directions are separate cases because they fail to different mistakes, and a wide window
# alone is BLIND to one of them -- found by a surviving mutant. For anything WIDER than 16:9 the
# height ratio already IS the smaller of the two, so a height-only factor agrees with minf() to the
# pixel here and only a TALLER-than-16:9 window can tell them apart.
func test_a_wide_window_gets_more_design_width_not_a_squeeze() -> void:
	await _resize_to(2560.0, 1080.0)
	assert_float(_design_space().y) \
		.override_failure_message("a 21:9 window should be bounded by its height, but the design space is %s"
			% _design_space()) \
		.is_equal_approx(NATIVE.y, 0.5)
	assert_float(_design_space().x) \
		.override_failure_message("a 21:9 window got %.0f of design width -- no wider than 16:9, so the UI was squeezed"
			% _design_space().x) \
		.is_greater(NATIVE.x)


# The mirror image, and the case a height-only factor dies on: it would scale by 1440/720 = 2 and
# hand the UI a 640-wide design space -- HALF the native width, with the panels overlapping in the
# middle of a window that is in no way short of room.
func test_a_tall_window_is_bounded_by_its_width_not_its_height() -> void:
	await _resize_to(1280.0, 1440.0)
	assert_float(_design_space().x) \
		.override_failure_message("a tall window got %.0f of design width against a native 1280 -- "
			% _design_space().x
			+ "the factor is following the height, so the UI is being squeezed inward") \
		.is_equal_approx(NATIVE.x, 0.5)
	assert_float(_design_space().y).is_greater(NATIVE.y)


# THE ISSUE'S OWN PROPERTY: "a 4K player should get the same relative panel footprint the dev sees
# at design resolution". Measured as a share of the SCREEN, through the transform a mouse click
# goes through, so it is the panel's real footprint rather than its authored width. The ratio is
# also the unit: no pixel value is pinned, so re-authoring the button's size cannot red this.
#
# EndTurnButton, not the inspect panel: that one ships visible = false, and a hidden Control's
# layout is not a thing to lean on.
func test_a_panel_keeps_its_share_of_the_screen() -> void:
	var button: Button = _main.get_node("GameContainer/GameView/Game/UILayer/EndTurnButton/Button")

	await _resize_to(1280.0, 720.0)
	var at_design := _screen_share(button)

	await _resize_to(2560.0, 1440.0)
	var at_4k := _screen_share(button)

	assert_float(at_4k) \
		.override_failure_message(
			"the End Turn button covers %.4f of the screen at 1280x720 but %.4f at 2560x1440 -- "
			% [at_design, at_4k]
			+ "the UI is not growing with the window") \
		.is_equal_approx(at_design, 0.001)


# How wide the control really is ON SCREEN, as a fraction of the window.
#
# NOT get_screen_transform(): MEASURED on the real scene, that returns a Control's bare global
# transform when the Control sits under a CanvasLayer -- the viewport's content scale is simply not
# in it, so it reports the design-space width and this case would pass on a build that never
# stretched anything. get_final_transform() composed with the canvas-aware global transform is the
# chain a mouse click traverses on its way in (Viewport.push_input inverts exactly this), which is
# what makes it the right answer to "how big is this on screen".
func _screen_share(control: Control) -> float:
	var to_screen: Transform2D = _view.get_final_transform() * control.get_global_transform_with_canvas()
	return (control.size.x * to_screen.get_scale().x) / _container.size.x


# The one-resize-behind bug, and the reason GameSurface reads its OWN size rather than the
# viewport's: SubViewportContainer resizes its viewport AFTER emitting `resized`, so a handler
# asking the viewport is always answering about the previous window. The second resize CHANGES
# ASPECT because a 16:9 pair cannot expose it -- both readings give 1280x720.
func test_the_scale_follows_a_SECOND_resize_that_changes_aspect() -> void:
	await _resize_to(1600.0, 900.0)
	assert_vector(_design_space()).is_equal(NATIVE)   # 16:9, so both readings agree here

	await _resize_to(2560.0, 1080.0)
	var expected := Vector2(roundi(2560.0 / 1.5), 720.0)
	assert_vector(_design_space()) \
		.override_failure_message(
			"after a second resize the design space is %s, expected %s -- a stale read of the "
			% [_design_space(), expected]
			+ "viewport's own size would give 1280x720 here") \
		.is_equal(expected)


# Nothing ever shrinks. custom_minimum_size floors the container at the design resolution, so a
# window smaller than 1280x720 clips exactly as it always has instead of scaling the UI down into
# illegibility -- which is what makes the factor >= 1 everywhere and this change purely additive.
func test_the_design_space_never_shrinks_below_the_native_resolution() -> void:
	_container.size = Vector2(800.0, 600.0)
	await await_idle_frame()
	await await_idle_frame()
	assert_vector(_container.size) \
		.override_failure_message("the container went below its own minimum: %s" % _container.size) \
		.is_equal(NATIVE)
	assert_vector(_design_space()).is_equal(NATIVE)
