# A rune holds the LIBRARY carving itself, never a copy (#1313). Every rune once held its own copy:
# the Item Editor's Inscribe duplicated the library carving, a scenario snapshot copied the rune
# again, and nothing referenced Resources/TransmutationData/ at all -- so a library edit reached
# no rune and no board, and 18 of 37 shipped copies had drifted from their library file.
#
# Each case follows the carving down one door a rune passes through -- inscribing, granting, a
# scenario capture and apply, and a save -- and asks it is still the library object. The copy case
# also pins the engine fact underneath (duplicate(true) shares a path'd resource held inside an
# exported Array), which the Character Editor and the Roster tool rely on as well.
#
# It loads library carvings to exercise the real path and asserts nothing about which carvings
# exist or what they hold (tests/README.md rule 9); an empty library warns and passes.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const EMBEDDED := preload("res://tests/law/test_no_embedded_carvings.gd")
const MAIN_SCENE := "res://Scenes/Main.tscn"
const SAVE_PATH := "user://__test_carving_reference.tres"


# Any library carving, or null (with a warning) when the library is empty.
func _library_carving() -> TransmutationData:
	var carvings := TransmutationCatalog.get_all()
	if carvings.is_empty():
		push_warning("no carvings in the library, so there is nothing to reference")
		return null
	return carvings.values()[0] as TransmutationData


# A large blank rune holding `carving`: large enough for any legal carving, and blank so the temper
# rule cannot refuse it.
func _rune_holding(carving: TransmutationData) -> RuneData:
	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	assert_bool(rune.inscribe(carving)).override_failure_message(
		"a blank large rune refused '%s', so this fixture cannot stand" % carving.display_name).is_true()
	return rune


func after_test() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func test_inscribing_holds_the_library_carving_itself() -> void:
	var carvings := TransmutationCatalog.get_all()
	if carvings.is_empty():
		push_warning("no carvings in the library, so there is nothing to inscribe")
		return
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	main.name = "Main"
	get_tree().root.add_child(main)
	await await_idle_frame()
	var game: Node = main.get_node("GameContainer/GameView/Game")
	var editor: ItemEditorTool = (game.dev_overlay as DevOverlay).get_node("%Item Editor")
	var bases := editor._base_catalog()
	var large_key := ""
	for key: String in bases:
		var base := bases[key] as RuneData
		if base != null and base.size == RuneData.Size.LARGE:
			large_key = key
	editor._rebase_on_type(bases.keys().find(large_key))
	var rune := editor.current_item as RuneData

	var picker := _find_button_row(editor.editor_container, "Inscribe")
	assert_object(picker).override_failure_message("the rune editor drew no Inscribe row").is_not_null()
	var chosen: String = (picker.get_child(0) as OptionButton).get_item_text(0)
	(picker.get_child(0) as OptionButton).select(0)
	(picker.get_child(1) as Button).pressed.emit()

	assert_int(rune.inscriptions.size()).is_equal(1)
	assert_object(rune.inscriptions[0]).override_failure_message(
		"Inscribe put a COPY of '%s' on the rune, so a library edit would never reach it" % chosen
	).is_same(carvings[chosen])
	get_tree().root.remove_child(main)
	main.free()


# The HBoxContainer holding a button labelled `text`, found by walking the built form.
func _find_button_row(node: Node, text: String) -> HBoxContainer:
	if node is HBoxContainer:
		for child in node.get_children():
			if child is Button and not child is OptionButton and (child as Button).text == text:
				return node as HBoxContainer
	for child in node.get_children():
		var found := _find_button_row(child, text)
		if found != null:
			return found
	return null


func test_granting_a_rune_keeps_its_carving_shared() -> void:
	var carving := _library_carving()
	if carving == null:
		return
	var rune := _rune_holding(carving)

	var granted := rune.copy_for_grant() as RuneData

	assert_object(granted).is_not_same(rune)
	assert_object(granted.inscriptions[0]).override_failure_message(
		"granting a rune copied its library carving: duplicate(true) no longer shares a path'd "
		+ "resource inside an exported Array, so every grant would fork the carving again"
	).is_same(carving)


func test_a_units_rune_keeps_its_carving_through_capture_and_apply() -> void:
	var carving := _library_carving()
	if carving == null:
		return
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	assert_bool(a.add_item(_rune_holding(carving))).is_true()

	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(a)
	var b: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(9, 9), {}, false)
	entry.apply_unit_state(b)

	var held: RuneData = null
	for item: Item in b.inventory:
		if item is RuneData:
			held = item as RuneData
	assert_object(held).override_failure_message("the loaded unit carries no rune").is_not_null()
	assert_object(held.inscriptions[0]).override_failure_message(
		"a scenario round trip copied the rune's library carving").is_same(carving)


# The wire: what a save actually WRITES. A shared carving serializes as a reference to its library
# file; a copy would come back as an inline sub_resource, which is how every embedded copy shipped.
func test_a_saved_rune_names_its_library_carving_instead_of_embedding_it() -> void:
	var carving := _library_carving()
	if carving == null:
		return
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	assert_bool(a.add_item(_rune_holding(carving))).is_true()
	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(a)

	assert_int(ResourceSaver.save(entry, SAVE_PATH)).is_equal(OK)
	var text := FileAccess.get_file_as_string(SAVE_PATH)

	assert_bool(text.contains('path="%s"' % carving.resource_path)).override_failure_message(
		"the saved rune does not name '%s' as an ext_resource" % carving.resource_path).is_true()
	# Counted by the law's own detector: the typed inscriptions array names the carving script in its
	# type even when every element is a reference, so "is the script named" cannot tell them apart.
	assert_int(EMBEDDED.embedded_carvings(text)).override_failure_message(
		"the saved rune embeds a carving copy:\n%s" % text).is_equal(0)
