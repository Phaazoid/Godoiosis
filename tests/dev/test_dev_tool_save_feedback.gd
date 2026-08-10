# #168: a dev-tool Save As with an illegal character (a backslash, reported) used to fail with no
# on-screen feedback -- push_warning/push_error only reach the editor's Output panel, invisible in
# the running game where these tools actually live. DevWidgets.refuse_existing_file had the same
# blind spot.
#
# No case here reaches ResourceSaver.save -- every one stays on the refusal side of a gate, which
# returns before any disk write. Matches this project's own "no real disk writes in tests"
# convention (tests/flow/test_scenario_round_trip.gd: capture/apply in memory, never
# save_scenario/load_scenario).
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
