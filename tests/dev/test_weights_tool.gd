# The Weights tab (#120 PR 3): every body's BLD and every item's weight on one page.
#
# Two kinds of case. The page's LAWS -- every authored file gets a row, a composed weapon gets no
# spinbox -- read the real catalogs and assert nothing about what they hold (the content razor).
# Its WIRES drive a real SpinBox through `value`, which emits value_changed exactly as a drag does,
# and assert on the live resource and on the readout a dev would be looking at.
#
# The catalog resources are process-global (the resource cache), so every case that moves one puts
# it back in after_test through the page's own Reset -- a leaked weight would reach every later suite.
# The one case that SAVES writes a user:// probe, never a shipped file.
extends GdUnitTestSuite

const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")
const PROBE_PATH := "user://__test_weights_tool.tres"

var _tool: WeightsTool
var _scene: Node3D


func before_test() -> void:
	_tool = WeightsTool.new()
	add_child(_tool)


func after_test() -> void:
	if is_instance_valid(_tool):
		_tool._on_reset_pressed()
		_tool.free()
	if is_instance_valid(_scene):
		(_scene.get_node("Main/DevOverlay") as DevOverlay).weights_tool._on_reset_pressed()
		get_tree().root.remove_child(_scene)
		_scene.free()
	if FileAccess.file_exists(PROBE_PATH):
		DirAccess.remove_absolute(PROBE_PATH)
	await await_idle_frame()   # #93/#101 orphan workaround


# Every label on the page names its file in its tooltip, so "does this file have a row" is a walk.
func _row_paths(page: Node) -> Dictionary:
	var paths := {}
	for node: Node in page.find_children("*", "Label", true, false):
		var tip := (node as Label).tooltip_text
		if tip.begins_with("res://"):
			paths[tip] = true
	return paths


# --- laws -----------------------------------------------------------------------------------

func test_every_character_item_and_mod_has_a_row() -> void:
	var expected: Array[Resource] = []
	expected.append_array(UnitCatalog.get_characters_by_file().values())
	for dir: String in ItemCatalog.SOURCES:
		expected.append_array(ResourceCatalog.by_file(dir, Item).values())
	expected.append_array(ResourceCatalog.by_file(WeaponModCatalog.MOD_DIR, WeaponModData).values())
	assert_int(expected.size()).override_failure_message(
		"no catalog returned anything, so this law checks nothing").is_greater(0)
	var listed := _row_paths(_tool)
	for res: Resource in expected:
		assert_bool(listed.has(res.resource_path)).override_failure_message(
			"%s has no row on the Weights page" % res.resource_path).is_true()


# A saved weapon's weight is family + its own + fitted mods; a spinbox would edit one of three terms
# and read as editing the total.
func test_a_composed_weapon_is_shown_but_not_editable() -> void:
	var saved := ResourceCatalog.by_file(WeaponCatalog.SAVED_DIR, Item).values()
	assert_int(saved.size()).override_failure_message(
		"no saved weapon variant exists, so this law checks nothing").is_greater(0)
	for item: Item in saved:
		if item is WeaponInstance:
			assert_bool(_tool._spins.has(item)).override_failure_message(
				"%s is composed but drew a spinbox" % item.resource_path).is_false()


# --- wires ----------------------------------------------------------------------------------

# A carried item's weight moves the readout of the character carrying it: the page's whole point is
# seeing one file's number land on another file's total.
func test_an_item_spinbox_moves_the_live_item_and_its_carriers_readout() -> void:
	var pick := _a_character_carrying_an_editable_item()
	assert_bool(pick.is_empty()).override_failure_message(
		"no character carries an item with a spinbox, so this case measures nothing").is_false()
	var carrier: UnitData = pick["carrier"]
	var item: Item = pick["item"]
	var before := item.weight
	_tool._spins[item].value = before + 5
	assert_int(item.weight).is_equal(before + 5)
	var total := WeightsTool.value_of(carrier) + Item.total_weight(carrier.starting_inventory)
	assert_str(_tool._readouts[carrier].text).contains("WT %d," % total)
	assert_str(_tool._save_button.text).is_equal("Save *")
	assert_array(Array(_tool.touched_files())).contains([item.resource_path])


func test_a_body_spinbox_moves_bld_and_the_band_it_lands_in() -> void:
	var by_file := UnitCatalog.get_characters_by_file()
	assert_int(by_file.size()).is_greater(0)
	var data: UnitData = by_file.values()[0]
	var carried := Item.total_weight(data.starting_inventory)
	var body := maxi(0, Stats.WEIGHT_BAND_2 - carried)
	_tool._spins[data].value = body
	assert_int(int(data.base_stats[Stats.Stat.BLD])).is_equal(body)
	assert_str(_tool._readouts[data].text).contains("band %d" % Stats.weight_band(body + carried))


# Reset puts a sparse stat back as ABSENT rather than as its default written out, so a character
# that never authored BLD keeps not authoring it. An in-memory body: every shipped character may
# author BLD, and this branch must stay measurable whatever the cast does.
func test_reset_restores_what_was_saved_including_an_unauthored_body() -> void:
	var unauthored := UnitData.new()
	assert_bool(unauthored.base_stats.has(Stats.Stat.BLD)).is_false()
	_tool.edit(unauthored, 3)
	assert_bool(unauthored.base_stats.has(Stats.Stat.BLD)).is_true()
	_tool._on_reset_pressed()
	assert_bool(unauthored.base_stats.has(Stats.Stat.BLD)).override_failure_message(
		"Reset wrote the default out instead of putting the unauthored stat back").is_false()
	assert_str(_tool._save_button.text).is_equal("Save")


func test_save_writes_the_touched_file_and_clears_the_marker() -> void:
	var probe := _staged_probe(3)
	_tool.edit(probe, 7)
	assert_array(Array(_tool.touched_files())).is_equal([PROBE_PATH])
	_tool.save_touched()
	var on_disk := ResourceLoader.load(PROBE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as Item
	assert_int(on_disk.weight).is_equal(7)
	assert_bool(_tool.is_dirty()).is_false()
	assert_str(_tool._save_button.text).is_equal("Save")


# #380: a save that overwrites asks first, and the ask names what it will write.
func test_save_asks_first_and_names_the_files() -> void:
	var probe := _staged_probe(3)
	_tool.edit(probe, 4)
	_tool._on_save_pressed()
	var dialogs := _tool.find_children("*", "ConfirmationDialog", false, false)
	assert_int(dialogs.size()).is_equal(1)
	assert_str((dialogs[0] as ConfirmationDialog).dialog_text).contains(PROBE_PATH.trim_prefix("res://"))
	var on_disk := ResourceLoader.load(PROBE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as Item
	assert_int(on_disk.weight).override_failure_message("the save ran before it was confirmed").is_equal(3)
	dialogs[0].free()


func test_save_with_nothing_touched_says_so_and_asks_nothing() -> void:
	_tool._on_save_pressed()
	assert_int(_tool.find_children("*", "ConfirmationDialog", false, false).size()).is_equal(0)
	assert_str(_tool._status.text).is_equal("Nothing has moved off what is saved.")


# The Item and Character pages write the same live resources. Showing this page must re-read them,
# or its spinbox says one number while the board uses another.
func test_showing_the_page_rereads_a_weight_another_page_changed() -> void:
	_scene = SCENE.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	var overlay := _scene.get_node("Main/DevOverlay") as DevOverlay
	var page := overlay.weights_tool
	var item: Item = null
	for res: Resource in page._spins:
		if res is Item:
			item = res
			break
	assert_object(item).override_failure_message("the page drew no item rows").is_not_null()
	overlay.show_leaf(page)
	page.edit(item, item.weight)   # touched through the page, so after_test's Reset puts it back
	overlay.show_leaf(overlay.game_tool)
	item.weight += 9   # what another page's save does to the live object
	overlay.show_leaf(page)
	assert_int(int(page._spins[item].value)).is_equal(item.weight)


func _a_character_carrying_an_editable_item() -> Dictionary:
	for data: UnitData in UnitCatalog.get_characters_by_file().values():
		for item: Item in data.starting_inventory:
			if item != null and _tool._spins.has(item):
				return {"carrier": data, "item": item}
	return {}


func _staged_probe(weight: int) -> Item:
	var seed_item := Item.new()
	seed_item.display_name = "Weights Probe"
	seed_item.weight = weight
	assert_int(ResourceSaver.save(seed_item, PROBE_PATH)).is_equal(OK)
	return load(PROBE_PATH) as Item
