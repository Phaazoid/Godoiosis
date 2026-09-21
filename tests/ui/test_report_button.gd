# The on-screen report mark (#1051) -- that it is BUILT, that it reaches the one report door, and
# that it does not sit on top of the two things it shares the top-right corner with.
#
# The overlap cases are the point of this file. ReportButton.DOCK_CLEARANCE is a second spelling of
# where the action-queue dock's left edge is, and a constant that restates another surface's layout
# goes stale the day that surface moves -- silently, because two overlapping Controls both draw.
# So the guard measures the LIVE rects rather than recomputing the arithmetic it is guarding
# (`tests/ui/test_queue_badge_widths.gd`'s habit: price against the anchored thing).
#
# Why the corner itself is not the answer, written down so the next person does not re-derive it:
# MissionStatusPanel's VersionLabel takes the top-right 54px and the dock begins at y 25, so the
# free band beside the version stamp is 25px tall -- while a Button carrying one word measures
# 61x31. Measured, not estimated.
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
	get_tree().paused = false
	if is_instance_valid(game):
		game.process_mode = Node.PROCESS_MODE_INHERIT
	for node: Node in get_tree().get_nodes_in_group(ModalLock.GROUP):
		node.free()
	remove_child(_main)
	_main.free()
	await await_idle_frame()


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _first_modal_of(script_class) -> Node:
	for node: Node in get_tree().get_nodes_in_group(ModalLock.GROUP):
		if is_instance_of(node, script_class):
			return node
	return null


func test_the_mark_is_built_and_visible() -> void:
	var mark: ReportButton = game.report_button
	assert_object(mark).override_failure_message(
		"the report mark is not in the built tree").is_not_null()
	assert_bool(mark.visible).is_true()
	assert_float(mark.button_rect().size.x).override_failure_message(
		"the mark has no width -- it is in the tree and draws nothing").is_greater(0.0)

	# ON SCREEN, and this is not padding: the two overlap cases below both pass just as happily if
	# DOCK_CLEARANCE walks the mark off the LEFT edge, so without this the guard has a whole
	# direction it cannot see. The design space is the frame of reference (#659), never the window.
	var design: Vector2 = game.get_viewport_rect().size
	var rect := mark.button_rect()
	assert_bool(Rect2(Vector2.ZERO, design).encloses(rect)).override_failure_message(
		"the report mark %s is not fully inside the %s design space" % [rect, design]).is_true()


func test_pressing_the_mark_opens_the_report_card() -> void:
	# The WIRE: the button is dumb and emits, game.gd routes it to open_report_card. Both ends were
	# correct and unconnected is #103's shape, so this drives the real signal rather than the door.
	var mark: ReportButton = game.report_button
	var button: Button = mark.get_node("Button")
	button.pressed.emit()
	await _frames(4)

	var card: Node = _first_modal_of(ReportPanel)
	assert_object(card).override_failure_message(
		"the mark did not reach the report card").is_not_null()
	card.finished.emit(false)
	await _frames(4)


func test_the_mark_does_not_sit_under_the_action_queue_dock() -> void:
	# Falsified by dropping DOCK_CLEARANCE to 0: the mark lands in the corner, under the dock.
	var mark: ReportButton = game.report_button
	var dock: Control = game.squad_action_queue_control.get_node("BackgroundPanel")
	var dock_rect := Rect2(dock.global_position, dock.size)

	assert_bool(mark.button_rect().intersects(dock_rect)).override_failure_message(
		"the report mark %s overlaps the action-queue dock %s" % [mark.button_rect(), dock_rect]
		).is_false()


func test_the_mark_does_not_sit_under_the_version_stamp() -> void:
	# The other neighbour in that corner -- and DECLARED AS A TRIPWIRE, not a live guard. Measured:
	# the stamp sits at x 1230..1274 and the mark at x 968..1041, so nothing short of a deliberate
	# relocation can bring them together, and three attempts to mutate this case red all failed
	# (widening the .tscn offsets does nothing, because MissionStatusPanel.gd:40 repositions the
	# label in code; growing that margin moves it diagonally out of reach instead).
	#
	# It is kept because it costs one rect compare and it is the guard that would catch someone
	# moving this mark INTO the corner later -- which is exactly the obvious thing to try. The guard
	# with real teeth is the dock one above.
	var mark: ReportButton = game.report_button
	var stamp: Control = game.mission_status_panel.get_node("VersionLabel")
	var stamp_rect := Rect2(stamp.global_position, stamp.size)

	assert_bool(mark.button_rect().intersects(stamp_rect)).override_failure_message(
		"the report mark %s overlaps the version stamp %s" % [mark.button_rect(), stamp_rect]
		).is_false()


func test_the_mark_stays_up_while_end_turn_stands_down() -> void:
	# The one place it parts from EndTurnButton, and the reason is the ticket's: a pass playing back
	# at you is exactly when something looks wrong and you want to say so. Falsified by giving this
	# button End Turn's playback gate.
	game.end_turn_button.set_hidden_for_playback(true)
	await _frames(2)

	assert_bool(game.end_turn_button.visible).override_failure_message(
		"End Turn did not stand down -- this case cannot see the difference").is_false()
	assert_bool(game.report_button.visible).override_failure_message(
		"the report mark went down with End Turn").is_true()
