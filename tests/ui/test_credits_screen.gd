# The Credits page's WIRE (#139), fired as the real sequence on the real scene: the title-screen
# row opens it, the required rows reach the page, Close hands the freeze back.
#
# THE PROPERTY THAT MATTERS HERE IS A LICENCE CONDITION, not a layout. Two credits ship because a
# grant was made on condition of attribution, so "the page renders" is not the claim — "every row
# marked required is on it" is. Asserted as a PROPERTY over Credits.required_entries(), never as
# an expected list, so re-wording a row or adding a fourth grant does not red this suite.
#
# Data-side coverage lives in tests/law/test_credits_required.gd — including the guard that
# required_entries() is not EMPTY, without which every assertion here passes vacuously.
# Frame counting, never await_millis (see test_report_flow.gd's note).
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
	# A test that fails mid-modal would otherwise leave the freeze on for everything after it.
	get_tree().paused = false
	if is_instance_valid(game):
		game.process_mode = Node.PROCESS_MODE_INHERIT
	remove_child(_main)
	_main.free()


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _first_modal_of(script_class) -> Node:
	for node: Node in get_tree().get_nodes_in_group("modal"):
		if is_instance_of(node, script_class):
			return node
	return null


func _button_with_text(root: Node, text: String) -> Button:
	if root is Button and (root as Button).text == text:
		return root
	for child: Node in root.get_children():
		var found: Button = _button_with_text(child, text)
		if found != null:
			return found
	return null


func _visible_text(root: Node) -> String:
	var parts: Array[String] = []
	_collect_label_text(root, parts)
	return "\n".join(parts)


func _collect_label_text(node: Node, parts: Array[String]) -> void:
	var label := node as Label
	if label != null:
		parts.append(label.text)
	for child: Node in node.get_children():
		_collect_label_text(child, parts)


# ==============================================================================
#  The title-screen route
# ==============================================================================

func test_the_title_screen_offers_credits_and_the_row_opens_the_page() -> void:
	# A signal with no button is a dead end that compiles (#103's shape), so the ROW is asserted
	# before the route is driven through it.
	var select: Node = game.mission_controller._select_screen
	assert_object(select) \
		.override_failure_message("fixture assumption broke: boot did not leave the mission select open") \
		.is_not_null()
	assert_object(_button_with_text(select, "Credits")) \
		.override_failure_message("the title screen has no Credits row").is_not_null()

	select.credits_chosen.emit()   # the REAL wiring, not a direct show_screen call
	await _frames(4)

	assert_object(_first_modal_of(CreditsScreen)) \
		.override_failure_message("credits_chosen is connected to nothing").is_not_null()


func test_closing_leaves_the_game_thawed() -> void:
	# MissionSelectScreen deliberately claims no lock; the credits page opened over it DOES.
	# Closing must hand the freeze back, or the next mission picked never runs (the #143 property).
	game.mission_controller._select_screen.credits_chosen.emit()
	await _frames(4)
	var screen: Node = _first_modal_of(CreditsScreen)
	assert_object(screen).is_not_null()
	assert_int(game.process_mode).override_failure_message(
		"the credits page is up but the game subtree is not frozen") \
		.is_equal(Node.PROCESS_MODE_DISABLED)

	# The REAL Close button, not closed.emit() — a button nobody can press is the #131 bug shape.
	var close: Button = _button_with_text(screen, "Close")
	assert_object(close).is_not_null()
	close.pressed.emit()
	await _frames(4)

	assert_object(_first_modal_of(CreditsScreen)).is_null()
	assert_int(game.process_mode) \
		.override_failure_message("closing the credits page left the game frozen behind the title screen") \
		.is_not_equal(Node.PROCESS_MODE_DISABLED)


# ==============================================================================
#  The licence conditions reach the player
# ==============================================================================

func test_every_required_credit_is_on_the_page() -> void:
	CreditsScreen.show_screen(game)
	await _frames(4)
	var screen: Node = _first_modal_of(CreditsScreen)
	assert_object(screen).is_not_null()

	var page: String = _visible_text(screen)
	for entry: Dictionary in Credits.required_entries():
		var who: String = String(entry.get("name", ""))
		assert_str(page).override_failure_message(
			"'%s' is a licence CONDITION and the credits page does not name them -- "
			% who + "this build ships outside the terms it was granted under").contains(who)
		var detail: String = String(entry.get("detail", ""))
		if detail != "":
			assert_str(page).override_failure_message(
				"'%s' is credited but the attribution detail the grant asks for (%s) is missing"
				% [who, detail]).contains(detail)

	_button_with_text(screen, "Close").pressed.emit()
	await _frames(2)


func test_escape_closes_the_page() -> void:
	CreditsScreen.show_screen(game)
	await _frames(4)
	var screen: Node = _first_modal_of(CreditsScreen)
	assert_object(screen).is_not_null()

	# Without _on_cancel this page swallows the key outright — game._input stands down while any
	# modal is up, so nothing else would answer it.
	assert_bool(screen._on_cancel()).is_true()
	await _frames(4)
	assert_object(_first_modal_of(CreditsScreen)).is_null()
