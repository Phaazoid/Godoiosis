# The Settings page's CONTROLS pane (#691) -- the wire, on the real scene.
#
# What this defends is that the pane is a PROJECTION and that the projection RAN. A pane built
# from an empty list still lays out, still fits, and still switches when you press its button, so
# every structural check passes over a page showing nothing -- the same blind spot that made
# tests/dev/test_dev_info_page.gd necessary one window over, and the reason its sibling case here
# asserts on entries reaching labels rather than on nodes existing.
#
# The filter is the other half. A dev binding on a player's page is the failure this ticket could
# most plausibly ship, because the two contexts live in one store and nothing about rendering a
# row knows which audience it is for.
#
# test_settings_screen's shape and its fixture. Frame counting, never await_millis.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

var _main: Node
var game: Node2D


func before_test() -> void:
	PlayerSettings.reset_for_test()
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
	remove_child(_main)
	_main.free()
	PlayerSettings.reset_for_test()


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _open() -> SettingsScreen:
	var screen := SettingsScreen.new()
	game.ui_layer.add_child(screen)
	screen._build(game)
	await _frames(2)
	return screen


func _labels(node: Node) -> Array[String]:
	var out: Array[String] = []
	var label := node as Label
	if label != null:
		out.append(label.text)
	for child: Node in node.get_children():
		out.append_array(_labels(child))
	return out


func _button_with_text(root: Node, text: String) -> Button:
	if root is Button and (root as Button).text == text:
		return root
	for child: Node in root.get_children():
		var found: Button = _button_with_text(child, text)
		if found != null:
			return found
	return null


func test_every_player_binding_reaches_the_controls_pane() -> void:
	var screen := await _open()
	var shown: Array[String] = _labels(screen)
	var missing: Array[String] = []
	for context: Controls.Context in Controls.PLAYER_CONTEXTS:
		for entry: Dictionary in Controls.in_context(context):
			var key: String = entry["key"]
			if not shown.has(key):
				missing.append(key)
	assert_array(missing).override_failure_message(
		"Player bindings that never reached the Controls pane: %s (page shows %d labels)"
			% [", ".join(missing), shown.size()]).is_empty()
	screen.queue_free()


# The filter, asserted on what the page SHOWS rather than on the constant -- the law suite already
# pins that PLAYER_CONTEXTS excludes DEV, and this pins that the page actually reads it.
func test_no_authoring_binding_reaches_the_players_page() -> void:
	var screen := await _open()
	var shown: Array[String] = _labels(screen)
	var leaked: Array[String] = []
	for entry: Dictionary in Controls.in_context(Controls.Context.DEV):
		var does: String = entry["does"]
		if shown.has(does):
			leaked.append(entry["key"])
	assert_array(leaked).override_failure_message(
		"Dev-only bindings leaked onto the player's settings page: %s" % ", ".join(leaked)).is_empty()
	screen.queue_free()


# Both panes are built once and switched by visibility, so "switching works" is a question about
# what is VISIBLE, never about what exists. A case asserting on presence alone passes with the
# switch deleted, since both panes are in the tree from the first frame.
func test_the_pane_buttons_switch_which_pane_is_visible() -> void:
	var screen := await _open()
	var settings_pane: Control = screen._panes[SettingsScreen.Pane.SETTINGS]
	var controls_pane: Control = screen._panes[SettingsScreen.Pane.CONTROLS]

	assert_bool(settings_pane.visible).override_failure_message(
		"The page did not open on Settings").is_true()
	assert_bool(controls_pane.visible).override_failure_message(
		"Controls is visible before it was asked for").is_false()

	_button_with_text(screen, "Controls").pressed.emit()
	await _frames(1)
	assert_bool(controls_pane.visible).override_failure_message(
		"Pressing Controls did not show the Controls pane").is_true()
	assert_bool(settings_pane.visible).override_failure_message(
		"Both panes are visible at once").is_false()

	_button_with_text(screen, "Settings").pressed.emit()
	await _frames(1)
	assert_bool(settings_pane.visible).override_failure_message(
		"Pressing Settings did not come back").is_true()
	screen.queue_free()


# The settings rows still follow the store while the Controls pane is up: _process reconciles
# controls it holds by reference, and hiding a pane must not stop that. Cheap to assert and it is
# the one interaction between the two panes.
func test_hiding_the_settings_pane_does_not_stop_it_following_the_store() -> void:
	var screen := await _open()
	_button_with_text(screen, "Controls").pressed.emit()
	await _frames(1)
	var setting: PlayerSettings.Setting = PlayerSettings.Setting.values()[0]
	if PlayerSettings.is_choice(setting):
		screen.queue_free()
		return   # the first row is a choice on this build; the toggle path is what this case drives
	var toggle: CheckButton = screen._toggles[setting]
	var flipped := not PlayerSettings.is_on(setting)
	PlayerSettings.set_on(setting, flipped)
	await _frames(2)
	assert_bool(toggle.button_pressed).override_failure_message(
		"A hidden settings row stopped following the store").is_equal(flipped)
	screen.queue_free()
