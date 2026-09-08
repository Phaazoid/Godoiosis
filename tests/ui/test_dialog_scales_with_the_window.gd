# Does the DIALOG BOX grow with the window (#687)?
#
# #659 gave the battle UI a fixed 1280x720 design space -- GameSurface puts a size_2d_override on
# GameView, so every Control mounted inside that SubViewport lays out in design units and covers the
# same fraction of the screen at any resolution. Dialogic's layout was the one player-facing surface
# outside it: create_layout defaults its parent to dialogic.get_parent(), the TREE ROOT, so on a 4K
# display the prolog intro drew at design-resolution PIXELS while every panel around it scaled.
# ScenarioDirector._start now hands over game.get_viewport() -- GameView in the real tree.
#
# THE MEASUREMENT IS THE LAYOUT SPACE, NOT A SHARE OF THE SCREEN, and that is the whole reason these
# cases are shaped this way: every layer of a Dialogic layout is a full-rect Control, so its share of
# the screen is 1.0 under EITHER parent and cannot tell them apart. Its SIZE can -- at a 2560x1440
# window the design space is 1280x720 and the physical window is not.
#
# The other half of the seam -- size_2d_override WITHOUT size_2d_override_stretch lays the UI out in
# the design space and then draws it 1:1 in a corner, which every design-space assertion is blind to
# -- is already pinned by test_ui_scales_with_the_window's share-of-screen case. The dialog inherits
# it from the same viewport rather than owning a second copy of the question.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

const NATIVE := Vector2(1280.0, 720.0)   # GameContainer.custom_minimum_size, the design resolution

var _main: Node
var _container: SubViewportContainer
var _view: SubViewport
var _game: Node2D


func before_test() -> void:
	PlayerSettings.reset_for_test()   # is_on falls through to DISK otherwise (the #350 gotcha)
	# _fire CONSUMES a beat without playing it when this is off (the #400 switch), which would leave
	# every case below asserting about a layout that was never built.
	PlayerSettings.set_on(PlayerSettings.Setting.SHOW_DIALOG, true)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	_container = _main.get_node("GameContainer") as SubViewportContainer
	_view = _main.get_node("GameContainer/GameView") as SubViewport
	_game = _main.get_node("GameContainer/GameView/Game") as Node2D
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	get_tree().root.remove_child(_main)
	_main.free()
	await await_idle_frame()


# --- Helpers ---------------------------------------------------------------------------

# The window resizing IS the container resizing: it is full-rect, so this is how a resize reaches
# the game. Asserted, without which a headless quirk holding every case at the design size would
# pass the suite vacuously. Same shape as test_ui_scales_with_the_window's own helper.
func _resize_to(width: float, height: float) -> void:
	_container.size = Vector2(width, height)
	await await_idle_frame()
	await await_idle_frame()
	assert_vector(_container.size) \
		.override_failure_message("fixture assumption broke: the container refused %.0fx%.0f (it is %.0fx%.0f)"
			% [width, height, _container.size.x, _container.size.y]) \
		.is_equal(Vector2(width, height))


# Talk through the REAL wire -- authored beats on the content store the director reads live, then
# the #220 fresh-start door -- rather than calling Dialogic directly, because the thing under test
# is which parent ScenarioDirector hands over. `count` beats all trigger on MISSION_START, so the
# first one PLAYS and the rest QUEUE, which is how the pending path gets exercised below.
func _talk(count: int) -> void:
	var beats: Array[DialogBeat] = []
	for i in count:
		var beat := DialogBeat.new()
		beat.trigger = DialogBeat.Trigger.MISSION_START
		beat.timeline = DialogicTimeline.new()
		beat.timeline.from_text("The dialog box should grow with the window. (%d)" % i)
		beats.append(beat)
	_game.scenario_manager.current_dialog_beats = beats
	_game.scenario_director.mission_started()
	# timeline_started, never a frame count: start() defers to the layout's `ready`, so this signal
	# is also the guarantee that the layout is in the tree by the time anything below reads it.
	await Dialogic.timeline_started


# The full-rect layer that stands in for "the dialog box", read off Dialogic's own API rather than
# by node name so an addon rename cannot silently make this suite measure nothing.
func _layout_layer() -> Control:
	var layout: DialogicLayoutBase = Dialogic.Styles.get_layout_node()
	assert_object(layout) \
		.override_failure_message("no Dialogic layout is live -- the beat never played") \
		.is_not_null()
	var layers: Array = layout.get_layers()
	assert_int(layers.size()) \
		.override_failure_message("the layout has no layers to measure") \
		.is_greater(0)
	return layers[0] as Control


# --- Cases -----------------------------------------------------------------------------

# THE WIRE. Dialogic's default parent is the tree root, which is a different VIEWPORT -- and the
# viewport is what carries the content scale, so this identity is the whole mechanism.
func test_the_dialog_layout_mounts_inside_the_game_viewport() -> void:
	await _talk(1)
	var layout: DialogicLayoutBase = Dialogic.Styles.get_layout_node()
	assert_object(layout.get_viewport()) \
		.override_failure_message("the dialog layout mounted in %s, not GameView -- it is outside "
			% layout.get_viewport()
			+ "the design space and draws at physical pixels") \
		.is_same(_view)


# THE REPORTED DEFECT, measured. A layout on the tree root lays out against the PHYSICAL window, so
# on a 2560x1440 screen its layer is 2560x1440 and every authored size inside it -- the textbox
# height, the font -- is that same fraction smaller. Inside GameView it is 1280x720 and the content
# scale draws it at 2x.
func test_the_dialog_lays_out_in_the_design_space() -> void:
	await _resize_to(2560.0, 1440.0)
	await _talk(1)
	assert_vector(_layout_layer().size) \
		.override_failure_message("at a 2560x1440 window the dialog lays out in %s, not the 1280x720 "
			% _layout_layer().size
			+ "design space -- it is drawing physical pixels while the panels around it scale") \
		.is_equal(NATIVE)


# The SECOND timeline, and the case that catches redirecting only _fire. end_timeline FREES the
# layout (dialogic/layout/end_behaviour 0), so the pending pop in _on_timeline_ended builds a fresh
# one -- and a parent handed over at only one of the two call sites sends this one back to the root.
func test_the_SECOND_timeline_mounts_inside_the_viewport_too() -> void:
	await _resize_to(2560.0, 1440.0)
	await _talk(2)   # the first plays, the second queues behind it
	Dialogic.end_timeline(true)
	await Dialogic.timeline_started   # the pending pop's own start
	assert_vector(_layout_layer().size) \
		.override_failure_message("the queued beat's layout lays out in %s, not the design space -- "
			% _layout_layer().size
			+ "the second Dialogic.start call site still hands over no parent") \
		.is_equal(NATIVE)
