# Does the title screen's column FIT the space it is laid out in (#723)?
#
# The dev asked for "a dedicated feedback option on the title screen". There already is one --
# MissionSelectScreen adds an ungated "Send Feedback" button wired to Kind.FEEDBACK on purpose
# (#131 item 6). The theory this suite exists to test is that it is simply BELOW THE BOTTOM EDGE.
#
# The mechanism, if so, is #418's bug class one screen over: ModalCard's unframed path returns a
# bare CenterContainer, which centres its child at the child's MINIMUM size and lets it overflow
# BOTH edges with no scrollbar. The mission list is already bounded (its own 420px scroller) -- it
# is the FIXED rows below it that push the column past the bottom, so the last ones added lose.
#
# WHY THIS IS NOT WINDOW-SIZE DEPENDENT, which is what makes it worth a suite: GameSurface lays the
# whole battle UI out in a fixed DESIGN space (#659), and that space is exactly 1280x720 for ANY
# 16:9 window -- 1080p and 1440p included. It only grows on a window TALLER than 16:9. So a column
# that overflows 720 overflows on essentially every display, maximised or not, and "it looks fine
# on my monitor" cannot clear it.
#
# MEASURED AS A PROPERTY, NEVER A PIXEL COUNT: the question is "does it fit", asked against the
# viewport's own height, so any row anyone adds later re-asks it and no tuning value can move the
# answer without moving the assertion.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const TEST_SAVE_DIR := "user://test_saves_title_fit/"

var _main: Node
var _game: Node2D
var _view: SubViewport


func before_test() -> void:
	# Redirected for the reason test_pause_menu.gd states: the suite otherwise shares the dev's own
	# play saves, and any_save_exists() decides whether a "Load Game" row is built at all. Set
	# before Main instantiates -- the boot title screen reads it.
	ScenarioManager.save_dir = TEST_SAVE_DIR
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	add_child(_main)
	await await_idle_frame()
	_game = _main.get_node("GameContainer/GameView/Game") as Node2D
	_view = _main.get_node("GameContainer/GameView") as SubViewport
	# game._ready DEFERS open_mission_select, so the screen lands a frame or two after the scene.
	await await_idle_frame()
	await await_idle_frame()


func after_test() -> void:
	remove_child(_main)
	_main.free()
	await await_idle_frame()


func _title_screen() -> MissionSelectScreen:
	var layer: Node = _game.get("ui_layer")
	for child: Node in layer.get_children():
		if child is MissionSelectScreen:
			return child as MissionSelectScreen
	return null


# The content column the base builds: <frame> -> VBoxContainer. Walked by TYPE off the card's own
# children rather than by find_children, for the reason test_modal_card_scaffold.gd's _chrome_panel
# gives -- a recursive search answers "is there one anywhere in here", which is a different question
# and would happily report the mission list's own inner box.
#
# The FRAME's type is deliberately not named: it is the step this screen overrides (#723), and a
# suite that pins it would fail the fix rather than the bug. Only the backdrop and the branding sit
# beside it, and neither is a Container.
func _column(screen: MissionSelectScreen) -> VBoxContainer:
	for child: Node in screen.get_children():
		if child is Container:
			for inner: Node in child.get_children():
				if inner is VBoxContainer:
					return inner as VBoxContainer
	return null


func _button_named(column: VBoxContainer, label: String) -> Button:
	for node: Node in column.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == label:
			return button
	return null


func test_the_title_column_fits_the_design_space() -> void:
	var screen: MissionSelectScreen = _title_screen()
	assert_object(screen).override_failure_message(
		"the title screen never opened, so nothing here measures anything").is_not_null()

	var column: VBoxContainer = _column(screen)
	assert_object(column).override_failure_message(
		"could not find the title screen's content column -- the chrome shape changed").is_not_null()

	var wanted: float = column.get_combined_minimum_size().y
	var room: float = _view.get_visible_rect().size.y
	assert_float(wanted).override_failure_message(
		("the title column wants %.0fpx of height and the design space is only %.0fpx, so it "
		+ "overflows a bare CenterContainer by %.0fpx -- split top and bottom, which puts the "
		+ "LAST rows (Send Feedback, Quit Game) below the bottom edge with no scrollbar. "
		+ "Note this is with NO save on disk; a save adds a Load Game row and makes it worse.")
		% [wanted, room, wanted - room]) \
		.is_less_equal(room)


# The consequence, asked where the dev actually met it. Separate from the case above because it
# fails to a different mistake: a fix that bounds the column by SCROLLING it would satisfy "fits"
# while still leaving this button off screen until someone scrolls, and that is not a door a
# stranger finds either.
func test_the_feedback_button_is_on_screen() -> void:
	var screen: MissionSelectScreen = _title_screen()
	var column: VBoxContainer = _column(screen)
	var feedback: Button = _button_named(column, "Send Feedback")
	assert_object(feedback).override_failure_message(
		"the title screen has no Send Feedback button at all").is_not_null()

	var bottom: float = feedback.global_position.y + feedback.size.y
	var room: float = _view.get_visible_rect().size.y
	assert_float(bottom).override_failure_message(
		("Send Feedback ends %.0fpx down a %.0fpx screen -- it is %.0fpx BELOW the bottom edge, "
		+ "which is why the title screen reads as having no feedback door.")
		% [bottom, room, bottom - room]) \
		.is_less_equal(room)
