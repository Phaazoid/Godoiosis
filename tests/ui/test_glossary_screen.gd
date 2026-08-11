# The Glossary page's WIRE (#135), fired as the real sequence on the real scene: the pause row
# opens it, its content populates from the registry, its Close button (a REAL button press — the
# #131 lesson) hands back to the pause menu, and the title-screen route leaves the game thawed.
#
# Content coverage lives in tests/law/test_glossary_coverage.gd; this suite is only the wiring
# and the lifecycle. Frame counting, never await_millis (see test_report_flow.gd's note).
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


func _modals() -> Array[Node]:
	return get_tree().get_nodes_in_group("modal")


func _first_modal_of(script_class) -> Node:
	for node: Node in _modals():
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


# All label text under a node, joined — for asserting what a page actually shows.
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
#  The pause route
# ==============================================================================

func test_pause_glossary_close_lands_back_on_the_pause_menu() -> void:
	# The whole round trip, ending playable: Esc -> Glossary -> Close -> pause menu -> Resume.
	# Same shape as REPORT's regression case — a wrong prior-state stash here locks the board.
	game._open_pause_menu()
	await _frames(4)

	var menu: Node = _first_modal_of(PauseMenu)
	assert_object(menu).is_not_null()
	assert_object(_button_with_text(menu, "Glossary")) \
		.override_failure_message("the pause menu has no Glossary row").is_not_null()
	menu.chosen.emit(PauseMenu.Choice.GLOSSARY)
	await _frames(4)

	var screen: Node = _first_modal_of(GlossaryScreen)
	assert_object(screen).is_not_null()
	assert_int(game.process_mode).override_failure_message(
		"the glossary is up but the game subtree is not frozen") \
		.is_equal(Node.PROCESS_MODE_DISABLED)

	# The REAL Close button, not closed.emit() — a button nobody can press is the #131 bug shape.
	var close: Button = _button_with_text(screen, "Close")
	assert_object(close).is_not_null()
	close.pressed.emit()
	await _frames(4)

	var reopened: Node = _first_modal_of(PauseMenu)
	assert_object(reopened) \
		.override_failure_message("closing the glossary did not return to the pause menu").is_not_null()
	reopened.chosen.emit(PauseMenu.Choice.RESUME)
	await _frames(4)

	assert_int(game.game_state).is_equal(game.GameState.IDLE)
	assert_bool(game._board_locked_for_player()).is_false()


# ==============================================================================
#  Content reaches the page
# ==============================================================================

func test_pages_render_the_registry_and_the_composed_reactions() -> void:
	GlossaryScreen.show_screen(game)
	await _frames(4)
	var screen: Node = _first_modal_of(GlossaryScreen)
	assert_object(screen).is_not_null()

	# Default page: Squads.
	assert_str(_visible_text(screen._entries_box)) \
		.override_failure_message("the default (Squads) page shows no squad entry").contains("Squad")

	# Elemental page ends with the interaction list composed from the real authored catalogs —
	# assert on data-derived content (the trigger element's name), not on authored prose.
	var elemental_button: Button = screen._category_buttons[Glossary.Category.ELEMENTAL]
	elemental_button.pressed.emit()
	await _frames(2)
	var page: String = _visible_text(screen._entries_box)
	var reactions: Array[ElementalReaction] = ReactionCatalog.get_all()
	assert_int(reactions.size()) \
		.override_failure_message("no authored reactions on disk — the composed-list assertions are vacuous") \
		.is_greater(0)
	for reaction: ElementalReaction in reactions:
		assert_str(page) \
			.override_failure_message("the elemental page never names %s — the composed reaction list is not rendering"
				% Elemental.display_name(reaction.incoming_element)) \
			.contains(Elemental.display_name(reaction.incoming_element))

	_button_with_text(screen, "Close").pressed.emit()
	await _frames(2)


# ==============================================================================
#  The title-screen route
# ==============================================================================

func test_title_screen_route_leaves_the_game_thawed() -> void:
	# MissionSelectScreen deliberately claims no lock; the glossary opened over it DOES. Closing
	# must hand the freeze back, or the next mission picked never runs (the #143 property).
	var select: Node = game.mission_controller._select_screen
	assert_object(select) \
		.override_failure_message("fixture assumption broke: boot did not leave the mission select open") \
		.is_not_null()

	select.glossary_chosen.emit()   # the REAL wiring, not a direct show_screen call
	await _frames(4)
	var screen: Node = _first_modal_of(GlossaryScreen)
	assert_object(screen).is_not_null()
	assert_int(game.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)

	_button_with_text(screen, "Close").pressed.emit()
	await _frames(4)

	assert_object(_first_modal_of(GlossaryScreen)).is_null()
	assert_int(game.process_mode) \
		.override_failure_message("closing the glossary left the game subtree frozen behind the title screen") \
		.is_not_equal(Node.PROCESS_MODE_DISABLED)
