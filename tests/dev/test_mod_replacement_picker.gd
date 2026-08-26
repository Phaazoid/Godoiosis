# The mod editor's "Replaces main" picker (#529) -- the WIRE, which is the #103 shape: the model
# side is pinned next door in tests/weapons/test_main_replacement.gd, and a rule can be correct at
# both ends while nothing connects it to the panel.
#
# The picker exists at all because a lone object @export would auto-render through
# build_resource_editor's resource swapper, which nests a LIVE editor for the attack it points at
# -- making the mod panel a back door into content the Attack Editor owns.
#
# The catalog is real authored content, so nothing here asserts what it holds: the attack each
# case picks is derived from the picker's own entries, with a non-vacuity message where a claim
# needs the catalog to be a certain shape at all (the content razor).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

var _main: Node
var game: Node2D
var overlay: DevOverlay

func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	overlay = game.dev_overlay
	await await_idle_frame()

func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()

func _controls(node: Node, type_name: String, found: Array) -> Array:
	for child in node.get_children():
		if child.is_class(type_name):
			found.append(child)
		_controls(child, type_name, found)
	return found

func _show(mod: WeaponModData) -> ItemEditorTool:
	var tool_ref: ItemEditorTool = overlay.get_node("%Item Editor")
	tool_ref.current_item = mod
	tool_ref.populate()
	return tool_ref

# The mod panel now draws several dropdowns (family, applies-to, element, ally splash), so the
# replacement one is found by the entry only it carries rather than by position.
func _replacement_picker(tool_ref: ItemEditorTool) -> OptionButton:
	for control in _controls(tool_ref.editor_container, "OptionButton", []):
		var option := control as OptionButton
		for i in option.item_count:
			if option.get_item_text(i) == ItemEditorTool.NO_REPLACEMENT_KEY:
				return option
	return null

func test_picking_an_attack_stores_it_as_the_replacement() -> void:
	var mod := WeaponModData.new()
	var tool_ref := _show(mod)
	var picker := _replacement_picker(tool_ref)
	assert_object(picker).is_not_null()

	# Any entry that is not the "leave it alone" one -- which attack it is does not matter.
	var pick := -1
	for i in picker.item_count:
		if picker.get_item_text(i) != ItemEditorTool.NO_REPLACEMENT_KEY:
			pick = i
			break
	assert_int(pick) \
		.override_failure_message("the attack catalog is empty, so this picker cannot be exercised") \
		.is_greater(-1)

	picker.item_selected.emit(pick)
	assert_object(mod.replaces_main).is_not_null()
	assert_str(mod.replaces_main.display_name).is_not_empty()

func test_choosing_the_weapons_own_clears_a_replacement() -> void:
	var mod := WeaponModData.new()
	var tool_ref := _show(mod)
	var picker := _replacement_picker(tool_ref)
	for i in picker.item_count:
		if picker.get_item_text(i) != ItemEditorTool.NO_REPLACEMENT_KEY:
			picker.item_selected.emit(i)
			break
	assert_object(mod.replaces_main) \
		.override_failure_message("nothing was set, so clearing it below would prove nothing") \
		.is_not_null()

	# populate() rebuilt the panel when the pick landed, so the picker has to be found again.
	picker = _replacement_picker(_show(mod))
	for i in picker.item_count:
		if picker.get_item_text(i) == ItemEditorTool.NO_REPLACEMENT_KEY:
			picker.item_selected.emit(i)
			break
	assert_object(mod.replaces_main).is_null()
