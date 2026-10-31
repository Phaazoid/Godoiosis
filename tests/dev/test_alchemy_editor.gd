# The Alchemy page's Substances and Reactions tabs (#1532 slice 3): each edits a COPY that Update
# writes back and Save As writes anew, with readouts drawn from the seams a cast and CI run.
#
# The content razor (tests/README.md rule 9): no case asserts what an authored substance or reaction
# SAYS. A case either holds a fixture of its own in the form (`_hold`), or takes whatever the catalog
# lists and derives every expectation from the seam under test (AlchemyFormula, CellSubstances,
# ReactionLint). Nothing is written under res://: Save As is aimed at a user:// folder, an Update at a
# user:// probe, and a press of Update is never confirmed.
extends GdUnitTestSuite

const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")
const DIR := "user://__test_alchemy_editor/"

var _subs: AlchemySubstances
var _reacts: AlchemyReactions
var _scene: Node3D
var _flipped: Substance = null   # a live catalog object a case changed, put back after


# What the pages re-read the plan through, and the board a ground Save As re-wires: counts, so a
# case can ask whether a save reached them.
class _StubSquads extends RefCounted:
	var active_squad = null

class _StubGame extends RefCounted:
	var squad_manager := _StubSquads.new()
	var terrain_states: TerrainStateManager = null
	var grid: TileMapLayer = null
	var refreshed := 0
	var dropped := 0
	func refresh_action_queue(_squad) -> void:
		refreshed += 1
	func drop_threat_field() -> void:
		dropped += 1


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_subs = AlchemySubstances.new()
	_subs.dir = DIR
	add_child(_subs)
	_reacts = AlchemyReactions.new()
	_reacts.unit_dir = DIR
	_reacts.ground_dir = DIR
	add_child(_reacts)


func after_test() -> void:
	for page: Node in [_subs, _reacts]:
		if is_instance_valid(page):
			page.free()
	if _flipped != null:
		_flipped.lends_its_parts = true
		_flipped = null
	if is_instance_valid(_scene):
		get_tree().root.remove_child(_scene)
		_scene.free()
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)
	DirAccess.remove_absolute(DIR)
	SubstanceCatalog.refresh()
	ReactionCatalog.refresh()
	TerrainReactionCatalog.refresh()
	await await_idle_frame()   # #93/#101 orphan workaround


func _stub_game(page: Node) -> _StubGame:
	var game := _StubGame.new()
	page.call("init", game)
	return game


func _dialogs(page: Node) -> Array[Node]:
	return page.find_children("*", "ConfirmationDialog", false, false)


func _free_dialogs(page: Node) -> void:
	for dialog: Node in _dialogs(page):
		dialog.free()


# The row a reflective or bespoke drawer built for `field`, by its label: the HBox holding it.
func _row(form: Node, field: String) -> HBoxContainer:
	for label: Node in form.find_children("*", "Label", true, false):
		if (label as Label).text == field.capitalize() and label.get_parent() is HBoxContainer:
			return label.get_parent() as HBoxContainer
	return null


func _ticks(row: Node) -> Array[CheckBox]:
	var out: Array[CheckBox] = []
	for node: Node in row.find_children("*", "CheckBox", true, false):
		out.append(node as CheckBox)
	return out


func _texts(nodes: Array[Node]) -> PackedStringArray:
	var out := PackedStringArray()
	for node: Node in nodes:
		out.append((node as Label).text)
	return out


# The readout grid as key -> value, its two columns read in pairs.
func _readout(page: AlchemySubstances) -> Dictionary:
	var cells := page._readout.get_children()
	var out := {}
	for i in range(0, cells.size() - 1, 2):
		out[(cells[i] as Label).text] = (cells[i + 1] as Label).text
	return out


# A compound the catalog holds that lends at least one part, found by what the code reports.
func _lending_compound() -> String:
	var catalog := SubstanceCatalog.get_all()
	for id: String in catalog:
		var substance := catalog[id] as Substance
		if substance.is_compound() and substance.lends_its_parts \
				and CellSubstances.present_from([id] as Array[String]).size() > 1:
			return id
	return ""


func _load_substance(id: String) -> void:
	_subs.picker.select(_subs._ids.find(id))
	_subs._load_selected()


# Every TileState member no authoring surface may offer, by the name its hint gives it.
func _retired_names() -> PackedStringArray:
	var out := PackedStringArray()
	for value: int in Terrain.RETIRED_STATES:
		out.append(String(Terrain.TileState.keys()[value]).capitalize())
	return out


func _live_tile_state_names() -> PackedStringArray:
	var out := PackedStringArray()
	for value: int in Terrain.TileState.values():
		if value != Terrain.TileState.NONE and not Terrain.RETIRED_STATES.has(value):
			out.append(String(Terrain.TileState.keys()[value]).capitalize())
	return out


# --- laws -----------------------------------------------------------------------------------

# Each reaction form is drawn by walking property_sections(): a field in no section is a field the
# page cannot draw, and a section naming no field draws nothing. The Substances form draws the whole
# property list, so Substance owes no sections.
func test_every_reaction_field_sits_in_exactly_one_section() -> void:
	var offenders: Array[String] = []
	for resource: Resource in [ElementalReaction.new(), TerrainReaction.new()]:
		var named: Array[String] = []
		for section: Dictionary in resource.call("property_sections"):
			for field: String in section["fields"]:
				named.append(field)
		var exported: Array[String] = []
		for prop in resource.get_property_list():
			if DevWidgets.is_exported(prop):
				exported.append(prop.name)
		for field: String in exported:
			if named.count(field) != 1:
				offenders.append("%s.%s in %d sections" % [resource.get_script().get_global_name(), field, named.count(field)])
		for field: String in named:
			if not exported.has(field):
				offenders.append("%s names '%s', no exported field" % [resource.get_script().get_global_name(), field])
	assert_array(offenders).is_empty()


# A retired TileState is a tombstone in an append-only enum, still in every hint string, so only the
# resource can say it is gone. A field holding TileStates that its property_retired() does not list
# would offer Blaze again.
func test_every_tile_state_field_declares_the_retired_states() -> void:
	var tokens := PackedStringArray()
	for value: int in Terrain.RETIRED_STATES:
		tokens.append("%s:%d" % [String(Terrain.TileState.keys()[value]).capitalize(), value])
	var offenders: Array[String] = []
	var seen := 0
	for resource: Resource in [Substance.new(), ElementalReaction.new(), TerrainReaction.new()]:
		for prop in resource.get_property_list():
			if not DevWidgets.is_exported(prop):
				continue
			for token: String in tokens:
				if not String(prop.hint_string).contains(token):
					continue
				seen += 1
				var retired := DevWidgets.retired_values(resource, prop.name)
				for value: int in Terrain.RETIRED_STATES:
					if not retired.has(value):
						offenders.append("%s.%s" % [resource.get_script().get_global_name(), prop.name])
	assert_int(seen).override_failure_message(
		"no field holds a TileState, so this law reads nothing -- did the hint format change?").is_greater(0)
	assert_array(offenders).is_empty()


# --- the pickers ----------------------------------------------------------------------------

func test_the_pickers_list_exactly_their_catalogs() -> void:
	assert_int(_subs.picker.item_count).is_equal(SubstanceCatalog.get_all().size())
	var reactions := ReactionCatalog.get_all().size() + TerrainReactionCatalog.get_all().size()
	assert_int(_reacts.picker.item_count).is_equal(reactions)
	for i in _reacts._entries.size():
		var entry: Dictionary = _reacts._entries[i]
		assert_str(_reacts.picker.get_item_text(i)).starts_with(
			AlchemyReactions.kind_of(entry["reaction"]))


# OptionButton.add_item auto-selects index 0: a re-list that names nothing must select nothing, or
# Update aims at an entry nobody picked.
func test_a_relist_naming_nothing_selects_nothing() -> void:
	_subs._refresh_list("")
	_reacts._refresh_list("")
	assert_int(_subs.picker.selected).is_equal(-1)
	assert_int(_reacts.picker.selected).is_equal(-1)
	assert_bool(_subs.update_button.disabled).is_true()


# --- a copy ---------------------------------------------------------------------------------

func test_load_is_a_copy_and_an_edit_leaves_the_catalog_alone() -> void:
	var id: String = _subs._loaded_id
	var live := SubstanceCatalog.by_id(id)
	assert_object(_subs.current).is_not_same(live)
	var was := live.formula
	DevWidgets.write(_subs.current, "formula", was + " + W2")
	assert_str(live.formula).is_equal(was)
	assert_bool(_subs.is_dirty()).is_true()
	assert_str(_subs.update_button.text).is_equal("Update *")

	var entry: Dictionary = _reacts._selected()
	var reaction := entry["reaction"] as Resource
	assert_object(_reacts.current).is_not_same(reaction)
	var popup := String(reaction.get("popup"))
	DevWidgets.write(_reacts.current, "popup", popup + "!")
	assert_str(String(reaction.get("popup"))).is_equal(popup)
	assert_bool(_reacts.is_dirty()).is_true()


# --- the substance readout ------------------------------------------------------------------

func test_the_substance_readout_is_the_seams_answer() -> void:
	var id := _lending_compound()
	assert_str(id).override_failure_message("no substance lends a part").is_not_empty()
	_load_substance(id)
	var catalog := _subs._catalog_with_copy(id)
	var shown := _readout(_subs)
	assert_str(shown["Atoms"]).is_equal(
		AlchemyFormula.format_atoms(AlchemyFormula.atoms_of(_subs.current, catalog).counts))
	for part: String in CellSubstances.present_from([id] as Array[String], catalog):
		if part != id:
			assert_str(shown["Lends"]).contains(SubstanceCatalog.name_of(part))
	var findings := ReactionLint.check_substance(_subs.current, catalog)
	if findings.is_empty():
		assert_str(shown["Lint"]).is_equal("clean")


# The tick reaches the readout with no save: off, the compound lends nothing.
func test_unticking_lends_its_parts_empties_the_lends_line() -> void:
	var id := _lending_compound()
	assert_str(id).override_failure_message("no substance lends a part").is_not_empty()
	_load_substance(id)
	DevWidgets.write(_subs.current, "lends_its_parts", false)
	assert_str(_readout(_subs)["Lends"]).starts_with("nothing")
	assert_bool(SubstanceCatalog.by_id(id).lends_its_parts).override_failure_message(
		"the tick moved the catalog's object, not the copy").is_true()


func test_a_broken_formula_shows_the_lints_blocks_line() -> void:
	DevWidgets.write(_subs.current, "formula", "W2 + __no_such_substance__")
	var findings := ReactionLint.check_substance(_subs.current, _subs._catalog_with_copy(_subs._loaded_id))
	assert_bool(findings.is_empty()).override_failure_message("the lint passed an unknown id").is_false()
	var shown := _readout(_subs)
	assert_str(shown.get("BLOCKS", "")).is_equal(findings[0]["text"])
	assert_str(shown["Atoms"]).is_equal("-")


# --- the reaction readout -------------------------------------------------------------------

func test_the_drawn_reaction_readout_is_readout_lines() -> void:
	var drawn := _texts(_reacts._equation_readout.get_children())
	var expected := PackedStringArray()
	for line: Dictionary in AlchemyReactions.readout_lines(_reacts.current):
		expected.append(line["text"])
	assert_array(Array(drawn)).is_equal(Array(expected))
	DevWidgets.write(_reacts.current, "equation", "")
	assert_array(Array(_texts(_reacts._equation_readout.get_children()))).is_equal([AlchemyReactions.NO_EQUATION])


func test_readout_lines_say_what_the_lint_says() -> void:
	var balanced := ElementalReaction.new()
	balanced.equation = "W2 -> W2"
	var unbalanced := ElementalReaction.new()
	unbalanced.equation = "W2 -> W"
	for reaction: ElementalReaction in [balanced, unbalanced]:
		var lines := PackedStringArray()
		for line: Dictionary in AlchemyReactions.readout_lines(reaction):
			lines.append(line["text"])
		var text := "\n".join(lines)
		var blocked := false
		for finding: Dictionary in ReactionLint.check(reaction):
			assert_str(text).contains(finding["text"])
			blocked = blocked or finding["severity"] == ReactionLint.Severity.BLOCKS
		assert_bool(text.contains("Balanced")).is_equal(not blocked)
	assert_bool(ReactionLint.check(unbalanced).is_empty()).override_failure_message(
		"the lint passed an unbalanced equation, so this case reads nothing").is_false()


# --- the reaction rows ----------------------------------------------------------------------

func test_ticks_offer_no_retired_state_and_no_none() -> void:
	_reacts._hold(TerrainReaction.new(), "")
	var row := _row(_reacts._form, "add_tile_states")
	assert_object(row).override_failure_message("no Add Tile States row was drawn").is_not_null()
	var offered := PackedStringArray()
	for tick: CheckBox in _ticks(row):
		offered.append(tick.text)
	assert_array(Array(offered)).is_equal(Array(_live_tile_state_names()))
	for option: Node in _reacts._form.find_children("*", "OptionButton", true, false):
		var picker := option as OptionButton
		var adds := picker.get_item_text(0).begins_with("+")
		for i in picker.item_count:
			var item := picker.get_item_text(i)
			assert_bool(_retired_names().has(item)).override_failure_message(
				"a dropdown offers retired '%s'" % item).is_false()
			if adds:
				assert_str(item).is_not_equal("None")


# A row never hides what a file stores, a retired member included.
func test_a_held_retired_state_still_shows_ticked() -> void:
	var held := TerrainReaction.new()
	held.add_tile_states.append(Terrain.RETIRED_STATES[0])
	_reacts._hold(held, "")
	var name := _retired_names()[0]
	var shown := _ticks(_row(_reacts._form, "add_tile_states")).filter(
		func(tick: CheckBox) -> bool: return tick.text == name)
	assert_int(shown.size()).is_equal(1)
	assert_bool((shown[0] as CheckBox).button_pressed).is_true()


# THE TYPED-ARRAY WIRE: ticks clicked last-first still write one typed array in the enum's order.
func test_a_tick_writes_a_typed_array_in_enum_order() -> void:
	_reacts._hold(TerrainReaction.new(), "")
	var ticks := _ticks(_row(_reacts._form, "add_tile_states"))
	assert_int(ticks.size()).override_failure_message("fewer than two ticks to order").is_greater_equal(2)
	ticks[ticks.size() - 1].button_pressed = true
	ticks[0].button_pressed = true
	var written: Array = (_reacts.current as TerrainReaction).add_tile_states
	var first: int = Terrain.TileState.get(ticks[0].text.to_upper().replace(" ", "_"))
	var last: int = Terrain.TileState.get(ticks[ticks.size() - 1].text.to_upper().replace(" ", "_"))
	assert_array(written).is_equal([first, last])
	assert_bool(written.is_typed()).is_true()
	ticks[0].button_pressed = false
	assert_array((_reacts.current as TerrainReaction).add_tile_states).is_equal([last])
	assert_bool(_reacts.is_dirty()).is_true()


func test_the_turns_map_adds_edits_and_removes_a_state() -> void:
	_reacts._hold(TerrainReaction.new(), "")
	var row := _row(_reacts._form, "add_state_turns")
	assert_object(row).override_failure_message("no Add State Turns row was drawn").is_not_null()
	var add: OptionButton = null
	for option: Node in row.find_children("*", "OptionButton", true, false):
		add = option as OptionButton
	var first_name := add.get_item_text(1)
	var key: int = Terrain.TileState.get(first_name.to_upper().replace(" ", "_"))
	add.select(1)
	add.item_selected.emit(1)
	assert_dict((_reacts.current as TerrainReaction).add_state_turns).is_equal({key: 1})
	await await_idle_frame()   # the entries redraw deferred
	var spins := row.find_children("*", "SpinBox", true, false)
	assert_int(spins.size()).is_equal(1)
	(spins[0] as SpinBox).value = 3
	assert_dict((_reacts.current as TerrainReaction).add_state_turns).is_equal({key: 3})
	for i in add.item_count:
		assert_str(add.get_item_text(i)).is_not_equal(first_name)
	var drop: Button = null
	for button: Node in row.find_children("*", "Button", true, false):
		if (button as Button).text == "x":
			drop = button as Button
	drop.pressed.emit()
	assert_dict((_reacts.current as TerrainReaction).add_state_turns).is_empty()
	assert_bool(is_instance_valid(drop)).override_failure_message(
		"the x freed itself inside its own signal (#741)").is_true()
	await await_idle_frame()
	assert_int(row.find_children("*", "SpinBox", true, false).size()).is_equal(0)


# --- Update ---------------------------------------------------------------------------------

func test_update_is_refused_until_the_picked_entry_is_loaded() -> void:
	for page: Node in [_subs, _reacts]:
		var picker: OptionButton = page.get("picker")
		assert_int(picker.item_count).override_failure_message("fewer than two entries").is_greater_equal(2)
		var other := 1 if picker.selected == 0 else 0
		picker.select(other)
		picker.item_selected.emit(other)
		assert_bool((page.get("update_button") as Button).disabled).is_true()
		page.call("_on_update_pressed")
		assert_int(_dialogs(page).size()).is_equal(0)
		assert_str((page.get("status_label") as Label).text).contains("Load")


func test_update_asks_first_and_cancel_writes_nothing() -> void:
	for page: Node in [_subs, _reacts]:
		var path: String
		if page == _subs:
			path = SubstanceCatalog.by_id(_subs._loaded_id).resource_path
		else:
			path = (_reacts._selected()["reaction"] as Resource).resource_path
		var before := FileAccess.get_file_as_string(path)
		DevWidgets.write(page.get("current"), "display_name" if page == _subs else "popup", "__edited__")
		page.call("_on_update_pressed")
		var dialogs := _dialogs(page)
		assert_int(dialogs.size()).is_equal(1)
		assert_str((dialogs[0] as ConfirmationDialog).dialog_text).contains("Overwrite")
		_free_dialogs(page)   # the dialog's No
		assert_str(FileAccess.get_file_as_string(path)).override_failure_message(
			"%s was written before Update was confirmed" % path).is_equal(before)


func test_update_refuses_a_formula_the_lint_blocks_before_asking() -> void:
	DevWidgets.write(_subs.current, "formula", "W2 + __no_such_substance__")
	_subs._on_update_pressed()
	assert_int(_dialogs(_subs).size()).is_equal(0)
	assert_str(_subs.status_label.text).starts_with("Not saved")


# A confirmed Update, aimed at a user:// probe: written through, the marker cleared, the plan re-read.
func test_a_confirmed_update_writes_and_rereads_the_plan() -> void:
	var game := _stub_game(_subs)
	var probe := DIR + "probe.tres"
	assert_int(ResourceSaver.save(_subs.current.duplicate(true), probe)).is_equal(OK)
	var held := ResourceLoader.load(probe, "", ResourceLoader.CACHE_MODE_REPLACE)
	DevWidgets.write(_subs.current, "display_name", "__edited__")
	_subs._update_confirmed(probe)
	assert_str((held as Substance).display_name).override_failure_message(
		"the save did not write through to the object a reader holds").is_equal("__edited__")
	assert_str((ResourceLoader.load(probe, "", ResourceLoader.CACHE_MODE_IGNORE) as Substance).display_name
		).is_equal("__edited__")
	assert_bool(_subs.is_dirty()).is_false()
	assert_int(game.refreshed).is_equal(1)
	assert_int(game.dropped).is_equal(1)


# --- Save As --------------------------------------------------------------------------------

func test_save_as_refuses_an_id_a_formula_could_not_name() -> void:
	var game := _stub_game(_subs)
	for chosen: String in ["Mud", "1st", "has space", "a+b", "a-b"]:
		_subs.name_input.text = chosen
		_subs._on_save_as_pressed()
		assert_str(_subs.status_label.text).override_failure_message("'%s' was taken" % chosen).contains("lower-case")
	assert_int(DirAccess.get_files_at(DIR).size()).is_equal(0)
	assert_int(game.refreshed).is_equal(0)


func test_save_as_refuses_a_broken_formula_and_an_existing_file() -> void:
	DevWidgets.write(_subs.current, "formula", "W2 + __no_such_substance__")
	_subs.name_input.text = "fresh"
	_subs._on_save_as_pressed()
	assert_str(_subs.status_label.text).starts_with("Not saved")
	assert_bool(FileAccess.file_exists(DIR + "fresh.tres")).is_false()

	assert_int(ResourceSaver.save(ElementalReaction.new(), DIR + "taken.tres")).is_equal(OK)
	var before := FileAccess.get_file_as_string(DIR + "taken.tres")
	_reacts.name_input.text = "taken"
	_reacts._on_save_as_pressed()
	assert_str(_reacts.status_label.text).contains("already exists")
	assert_str(FileAccess.get_file_as_string(DIR + "taken.tres")).is_equal(before)
	_reacts.name_input.text = "bad:name"
	_reacts._on_save_as_pressed()
	assert_str(_reacts.status_label.text).contains("can't contain")


# After a Save As the form must hold a fresh COPY: save_over hands the path to the object it saved,
# so editing that would edit the new file's live object with no save.
func test_save_as_writes_the_file_and_the_form_keeps_a_copy() -> void:
	var game := _stub_game(_subs)
	_subs.name_input.text = "fresh_substance"
	_subs._on_save_as_pressed()
	var path := DIR + "fresh_substance.tres"
	assert_bool(FileAccess.file_exists(path)).is_true()
	var saved := load(path) as Substance
	assert_object(_subs.current).is_not_same(saved)
	var was := saved.display_name
	DevWidgets.write(_subs.current, "display_name", "__after_save__")
	assert_str(saved.display_name).is_equal(was)
	assert_int(game.refreshed).is_equal(1)
	assert_int(game.dropped).is_equal(1)


func test_a_unit_save_as_reads_the_reaction_folder_again() -> void:
	_stub_game(_reacts)
	_reacts._hold(ElementalReaction.new(), "")
	var before := ReactionCatalog.scans
	_reacts.name_input.text = "fresh_unit"
	_reacts._on_save_as_pressed()
	assert_bool(FileAccess.file_exists(DIR + "fresh_unit.tres")).is_true()
	assert_int(ReactionCatalog.scans).override_failure_message(
		"a new unit reaction left the catalog answering from its old list").is_greater(before)


# game.gd composes the board's fuel source ONCE, over the list it had then; a new ground reaction must
# re-compose it. A SENTINEL the re-wire must replace, test_game_knobs's reason: two composed sources
# capture equal values and compare equal, so a before/after compare proves nothing.
func test_a_ground_save_as_reads_the_folder_again_and_rewires_the_fuel() -> void:
	var game := _stub_game(_reacts)
	game.terrain_states = auto_free(TerrainStateManager.new())
	add_child(game.terrain_states)
	game.grid = auto_free(TileMapLayer.new())
	var sentinel := func(_cell: Vector2i) -> TerrainReaction: return null
	game.terrain_states.fuel_source = sentinel
	_reacts._hold(TerrainReaction.new(), "")
	var before := TerrainReactionCatalog.scans
	_reacts.name_input.text = "fresh_ground"
	_reacts._on_save_as_pressed()
	assert_bool(FileAccess.file_exists(DIR + "fresh_ground.tres")).is_true()
	assert_int(TerrainReactionCatalog.scans).is_greater(before)
	assert_bool(game.terrain_states.fuel_source == sentinel).override_failure_message(
		"a new ground reaction left the board reading the fuel source it had before").is_false()
	assert_int(game.refreshed).is_equal(1)


# --- the dev window -------------------------------------------------------------------------

func test_the_window_hosts_three_tabs_and_sources_rereads_on_show() -> void:
	_scene = SCENE.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	var overlay := _scene.get_node("Main/DevOverlay") as DevOverlay
	var page := overlay.alchemy_tool
	overlay.show_leaf(page)
	var tabs := page._tabs
	assert_int(tabs.get_tab_count()).is_equal(3)
	assert_array([tabs.get_tab_title(0), tabs.get_tab_title(1), tabs.get_tab_title(2)]).is_equal(
		["Sources", "Substances", "Reactions"])
	# A Sources row whose readout names a part some compound in it lends, found by what the code reports.
	var catalog := SubstanceCatalog.get_all()
	var table: StringName
	var key := -1
	for field: LineEdit in page.sources._fields:
		for id: String in AlchemySources.parse_row(field.text, catalog)["ids"]:
			var substance := catalog[id] as Substance
			if _flipped == null and substance.is_compound() and substance.lends_its_parts \
					and CellSubstances.present_from([id] as Array[String]).size() > 1:
				_flipped = substance
				table = page.sources._fields[field]["table"]
				key = page.sources._fields[field]["key"]
	assert_object(_flipped).override_failure_message("no Sources row names a compound that lends").is_not_null()
	var before := _sources_readout(page.sources, table, key)
	# The object a Substances Update writes THROUGH to (DevWidgets.save_over), moved as that write would.
	_flipped.lends_its_parts = false
	page.show_tab(page.substances)
	page.show_tab(page.sources)
	assert_str(_sources_readout(page.sources, table, key)).override_failure_message(
		"Sources went on showing what it read before the Substances tab changed a tick").is_not_equal(before)


func _sources_readout(sources: AlchemySources, table: StringName, key: int) -> String:
	for field: LineEdit in sources._fields:
		if sources._fields[field]["table"] == table and sources._fields[field]["key"] == key:
			return sources._readouts[field].text
	return ""
