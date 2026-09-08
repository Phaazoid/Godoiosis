# THE FIRST-LAUNCH NOTICE (#53 slice 3), driven through the real boot.
#
# The four should_show() cases are pure and need no scene. The rest are WIRE cases and boot
# Main.tscn, because what is under test is that game._ready's deferred open_mission_select actually
# reaches the card -- both ends being correct while nothing connects them is #103's shape, and this
# wire crosses two files.
#
# TelemetryNotice.enabled IS FALSE HEADLESS, so every wire case turns it back on deliberately and
# after_test turns it off again. That restore is not tidiness: statics outlive a suite inside one
# gdUnit4 process, and 89 other suites boot Main.tscn -- leaking `true` would stack a modal over the
# front door of most of the test tree, and they would fail somewhere else entirely.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const SCRATCH_ROOT := "user://__telemetry_notice_test/"

var _main: Node
var game: Node2D


func before_test() -> void:
	TelemetryStore.reset_for_test()
	TelemetryStore.root = SCRATCH_ROOT
	_wipe()


func after_test() -> void:
	# Off again before anything else runs -- see the header.
	TelemetryNotice.enabled = false
	for node: Node in get_tree().get_nodes_in_group(ModalLock.GROUP):
		node.free()
	if is_instance_valid(game):
		game.process_mode = Node.PROCESS_MODE_INHERIT
	if is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	_wipe()
	TelemetryStore.reset_for_test()


# ==============================================================================
#  Is a notice due? -- the three clauses, one case each
# ==============================================================================

func test_a_fresh_install_is_due_the_notice() -> void:
	TelemetryStore.persistence_enabled = true
	TelemetryNotice.enabled = true
	assert_bool(TelemetryNotice.should_show()).is_true()


func test_the_notice_is_not_due_once_it_has_been_seen() -> void:
	TelemetryStore.persistence_enabled = true
	TelemetryNotice.enabled = true
	TelemetryStore.mark_notice_seen()
	assert_bool(TelemetryNotice.should_show()).is_false()


func test_a_headless_process_is_never_due_the_notice() -> void:
	TelemetryStore.persistence_enabled = true
	TelemetryNotice.enabled = false
	# Fresh install in every other respect: the seam alone is what refuses.
	assert_bool(TelemetryStore.notice_seen()).is_false()
	assert_bool(TelemetryNotice.should_show()).is_false()


# A notice we could not record having shown would reappear on every launch, which is worse for the
# player than never showing it -- so "cannot remember" refuses in its own right.
func test_a_notice_that_could_not_be_remembered_is_never_due() -> void:
	TelemetryStore.persistence_enabled = false
	TelemetryNotice.enabled = true
	assert_bool(TelemetryNotice.should_show()).is_false()


# _write_key is read-modify-write for exactly this reason: ConfigFile.save writes the WHOLE file, so
# a blind write of the second key would drop the first.
func test_the_marker_shares_its_file_with_the_install_id() -> void:
	TelemetryStore.persistence_enabled = true
	var id: String = TelemetryStore.install_id()
	assert_str(id).is_not_empty()
	TelemetryStore.mark_notice_seen()
	var cfg := ConfigFile.new()
	assert_int(cfg.load(TelemetryStore.config_path())).is_equal(OK)
	assert_str(str(cfg.get_value(TelemetryStore.CONFIG_SECTION, TelemetryStore.INSTALL_ID_KEY, ""))).is_equal(id)
	assert_bool(TelemetryStore.notice_seen()).is_true()


# ==============================================================================
#  The wire -- booting the real scene
# ==============================================================================

func test_booting_puts_the_notice_over_the_title_screen() -> void:
	await _boot()
	var card := _notice()
	assert_object(card).is_not_null()
	# OVER, not instead of: the title screen is still there underneath, and ModalCard's own
	# z_index table is what puts the card (MODAL_CARD 200) above it (MENU_SCREEN 100).
	var mc: MissionController = game.mission_controller
	assert_bool(mc.mission_select_is_up()).is_true()
	assert_int(card.card_z_index).is_greater(UiLayers.MENU_SCREEN)


func test_acknowledging_writes_the_marker_and_leaves_the_game_thawed() -> void:
	await _boot()
	var card := _notice()
	assert_object(card).is_not_null()
	_button_of(card).pressed.emit()
	await _frames(2)
	assert_object(_notice()).is_null()
	assert_bool(TelemetryStore.notice_seen()).is_true()
	# The twin of test_return_to_title_lands_on_the_menu_with_the_game_thawed: a Game left DISABLED
	# behind the title screen would never run the mission picked next.
	assert_int(game.process_mode).is_equal(Node.PROCESS_MODE_INHERIT)


func test_a_boot_after_the_notice_was_seen_shows_nothing() -> void:
	TelemetryStore.persistence_enabled = true
	TelemetryStore.mark_notice_seen()
	await _boot()
	assert_object(_notice()).is_null()
	var mc: MissionController = game.mission_controller
	assert_bool(mc.mission_select_is_up()).is_true()
	assert_int(game.process_mode).is_equal(Node.PROCESS_MODE_INHERIT)


# _on_cancel returns false, which per ModalCard's contract SWALLOWS the key. Deliberate: the button
# is the only door out of a notice somebody is meant to read.
func test_escape_does_not_get_past_the_notice() -> void:
	await _boot()
	assert_object(_notice()).is_not_null()
	await _press_escape()
	assert_object(_notice()).is_not_null()
	assert_bool(TelemetryStore.notice_seen()).is_false()


# ==============================================================================
#  Fixture
# ==============================================================================

# Both switches are set BEFORE the scene is built: game._ready DEFERS open_mission_select, so the
# card is decided a frame or two in and a switch flipped after the instantiate is already too late.
func _boot() -> void:
	TelemetryStore.persistence_enabled = true
	TelemetryNotice.enabled = true
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	add_child(_main)
	await _frames(3)
	game = _main.get_node("GameContainer/GameView/Game")


func _notice() -> TelemetryNotice:
	for node: Node in get_tree().get_nodes_in_group(ModalLock.GROUP):
		if node is TelemetryNotice:
			return node as TelemetryNotice
	return null


func _button_of(card: Node) -> Button:
	for node: Node in _descendants(card):
		if node is Button:
			return node as Button
	return null


func _descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in node.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out


# The OS-driver entry (test_modal_card_scaffold's idiom): the whole chain from the root viewport
# through the SubViewportContainer to ModalCard._input, never a direct _input call.
func _press_escape() -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_ESCAPE
	down.physical_keycode = KEY_ESCAPE
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(2)
	var up := InputEventKey.new()
	up.keycode = KEY_ESCAPE
	up.physical_keycode = KEY_ESCAPE
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _wipe() -> void:
	var dir := DirAccess.open(SCRATCH_ROOT)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
