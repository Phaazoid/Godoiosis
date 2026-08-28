# The settings page's WIRE (#350), fired as the real sequence on the real scene: the pause row
# opens it, a real checkbox press reaches the store, and Close hands back to the pause menu leaving
# the board playable.
#
# The chain this exists to defend is checkbox -> PlayerSettings -> UnitMirror's per-frame read, and
# its two ends were correct and unconnected before this ticket. What the BOARD then does with the
# setting is tests/presentation/test_unit_health_bar.gd's half; this suite stops at the store.
#
# test_glossary_screen's shape and its fixture. Frame counting, never await_millis.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

var _main: Node
var game: Node2D


func before_test() -> void:
	PlayerSettings.reset_for_test()   # in-memory, defaults only, never the developer's own cfg
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
	PlayerSettings.reset_for_test()   # and never leak a preference into the next suite


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _first_modal_of(script_class) -> Node:
	for node: Node in get_tree().get_nodes_in_group("modal"):
		if is_instance_of(node, script_class):
			return node
	return null


# CheckButton IS-A Button, so this finds the toggle rows and the choice segments as well as Close.
func _button_with_text(root: Node, text: String) -> Button:
	if root is Button and (root as Button).text == text:
		return root
	for child: Node in root.get_children():
		var found: Button = _button_with_text(child, text)
		if found != null:
			return found
	return null


# A choice row's title is a plain Label above its strip, not a button — so asking about a row's
# title has to reach both kinds (#418).
func _label_with_text(root: Node, text: String) -> Label:
	if root is Label and (root as Label).text == text:
		return root
	for child: Node in root.get_children():
		var found: Label = _label_with_text(child, text)
		if found != null:
			return found
	return null


func _row_title_shown(root: Node, text: String) -> bool:
	return _button_with_text(root, text) != null or _label_with_text(root, text) != null


# One segment of the health-bar strip, found by the label the STORE declares for that mode — so a
# renamed option moves the test with it rather than reddening it.
func _health_segment(screen: Node, mode: PlayerSettings.HealthBars) -> Button:
	var labels: Array = PlayerSettings.options_of(PlayerSettings.Setting.HEALTH_BARS)
	return _button_with_text(screen, str(labels[mode]))


# ==============================================================================
#  The pause route
# ==============================================================================

func test_pause_settings_close_lands_back_on_the_pause_menu() -> void:
	# The whole round trip, ending playable: Esc -> Settings -> Close -> pause menu -> Resume.
	# A wrong prior-state stash here locks the board for good, which is REPORT's old bug shape.
	game._open_pause_menu()
	await _frames(4)

	var menu: Node = _first_modal_of(PauseMenu)
	assert_object(menu).is_not_null()
	assert_object(_button_with_text(menu, "Settings")) \
		.override_failure_message("the pause menu has no Settings row").is_not_null()
	menu.chosen.emit(PauseMenu.Choice.SETTINGS)
	await _frames(4)

	var screen: Node = _first_modal_of(SettingsScreen)
	assert_object(screen).is_not_null()
	assert_int(game.process_mode).override_failure_message(
		"the settings page is up but the game subtree is not frozen") \
		.is_equal(Node.PROCESS_MODE_DISABLED)

	# The REAL Close button, not closed.emit() — a button nobody can press is the #131 bug shape.
	var close: Button = _button_with_text(screen, "Close")
	assert_object(close).is_not_null()
	close.pressed.emit()
	await _frames(4)

	var reopened: Node = _first_modal_of(PauseMenu)
	assert_object(reopened).override_failure_message(
		"closing the settings page did not return to the pause menu").is_not_null()
	reopened.chosen.emit(PauseMenu.Choice.RESUME)
	await _frames(4)

	assert_int(game.game_state).is_equal(game.GameState.IDLE)
	assert_bool(game._board_locked_for_player()).is_false()


# ==============================================================================
#  The checkbox reaches the store
# ==============================================================================

func test_pressing_a_toggle_row_writes_the_preference() -> void:
	SettingsScreen.show_screen(game)
	await _frames(4)
	var screen: Node = _first_modal_of(SettingsScreen)
	var setting := PlayerSettings.Setting.ALWAYS_SHOW_SQUAD_RINGS
	var row: Button = _button_with_text(screen, PlayerSettings.title_of(setting))
	assert_object(row).override_failure_message(
		"the settings page has no row for ALWAYS_SHOW_SQUAD_RINGS").is_not_null()
	assert_bool(row.button_pressed).is_false()   # the default, read back off the page

	# Flipping button_pressed is what a click does: the control emits `toggled` through its own
	# state rather than the test emitting the signal the handler happens to listen for.
	row.button_pressed = true
	await _frames(2)

	assert_bool(PlayerSettings.is_on(setting)) \
		.override_failure_message("the checkbox moved and the store did not").is_true()

	row.button_pressed = false
	await _frames(2)
	assert_bool(PlayerSettings.is_on(setting)).is_false()


func test_picking_a_segment_writes_the_chosen_mode() -> void:
	# #418's wire: the strip is the first non-checkbox row this page has ever had, and what it must
	# do is the same thing every row above it does -- reach the store, by its own state.
	SettingsScreen.show_screen(game)
	await _frames(4)
	var screen: Node = _first_modal_of(SettingsScreen)
	var damaged: Button = _health_segment(screen, PlayerSettings.HealthBars.DAMAGED)
	assert_object(damaged).override_failure_message(
		"the settings page has no 'damaged units' segment").is_not_null()

	damaged.button_pressed = true
	await _frames(2)
	assert_int(PlayerSettings.choice_of(PlayerSettings.Setting.HEALTH_BARS)) \
		.override_failure_message("the segment moved and the store did not") \
		.is_equal(PlayerSettings.HealthBars.DAMAGED)

	# A DIFFERENT segment, so a handler writing one constant cannot pass both halves of this case.
	_health_segment(screen, PlayerSettings.HealthBars.EVERY).button_pressed = true
	await _frames(2)
	assert_int(PlayerSettings.choice_of(PlayerSettings.Setting.HEALTH_BARS)) \
		.is_equal(PlayerSettings.HealthBars.EVERY)


func test_the_strip_leaves_exactly_one_segment_pressed() -> void:
	# The whole reason it is a ButtonGroup: three loose toggles can show two modes chosen at once,
	# which is the illegal state the choice kind exists to make unrepresentable.
	SettingsScreen.show_screen(game)
	await _frames(4)
	var screen: Node = _first_modal_of(SettingsScreen)
	_health_segment(screen, PlayerSettings.HealthBars.DAMAGED).button_pressed = true
	await _frames(2)

	var pressed := 0
	for mode: PlayerSettings.HealthBars in PlayerSettings.HealthBars.values():
		if _health_segment(screen, mode).button_pressed:
			pressed += 1
	assert_int(pressed).override_failure_message(
		"the health-bar strip is showing %d modes chosen at once" % pressed).is_equal(1)


func test_the_page_opens_showing_what_was_already_chosen() -> void:
	# A settings page that always opens on the defaults is the shape that reads as "it didn't save".
	PlayerSettings.set_on(PlayerSettings.Setting.ALWAYS_SHOW_SQUAD_RINGS, true)
	PlayerSettings.set_choice(PlayerSettings.Setting.HEALTH_BARS, PlayerSettings.HealthBars.DAMAGED)

	SettingsScreen.show_screen(game)
	await _frames(4)
	var screen: Node = _first_modal_of(SettingsScreen)

	assert_bool(_button_with_text(screen,
			PlayerSettings.title_of(PlayerSettings.Setting.ALWAYS_SHOW_SQUAD_RINGS)).button_pressed) \
		.is_true()
	assert_bool(_health_segment(screen, PlayerSettings.HealthBars.DAMAGED).button_pressed) \
		.override_failure_message("the page opened on a mode the player had not chosen").is_true()


func test_every_declared_setting_gets_a_row() -> void:
	# The page is a projection of DEFS, so this is what keeps "declare it and it appears" true —
	# the property that lets #217's toggle be a store edit rather than UI work. It asks about BOTH
	# kinds on purpose: narrowing it to the toggles would retire the property for choice rows the
	# moment #418 added one.
	SettingsScreen.show_screen(game)
	await _frames(4)
	var screen: Node = _first_modal_of(SettingsScreen)

	for setting: PlayerSettings.Setting in PlayerSettings.Setting.values():
		assert_bool(_row_title_shown(screen, PlayerSettings.title_of(setting))) \
			.override_failure_message("no row for %s" % PlayerSettings.Setting.keys()[setting]) \
			.is_true()


func test_every_option_of_a_choice_row_is_reachable() -> void:
	# A strip that drew two of its three modes would look entirely correct and leave one preference
	# unpickable -- the projection property, one level down from "the row exists at all".
	SettingsScreen.show_screen(game)
	await _frames(4)
	var screen: Node = _first_modal_of(SettingsScreen)

	for setting: PlayerSettings.Setting in PlayerSettings.Setting.values():
		if not PlayerSettings.is_choice(setting):
			continue
		var name: String = PlayerSettings.Setting.keys()[setting]
		for label: Variant in PlayerSettings.options_of(setting):
			assert_object(_button_with_text(screen, str(label))) \
				.override_failure_message("%s has no segment for '%s'" % [name, label]) \
				.is_not_null()
