# #168: a dev-tool Save As with an illegal character (a backslash, reported) used to fail with no
# on-screen feedback -- push_warning/push_error only reach the editor's Output panel, invisible in
# the running game where these tools actually live. DevWidgets.refuse_existing_file had the same
# blind spot.
#
# No case here ever writes a byte to disk. Most stay on the refusal side of a gate, which returns
# before any disk write; the two error-path cases DO reach ResourceSaver.save, but only with a path
# whose base "directory" is an existing FILE -- a save that fails deterministically on every
# platform (you can't create a directory where a file sits, on Windows or Linux) with nothing
# written. That platform-independence is load-bearing: a backslash name, the obvious failure
# forcer, saves LEGALLY on Linux and would have left CI green-writing junk files. Matches this
# project's "no real disk writes in tests" convention (tests/flow/test_scenario_round_trip.gd:
# capture/apply in memory).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const CHAINSWORD_PATH := "res://Resources/Weapons/MainVarieties/ChainSword.tres"

var _main: Node
var game: Node2D
var overlay: DevOverlay


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	overlay = game.dev_overlay
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


# ==============================================================================
#  DevWidgets.refuse_illegal_name -- pure logic, no scene needed beyond the fixture above
# ==============================================================================

func test_every_banned_character_is_refused_and_named_in_the_label() -> void:
	for c in DevWidgets.ILLEGAL_NAME_CHARS:
		var label := Label.new()
		var refused := DevWidgets.refuse_illegal_name("na%sme" % c, "item", label)
		assert_bool(refused).override_failure_message("'%s' was not refused" % c).is_true()
		assert_str(label.text).override_failure_message("refusing '%s' left the label empty" % c) \
			.contains(c)
		label.free()


func test_a_clean_name_is_not_refused() -> void:
	var label := Label.new()
	var refused := DevWidgets.refuse_illegal_name("Perfectly Fine Name", "item", label)
	assert_bool(refused).is_false()
	assert_str(label.text).is_empty()
	label.free()


# The asymmetry that matters: '/' is banned for the flat item/attack catalogs (a file a scan will
# never find again) but a real, working feature for scenario subfolders (Scenarios/fixtures/). A
# future "just call it the same way everywhere" edit is exactly what would silently break that.
func test_slash_is_banned_by_default_and_allowed_for_scenarios() -> void:
	assert_bool(DevWidgets.refuse_illegal_name("fixtures/Foo", "item")).is_true()
	assert_bool(DevWidgets.refuse_illegal_name("fixtures/Foo", "scenario", null, true)).is_false()


# An allowed '/' still has to spell an honest subfolder: '../Foo' lands OUTSIDE Scenarios/ where
# the recursive scan never looks (#168's symptom, one level up), and empty/'.' segments degenerate
# the filename ('foo/' saves a file literally named '.tres').
func test_a_permitted_slash_refuses_traversal_and_degenerate_segments() -> void:
	for bad in ["../Foo", "foo//bar", "foo/", "fixtures/./Foo"]:
		assert_bool(DevWidgets.refuse_illegal_name(bad, "scenario", null, true)) \
			.override_failure_message("'%s' was not refused for a scenario" % bad).is_true()
	assert_bool(DevWidgets.refuse_illegal_name("missions/Prolog2", "scenario", null, true)).is_false()


# ==============================================================================
#  DevWidgets.refuse_existing_file -- the OTHER refusal the issue named as having the same gap
# ==============================================================================

func test_an_existing_file_refusal_reaches_the_label() -> void:
	var label := Label.new()
	var refused := DevWidgets.refuse_existing_file(CHAINSWORD_PATH, "item", label)
	assert_bool(refused).is_true()
	assert_str(label.text).contains("already exists")
	label.free()


# ==============================================================================
#  save_over's ERROR path reaches the label -- and save_scenario now rides it (the de-dup).
#  Both use a base "directory" that is an existing FILE: the one save that fails on every
#  platform with zero bytes written (see the header).
# ==============================================================================

func test_a_failed_save_reaches_the_label() -> void:
	var label := Label.new()
	var saved := DevWidgets.save_over(Resource.new(), CHAINSWORD_PATH + "/nope.tres", label)
	assert_bool(saved).is_false()
	assert_str(label.text).contains("Failed to save")
	label.free()


# The wire (#168 follow-up): save_scenario used to hand-copy save_over's body, so its own disk
# failure could never reach the label the tool now shows. This drives the REAL method and asserts
# both halves of the de-dup: the message lands, and last_loaded_path doesn't move on failure.
func test_a_failed_scenario_save_reaches_the_label() -> void:
	var label := Label.new()
	var manager: ScenarioManager = game.scenario_manager
	var before: String = manager.last_loaded_path

	manager.save_scenario("missions/Prolog.tres/x", label)

	assert_str(label.text) \
		.override_failure_message("a failed scenario save left the tool's label empty").contains("Failed to save")
	assert_str(manager.last_loaded_path) \
		.override_failure_message("last_loaded_path moved on a save that never landed").is_equal(before)
	label.free()


# ==============================================================================
#  The wire: pressing the real Save As button on each real tool leaves ITS OWN status label
#  non-empty. Reused fixture, one case per tool -- proves the button->handler->gate->label path
#  the issue was actually filed about, not just the gate function in isolation.
# ==============================================================================

func test_item_editor_save_as_shows_the_refusal() -> void:
	var tool: ItemEditorTool = overlay.get_node("%Item Editor")
	tool.name_input.text = "bad\\name"
	tool.get_node("VBoxContainer/NewRow/SaveAsItemButton").pressed.emit()

	assert_str(tool.status_label.text) \
		.override_failure_message("Item Editor's Save As left no visible feedback for an illegal name").is_not_empty()


func test_attack_editor_save_as_shows_the_refusal() -> void:
	# Not %-reachable -- unlike the "Item Editor" tab node, "Attack Editor" was never marked
	# unique_name_in_owner, so this goes structural instead of expanding the scene diff for it.
	var tool: AttackEditorTool = overlay.get_node("Panel/MarginContainer/VBoxContainer/DevTabs/Attack Editor")
	tool.name_input.text = "bad\\name"
	tool.save_as_button.pressed.emit()

	assert_str(tool.status_label.text) \
		.override_failure_message("Attack Editor's Save As left no visible feedback for an illegal name").is_not_empty()


func test_scenario_tool_save_as_shows_the_refusal() -> void:
	var tool := overlay.scenario_tool
	tool.scenario_name_input.text = "bad\\name"
	tool.get_node("NewRow/SaveAsScenarioButton").pressed.emit()

	assert_str(tool.status_label.text) \
		.override_failure_message("Scenario tool's Save As left no visible feedback for an illegal name").is_not_empty()
