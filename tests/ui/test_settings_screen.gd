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


# The OTHER half of "the page fits", and it is not optional: a body squashed to nothing fits every
# viewport there is, so "Close is on screen" alone is satisfied by a settings page showing NOTHING.
# Found by falsifying -- the first version of these cases passed against exactly that.
func _assert_the_body_is_not_collapsed(screen: Node) -> void:
	var scroll: ScrollContainer = _first_of(screen, ScrollContainer)
	assert_object(scroll).override_failure_message(
		"the settings page has no scroll region, so nothing bounds its body").is_not_null()
	assert_float(scroll.size.y).override_failure_message(
		"the settings body is %.1f tall -- the page fits by showing nothing" % scroll.size.y
		).is_greater_equal(SettingsScreen.MIN_BODY_HEIGHT)


func _first_of(root: Node, type) -> Node:
	if is_instance_of(root, type):
		return root
	for child: Node in root.get_children():
		var found: Node = _first_of(child, type)
		if found != null:
			return found
	return null


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


# ==============================================================================
#  The page has to FIT, and it has to have a second door
# ==============================================================================

# Esc through the OS-driver entry, test_input_bridge's idiom -- the real pipeline, so what is under
# test is the whole chain root viewport -> SubViewportContainer -> ui_layer -> ModalCard._input.
func _press_escape() -> void:
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(2)
	var up := InputEventKey.new()
	up.keycode = KEY_ESCAPE
	up.physical_keycode = KEY_ESCAPE
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)


func test_the_close_button_is_somewhere_a_player_can_actually_reach() -> void:
	# THE CASE THAT WOULD HAVE CAUGHT #418's LOCK. Every other case here presses Close by calling
	# it, which works perfectly on a button hanging off the bottom of the screen -- so the whole
	# suite stayed green while the page was a room with no door. #131's shape: a button nobody can
	# press. The claim is GEOMETRY, and nothing else here makes one.
	SettingsScreen.show_screen(game)
	await _frames(4)
	var screen: Node = _first_modal_of(SettingsScreen)
	var close: Button = _button_with_text(screen, "Close")
	assert_object(close).is_not_null()

	# Non-vacuity: a zero-sized button sits inside every rect there is.
	assert_float(close.size.y).override_failure_message(
		"the Close button has no height, so the bounds check below proves nothing").is_greater(0.0)
	_assert_the_body_is_not_collapsed(screen)

	var view: Vector2 = screen.get_viewport_rect().size
	var bottom := close.global_position.y + close.size.y
	assert_float(bottom).override_failure_message(
		"the Close button's bottom edge is at %.1f on a %.1f-tall viewport -- the page cannot be left"
		% [bottom, view.y]).is_less_equal(view.y)
	assert_float(close.global_position.y).override_failure_message(
		"the Close button is off the TOP of the screen").is_greater_equal(0.0)


func test_the_page_still_fits_when_the_body_is_far_taller_than_the_screen() -> void:
	# The property, not the arithmetic: the fit above could be true by luck at five settings. Here
	# the body is grown past any viewport, so only the scroll region can keep Close on screen --
	# which is what makes a SIXTH setting safe rather than a coin flip.
	SettingsScreen.show_screen(game)
	await _frames(4)
	var screen: Node = _first_modal_of(SettingsScreen)
	var scroll: ScrollContainer = _first_of(screen, ScrollContainer)
	assert_object(scroll).override_failure_message(
		"the settings page has no scroll region, so nothing bounds its body").is_not_null()

	var rows: Control = scroll.get_child(0)
	for i in 40:
		var filler := Label.new()
		filler.text = "filler row %d" % i
		rows.add_child(filler)
	await _frames(4)

	_assert_the_body_is_not_collapsed(screen)
	var close: Button = _button_with_text(screen, "Close")
	assert_float(close.global_position.y + close.size.y).override_failure_message(
		"forty extra rows pushed Close off the screen -- the body is not actually bounded"
		).is_less_equal(float(screen.get_viewport_rect().size.y))


func test_escape_backs_out_of_the_settings_page() -> void:
	# The second door, and the one that cannot leave the screen. game.gd stands down on ui_cancel
	# while any modal is open, so before #418's follow-up this key reached nothing at all.
	SettingsScreen.show_screen(game)
	await _frames(4)
	assert_object(_first_modal_of(SettingsScreen)).override_failure_message(
		"the page never opened, so its closing proves nothing").is_not_null()

	await _press_escape()
	await _frames(4)

	assert_object(_first_modal_of(SettingsScreen)).override_failure_message(
		"Esc did not close the settings page").is_null()
