# The Item Editor's vial mode (#791): a VialData is authored in the tab that authors carried things,
# rather than hand-typed as a .tres. Pins what is a decision rather than plumbing: the blank entry
# authors a vial, Load lists the vials and hands out a COPY, a new vial is saved beside the others,
# and the substance is picked from the LIBRARY as a reference -- never a fresh inline Substance.
#
# No case writes to disk (test_prototype_editor's rule): the save folder is asserted at the
# predicate, and the substance pick at the object it leaves on the vial.
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
	overlay = game.dev_overlay
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()   # gdUnit4 6.2.1's false orphans; retired with the rest by #482
	get_tree().root.remove_child(_main)
	_main.free()


func _tool() -> ItemEditorTool:
	return overlay.get_node("%Item Editor")


func _new_vial() -> VialData:
	var tool_ref := _tool()
	tool_ref._rebase_on_type(tool_ref._base_catalog().keys().find(ItemEditorTool.NEW_VIAL_KEY))
	return tool_ref.current_item as VialData


# The OptionButton in the row whose label reads `label`, found by walking the built form.
func _find_option(node: Node, label: String) -> OptionButton:
	if node is HBoxContainer:
		var has_label := false
		for child in node.get_children():
			if child is Label and (child as Label).text == label:
				has_label = true
		if has_label:
			for child in node.get_children():
				if child is OptionButton:
					return child as OptionButton
	for child in node.get_children():
		var found := _find_option(child, label)
		if found != null:
			return found
	return null


func test_the_blank_vial_entry_authors_a_vial() -> void:
	var tool_ref := _tool()
	tool_ref._rebase_on_type(tool_ref._base_catalog().keys().find(ItemEditorTool.NEW_VIAL_KEY))
	# The tool's own untyped field, so the `is` check is not made vacuous by a typed local.
	var made: Resource = tool_ref.current_item
	assert_bool(made is VialData).override_failure_message("the blank vial entry built no vial").is_true()


func test_load_lists_every_vial_and_hands_out_a_copy() -> void:
	var tool_ref := _tool()
	var vials := VialCatalog.get_variants()
	if vials.is_empty():   # content-absent: warn, never fail (tests/README.md rule 9)
		push_warning("no vials on disk, so there is nothing to load")
		return
	tool_ref._refresh_variant_list()
	for vial_name: String in vials:
		assert_bool(tool_ref._variants.has(vial_name)).override_failure_message(
				"Load does not list the vial '%s'" % vial_name).is_true()
	var first: Resource = vials.values()[0]
	var copy: Resource = tool_ref._editable_copy(first)
	assert_object(copy).override_failure_message(
			"Load handed out the catalog's live vial, so an unsaved edit would reach every holder").is_not_same(first)
	assert_bool(copy is VialData).is_true()


func test_a_new_vial_is_saved_beside_the_others() -> void:
	assert_str(_tool()._save_dir_for(VialData.new())).is_equal(VialCatalog.VARIANT_DIR)


# THE case. The pick lands the LIBRARY's own object on the vial, which carries its path and therefore
# saves as a reference; a fresh Substance would carry none and save inline.
func test_the_substance_is_picked_from_the_library_by_reference() -> void:
	var substances := SubstanceCatalog.get_all()
	if substances.is_empty():
		push_warning("no substances on disk, so there is nothing to pick")
		return
	var vial := _new_vial()
	var tool_ref := _tool()
	var option := _find_option(tool_ref.editor_container, "Substance")
	assert_object(option).override_failure_message("the vial form draws no Substance picker").is_not_null()
	var wanted: Substance = substances.values()[0]
	var index := -1
	for i in option.item_count:
		if option.get_item_text(i).ends_with("(%s)" % substances.keys()[0]) \
				or option.get_item_text(i) == substances.keys()[0]:
			index = i
	assert_int(index).override_failure_message("the picker does not offer the library's substances").is_not_equal(-1)
	option.select(index)
	option.item_selected.emit(index)
	assert_object(vial.substance).override_failure_message(
			"the pick did not land the library's own substance on the vial").is_same(wanted)
	assert_str(vial.substance.resource_path).override_failure_message(
			"the picked substance has no path, so it would save inline").is_not_empty()
