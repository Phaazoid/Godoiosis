# THE ON-SCREEN REPORT SIGN (#1051) -- that it is built and readable, that it names the key the
# binding registry actually documents, that it is NOT a door, and that it does not sit on top of
# either neighbour in the top-right strip.
#
# "Not a door" is the rule this file exists to hold. The ticket shipped once as a clickable mark
# and the dev's correction was that a fourth way into the same card, sitting beside three nobody
# could find, taught a player nothing: the sign's whole job is to NAME the cheapest way in. A case
# asserting it eats no input is the only thing standing between that ruling and the obvious
# "while we are here, may as well make it clickable".
#
# TWO THINGS GIVE THESE CASES TEETH, and both are arrangements rather than assertions:
#   - Scenes/MissionStatusPanel.tscn authors NO text on the label, so the only thing that can put
#     words in it is _build_report_hint(). A case reading "F3" out of a label the editor already
#     filled in would pass against a panel that never ran.
#   - The sign reads its key from Controls, so this file asks Controls too. Spelling "F3" here
#     would pin the registry's current answer rather than the wire between them -- and the wire is
#     the point, since tests/law/test_controls_coverage.gd already walks that registry against the
#     live Input Map in both directions.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	remove_child(_main)
	_main.free()
	await await_idle_frame()


func _sign() -> Label:
	return game.mission_status_panel.get_node("ReportHint")


func _rect_of(control: Control) -> Rect2:
	return Rect2(control.global_position, control.size)


func test_the_sign_is_built_and_readable() -> void:
	var sign_label := _sign()
	assert_object(sign_label).override_failure_message(
		"the report sign is not in the built tree").is_not_null()
	assert_bool(sign_label.visible).is_true()
	assert_str(sign_label.text).override_failure_message(
		"the report sign is blank -- it is in the tree and says nothing").is_not_empty()

	# ON SCREEN, and this is not padding: the sign is placed by stepping LEFT off the version
	# stamp, so every other case here passes just as happily with it walked off the left edge. The
	# design space is the frame of reference (#659), never the window.
	var design: Vector2 = game.get_viewport_rect().size
	var rect := _rect_of(sign_label)
	assert_bool(Rect2(Vector2.ZERO, design).encloses(rect)).override_failure_message(
		"the report sign %s is not fully inside the %s design space" % [rect, design]).is_true()


func test_the_sign_names_the_key_the_registry_documents() -> void:
	# THE WIRE (#103's shape): both ends can be perfectly correct and unconnected. Falsified by
	# spelling the key into MissionStatusPanel.REPORT_HINT and changing the registry's row -- the
	# sign then names a key the game does not have, which is the whole failure this guards.
	var key: String = Controls.key_for_action(MissionStatusPanel.REPORT_ACTION)
	assert_str(key).override_failure_message(
		"the registry documents no key for %s -- the sign has nothing to name"
		% MissionStatusPanel.REPORT_ACTION).is_not_empty()
	assert_str(_sign().text).override_failure_message(
		"the report sign reads '%s' and the registry says the key is '%s'" % [_sign().text, key]
		).contains(key)


func test_the_sign_is_not_a_door() -> void:
	# THE DEV'S RULING, 2026-09-21, after the clickable version shipped: "I didn't want an actual
	# report button on the screen. I wanted a notice... Now there are 3 paths to the report, and
	# the player has no way of knowing the easiest one."
	#
	# So: not a button, and no mouse_filter that would swallow a board click passing under it.
	# The node is read UNTYPED here on purpose, and the reason is worth keeping: typed as a Label,
	# GDScript refuses to COMPILE the check -- "Expression is of type Label so it can't be of type
	# BaseButton". The check has to be made where the type is still open, which is also the only
	# place the mistake could be made.
	#
	# MEASURED 2026-09-21: dropping `mouse_filter = 2` from the .tscn leaves all seven cases green,
	# because Godot 4.7 already defaults a Label to IGNORE. So the second assertion bites on the
	# node CHANGING TYPE -- a Button or a RichTextLabel stops at STOP -- and not on that line, which
	# is an explicit restatement of a default kept where someone would make the swap.
	var node: Node = game.mission_status_panel.get_node("ReportHint")
	assert_bool(node is BaseButton).override_failure_message(
		"the report sign became a button again -- it is a SIGN, and the card already has three doors"
		).is_false()
	assert_int((node as Control).mouse_filter).override_failure_message(
		"the report sign eats mouse input it has no use for").is_equal(Control.MOUSE_FILTER_IGNORE)


func test_the_sign_sits_clear_of_the_version_stamp() -> void:
	# MEASURED in the 1280x720 design space (#659): the sign sits at x 1133..1220, the stamp at
	# 1230..1274, both y 6..22, ten pixels apart -- so unlike its predecessor this one has real
	# teeth. Dropping the post-preset step in _build_report_hint() puts the sign at 1187..1274, on
	# top of the stamp, and reds both assertions below.
	#
	# The guard MEASURES both rects rather than recomputing the arithmetic it is guarding -- the
	# step is taken from the stamp's own minimum size, so a longer version string pushes the sign
	# along, and a case restating 44px would not notice if it stopped doing that.
	var sign_rect := _rect_of(_sign())
	var stamp_rect := _rect_of(game.mission_status_panel.get_node("VersionLabel"))

	assert_bool(sign_rect.intersects(stamp_rect)).override_failure_message(
		"the report sign %s overlaps the version stamp %s" % [sign_rect, stamp_rect]).is_false()
	assert_float(sign_rect.end.x).override_failure_message(
		"the report sign %s is not LEFT of the version stamp %s -- it stepped the wrong way"
		% [sign_rect, stamp_rect]).is_less_equal(stamp_rect.position.x)


func test_the_sign_does_not_sit_under_the_action_queue_dock() -> void:
	# The other neighbour in that corner, and a TRIPWIRE rather than a live guard: the dock's panel
	# begins at y 25 and the strip ends at 22, so nothing short of moving one of them brings these
	# together. Kept because "put it lower, there is room" is exactly the obvious next edit.
	var sign_rect := _rect_of(_sign())
	var dock: Control = game.squad_action_queue_control.get_node("BackgroundPanel")
	var dock_rect := _rect_of(dock)

	assert_bool(sign_rect.intersects(dock_rect)).override_failure_message(
		"the report sign %s overlaps the action-queue dock %s" % [sign_rect, dock_rect]).is_false()


func test_the_sign_stays_up_while_end_turn_stands_down() -> void:
	# "A notice on the screen at all times" is the ask, and the moments the board is playing back
	# at you are exactly the moments something looks wrong. EndTurnButton hides for a cinematic
	# pass (#722); the strip this lives in has no such gate. Falsified by giving the panel one.
	game.end_turn_button.set_hidden_for_playback(true)
	await await_idle_frame()

	assert_bool(game.end_turn_button.visible).override_failure_message(
		"End Turn did not stand down -- this case cannot see the difference").is_false()
	assert_bool(_sign().visible).override_failure_message(
		"the report sign went down with End Turn").is_true()


func test_the_sign_outlives_a_board_with_no_mission() -> void:
	# clear() takes the objective list down on a sandbox board. The strip is not mission status and
	# must not go with it -- the same rule the version stamp has always had, now with a second
	# reader. Falsified by hiding the panel root in clear() instead of the objective panel.
	game.mission_status_panel.clear()
	await await_idle_frame()

	assert_bool(_sign().visible).override_failure_message(
		"the report sign went down with the objective list").is_true()
	assert_bool(_sign().is_visible_in_tree()).override_failure_message(
		"the report sign is visible but its panel is not -- nothing draws it").is_true()
