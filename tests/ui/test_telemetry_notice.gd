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

# Captured when this script LOADS -- referencing TelemetryNotice forces its _static_init to run
# first, so this is the value a real process boots with, before any case below can move it. A
# static rather than a member: it must not depend on gdUnit4 instantiating the suite per case.
static var _enabled_at_load := TelemetryNotice.enabled

var _main: Node
var game: Node2D


func before_test() -> void:
	TelemetryStore.reset_for_test()
	TelemetryStore.root = SCRATCH_ROOT
	# The card writes a PLAYER SETTING now (#1049), so this suite owns that store's state too --
	# otherwise a name written here survives into the next suite in the same gdUnit4 process, the
	# way `enabled` would. reset_for_test leaves it in memory and off disk.
	PlayerSettings.reset_for_test()
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
	PlayerSettings.reset_for_test()


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
	TelemetryStore.mark_notice_seen(TelemetryNotice.VERSION)
	assert_bool(TelemetryNotice.should_show()).is_false()


func test_a_headless_process_is_never_due_the_notice() -> void:
	TelemetryStore.persistence_enabled = true
	TelemetryNotice.enabled = false
	# Fresh install in every other respect: the seam alone is what refuses.
	assert_int(TelemetryStore.notice_version_seen()).is_equal(0)
	assert_bool(TelemetryNotice.should_show()).is_false()


# The clause that protects the other 89 booting suites, asserted rather than restated. Case 3 above
# sets `enabled` by hand and so cannot see a _static_init that stopped clearing it; this reads the
# value the process actually booted with.
func test_a_headless_run_boots_with_the_notice_suppressed() -> void:
	if DisplayServer.get_name() != "headless":
		# An editor-panel run is not headless, so the clause under test does not apply here.
		# run_tests.ps1 and CI are both headless, which is where this is the gate.
		return
	assert_bool(_enabled_at_load).is_false()



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
	TelemetryStore.mark_notice_seen(TelemetryNotice.VERSION)
	var cfg := ConfigFile.new()
	assert_int(cfg.load(TelemetryStore.config_path())).is_equal(OK)
	assert_str(str(cfg.get_value(TelemetryStore.CONFIG_SECTION, TelemetryStore.INSTALL_ID_KEY, ""))).is_equal(id)
	assert_int(TelemetryStore.notice_version_seen()).is_equal(TelemetryNotice.VERSION)


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
	assert_int(TelemetryStore.notice_version_seen()).is_equal(TelemetryNotice.VERSION)
	# The twin of test_return_to_title_lands_on_the_menu_with_the_game_thawed: a Game left DISABLED
	# behind the title screen would never run the mission picked next.
	assert_int(game.process_mode).is_equal(Node.PROCESS_MODE_INHERIT)


# ==============================================================================
#  The version gate (#1049) -- who is due a card, and when
# ==============================================================================

# THE CASE THE WHOLE FEATURE EXISTS FOR. Every install already playing the itch demo acknowledged
# the pre-#1049 card, which wrote the retired `notice_seen` bool -- so if "has been told" stayed a
# one-way BIT, the people whose reports we cannot attribute would be exactly the people never asked
# for a name. The version gate is what reaches them.
#
# The old key is written RAW here rather than through any API, because no API writes it any more:
# what is being reproduced is a cfg on a stranger's disk, not a state this build can reach.
#
# Falsified by making should_show() ask `!= 0` instead of `< VERSION`.
func test_an_install_that_acknowledged_the_OLD_notice_is_due_the_NEW_one() -> void:
	TelemetryStore.persistence_enabled = true
	TelemetryNotice.enabled = true
	# The folder is made by hand because _write_key is what normally makes it, and this case
	# deliberately does not go through it.
	DirAccess.make_dir_recursive_absolute(TelemetryStore.root)
	var cfg := ConfigFile.new()
	cfg.set_value(TelemetryStore.CONFIG_SECTION, "notice_seen", true)
	assert_int(cfg.save(TelemetryStore.config_path())).is_equal(OK)

	assert_int(TelemetryStore.notice_version_seen()).is_equal(0)
	assert_bool(TelemetryNotice.should_show()).is_true()


# ...and the same install, once it has acknowledged THIS version, is done -- or the card would
# reappear every launch, which is the failure the version gate could plausibly have introduced.
func test_the_new_notice_settles_once_acknowledged() -> void:
	TelemetryStore.persistence_enabled = true
	TelemetryNotice.enabled = true
	TelemetryStore.mark_notice_seen(TelemetryNotice.VERSION)
	assert_bool(TelemetryNotice.should_show()).is_false()


# A version AHEAD of this build's is not "due" -- it means the player ran a newer build and came
# back. Re-showing an OLDER notice would describe terms that are no longer the ones in force.
func test_a_newer_acknowledged_version_is_not_due_the_older_card() -> void:
	TelemetryStore.persistence_enabled = true
	TelemetryNotice.enabled = true
	TelemetryStore.mark_notice_seen(TelemetryNotice.VERSION + 1)
	assert_bool(TelemetryNotice.should_show()).is_false()


# ==============================================================================
#  The name box (#1049)
# ==============================================================================

func test_acknowledging_with_a_name_stores_it() -> void:
	await _boot()
	var card := _notice()
	assert_object(card).is_not_null()
	var box := _name_box_of(card)
	assert_object(box).is_not_null()
	box.text = "Jae"
	_button_of(card).pressed.emit()
	await _frames(2)
	assert_str(_stored_name()).is_equal("Jae")
	assert_int(TelemetryStore.notice_version_seen()).is_equal(TelemetryNotice.VERSION)


# SKIPPING IS THE DEFAULT AND MUST COST NOTHING. An empty box is the anonymous answer, and it still
# settles the card -- a player who wants no name must not be asked again every launch.
func test_acknowledging_with_an_empty_box_stays_anonymous_and_still_settles() -> void:
	await _boot()
	var card := _notice()
	_button_of(card).pressed.emit()
	await _frames(2)
	assert_str(_stored_name()).is_empty()
	assert_int(TelemetryStore.notice_version_seen()).is_equal(TelemetryNotice.VERSION)


# The box starts with whatever the store already holds, so a card shown again by a future VERSION
# bump cannot blank a name the player set on the settings page. Falsified by dropping the prefill
# in _build_name_box: the acknowledge below then writes "" over "Jae".
func test_the_box_is_prefilled_so_a_later_card_cannot_blank_a_name() -> void:
	PlayerSettings.set_text(PlayerSettings.Setting.PLAYER_NAME, "Jae")
	await _boot()
	var card := _notice()
	assert_object(card).is_not_null()
	assert_str(_name_box_of(card).text).is_equal("Jae")
	_button_of(card).pressed.emit()
	await _frames(2)
	assert_str(_stored_name()).is_equal("Jae")


func test_a_boot_after_the_notice_was_seen_shows_nothing() -> void:
	TelemetryStore.persistence_enabled = true
	TelemetryStore.mark_notice_seen(TelemetryNotice.VERSION)
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
	assert_int(TelemetryStore.notice_version_seen()).is_equal(0)


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


func _name_box_of(card: Node) -> LineEdit:
	for node: Node in _descendants(card):
		if node is LineEdit:
			return node as LineEdit
	return null


# The card built WITHOUT the scene, for the cases that are about what it writes rather than about
# the boot wire. ModalCard needs a game node only when it claims the lock, and a notice does -- so
# this uses the booted one, which every caller below already has.
func _stored_name() -> String:
	return PlayerSettings.text_of(PlayerSettings.Setting.PLAYER_NAME)


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
