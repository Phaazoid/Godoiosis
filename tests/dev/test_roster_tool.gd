# The roster editor (#812): what a mission OFFERS, edited rather than hand-authored in Godot's
# inspector. Three columns, each the whole catalogue with the chosen floated above a rule.
#
# The cases drive the TOOL -- a real instance, its own rows' toggles -- rather than the model
# underneath, because the model half was already shipped by #735 and what this ticket adds is the
# surface. Where a case can only reach the model it says so.
#
# Nothing here pins authored content (the razor): every case builds its own roster in memory and
# saves to user://, and the catalogue reads are preconditions rather than assertions.
extends GdUnitTestSuite

const OVERLAY := "res://Scenes/DevOverlay.tscn"
const SCRATCH_DIR := "user://__roster_tool_812/"

var _overlay: Window
var tool_page: RosterTool


func before_test() -> void:
	_overlay = (load(OVERLAY) as PackedScene).instantiate()
	get_tree().root.add_child(_overlay)
	await await_idle_frame()
	tool_page = _overlay.get_node("%Rosters")


func after_test() -> void:
	get_tree().root.remove_child(_overlay)
	_overlay.free()
	await await_idle_frame()
	_wipe_scratch()


static func _wipe_scratch() -> void:
	if not DirAccess.dir_exists_absolute(SCRATCH_DIR):
		return
	for file in DirAccess.get_files_at(SCRATCH_DIR):
		DirAccess.remove_absolute(SCRATCH_DIR + file)


# The first character on disk, or null -- a content precondition, never an assertion about who the
# cast holds.
func _a_character() -> UnitData:
	var characters := UnitCatalog.get_characters_by_file()
	for key: String in characters:
		return characters[key]
	return null


func _an_item() -> Item:
	for item: Item in ItemCatalog.everything():
		return item
	return null


func _a_mod() -> WeaponModData:
	var mods := WeaponModCatalog.get_mods()
	for key in mods:
		return mods[key]
	return null


# Every CheckBox and SpinBox the page has built, in column order -- what a click would reach.
func _rows_of(column: int) -> Array[Control]:
	var found: Array[Control] = []
	var pools: HBoxContainer = _overlay.get_node("%RosterPools")
	if column >= pools.get_child_count():
		return found
	_collect(pools.get_child(column), found)
	return found


func _collect(node: Node, into: Array[Control]) -> void:
	for child in node.get_children():
		if child is CheckBox or child is SpinBox:
			into.append(child)
		_collect(child, into)


# The row whose label names this file, in the given column. The toggle at the TOP of a column is
# the "offer everything" one and is deliberately skipped -- it is not a row.
func _row_for(column: int, needle: String) -> Control:
	for row: Control in _rows_of(column):
		if row is CheckBox and (row as CheckBox).text.contains(needle):
			return row
	return null


# The "offer everything" toggle of a column -- the control, not the field. A case that writes the
# flag directly cannot see anything the toggle's own handler does, which is how a mutant that
# emptied the list on the way past went green.
func _toggle_of(column: int) -> CheckBox:
	for row: Control in _rows_of(column):
		if row is CheckBox and (row as CheckBox).text.begins_with("Offer every"):
			return row
	return null


# --- units ---

func test_ticking_a_character_adds_a_reference_entry() -> void:
	var character := _a_character()
	if character == null:
		push_warning("no characters are authored, so the units column cannot be exercised")
		return
	var file: String = character.resource_path.get_file().get_basename()
	tool_page._on_new_pressed()
	await await_idle_frame()

	var row := _row_for(0, file) as CheckBox
	assert_object(row).override_failure_message(
		"the units column did not list an authored character").is_not_null()
	row.button_pressed = true   # emits toggled, which is the tool's own door
	await await_idle_frame()

	assert_int(tool_page.current.entries.size()).is_equal(1)
	var entry: ScenarioUnitEntry = tool_page.current.entries[0]
	assert_object(entry.unit_data).override_failure_message(
		"the entry copied the character instead of referencing the file").is_same(character)
	assert_bool(entry.state_saved).override_failure_message(
		"the tool authored a SNAPSHOT entry, which deploys the character naked and jobless"
		).is_false()


func test_unticking_a_chosen_character_removes_it() -> void:
	var character := _a_character()
	if character == null:
		return
	tool_page._on_new_pressed()
	tool_page._add_character(character)
	tool_page._rebuild()
	await await_idle_frame()

	var file: String = character.resource_path.get_file().get_basename()
	var row := _row_for(0, file) as CheckBox
	assert_object(row).is_not_null()
	row.button_pressed = false
	await await_idle_frame()

	assert_array(tool_page.current.entries).is_empty()


# --- the stash is a MULTISET ---

# A tick cannot say "two Fire Vials", so the stash column counts. Without this the tool would drop
# a duplicate on the next Update -- silently, and only visible a mission later.
func test_a_duplicate_stash_item_survives_a_round_trip() -> void:
	var item := _an_item()
	if item == null:
		push_warning("no items are authored, so the stash column cannot be exercised")
		return
	tool_page._on_new_pressed()
	tool_page._set_stash_count(item, 2)
	assert_int(tool_page.current.stash.size()).override_failure_message(
		"the count did not put two of the item in the stash").is_equal(2)

	var path := SCRATCH_DIR + "dupe.tres"
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	assert_int(ResourceSaver.save(tool_page.current, path)).is_equal(OK)
	var reloaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Roster

	assert_int(reloaded.stash.size()).override_failure_message(
		"a duplicate stash entry was dropped by the round trip").is_equal(2)


func test_setting_a_count_to_zero_takes_the_item_out() -> void:
	var item := _an_item()
	if item == null:
		return
	tool_page._on_new_pressed()
	tool_page._set_stash_count(item, 3)
	tool_page._set_stash_count(item, 0)
	assert_array(tool_page.current.stash).is_empty()


# --- what a saved roster actually WRITES ---

# THE ONE THAT MATTERS MOST AND LOOKS LEAST LIKE IT. A pick stored as a COPY serializes INLINE as a
# sub_resource rather than as an ext_resource, which forks the content silently -- nothing is red,
# nothing is visibly wrong, and the roster stops tracking the file months later. Read as TEXT,
# because that is the only place the distinction exists.
func test_a_saved_roster_references_its_picks_instead_of_embedding_them() -> void:
	var character := _a_character()
	var item := _an_item()
	if character == null or item == null:
		return
	tool_page._on_new_pressed()
	tool_page._add_character(character)
	tool_page._set_stash_count(item, 1)

	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var path := SCRATCH_DIR + "refs.tres"
	assert_int(ResourceSaver.save(tool_page.current, path)).is_equal(OK)

	var text := FileAccess.get_file_as_string(path)
	assert_str(text).override_failure_message(
		"the roster did not reference the character file -- a copy was embedded instead"
		).contains(character.resource_path)
	assert_str(text).override_failure_message(
		"the roster did not reference the item file -- a copy was embedded instead"
		).contains(item.resource_path)


# --- "or everything" ---

# The toggle is a STORED flag rather than a bulk tick, so a mod authored tomorrow is included by a
# roster that says "every mod" (dev, 2026-09-07).
func test_offering_everything_keeps_the_explicit_picks_underneath() -> void:
	var character := _a_character()
	if character == null:
		return
	tool_page._on_new_pressed()
	tool_page._add_character(character)

	tool_page._rebuild()
	await await_idle_frame()

	# THE CONTROL, not the field: everything this case is about happens inside the toggle's handler.
	var toggle := _toggle_of(0)
	assert_object(toggle).override_failure_message("the units column has no toggle").is_not_null()
	toggle.button_pressed = true
	await await_idle_frame()
	assert_bool(tool_page.current.offers_every_character).is_true()
	assert_int(tool_page.current.entries.size()).override_failure_message(
		"turning the toggle on threw the curated list away").is_equal(1)

	_toggle_of(0).button_pressed = false
	await await_idle_frame()
	assert_bool(tool_page.current.offers_every_character).is_false()
	assert_int(tool_page.current.entries.size()).override_failure_message(
		"the picks did not come back when the toggle went off").is_equal(1)


func test_an_empty_list_offers_nothing_and_the_flag_offers_everything() -> void:
	var roster := Roster.new()
	# EMPTY MEANS NONE, which is what makes "this mission offers no mods yet" a different file from
	# one nobody thought about -- the ai_factions ambiguity, avoided by having a second state.
	assert_array(roster.offered_mods()).is_empty()
	assert_array(roster.offered_entries()).is_empty()
	assert_array(roster.offered_stash()).is_empty()

	roster.offers_every_mod = true
	roster.offers_every_character = true
	assert_int(roster.offered_mods().size()).is_equal(WeaponModCatalog.get_mods().size())
	assert_int(roster.offered_entries().size()).is_equal(UnitCatalog.get_characters_by_file().size())


# Every synthesized entry is a REFERENCE, the same shape the tool authors by hand: a snapshot here
# would deploy the whole cast naked and jobless.
func test_offering_every_character_synthesizes_reference_entries() -> void:
	var roster := Roster.new()
	roster.offers_every_character = true
	var entries := roster.offered_entries()
	if entries.is_empty():
		push_warning("no characters are authored")
		return
	for entry: ScenarioUnitEntry in entries:
		assert_bool(entry.state_saved).override_failure_message(
			"a synthesized entry was a snapshot").is_false()
		assert_object(entry.unit_data).is_not_null()


# --- the pool reaches the phase ---

# Loadout is the one phase object that outlives the draw, so it is what the fitting card can still
# ask. Mods ride it as SHARED refs (copy_for_grant answers with itself), the stash as copies.
func test_the_loadout_carries_the_missions_mods_by_reference() -> void:
	var mod := _a_mod()
	if mod == null:
		push_warning("no mods are authored")
		return
	var roster := Roster.new()
	roster.available_mods = [mod]

	var loadout := Loadout.from_roster(roster)

	assert_int(loadout.available_mods.size()).is_equal(1)
	assert_object(loadout.available_mods[0]).override_failure_message(
		"the mod was copied -- a fork of its granted attacks a save would write inline"
		).is_same(mod)


# The family rule stays a fact about the WEAPON and the pool a fact about the mission, so the two
# compose rather than replacing each other.
func test_the_pool_filters_the_offer_and_an_empty_pool_means_the_catalogue() -> void:
	var mods := WeaponModCatalog.get_mods()
	if mods.size() < 2:
		push_warning("fewer than two mods are authored, so a filter cannot be observed")
		return
	var family := WeaponData.WeaponType.CARBINE
	var everything := WeaponModCatalog.offerable_for(family)
	if everything.size() < 2:
		push_warning("fewer than two mods fit this family")
		return

	var one: Array[WeaponModData] = [everything[everything.keys()[0]]]
	var narrowed := WeaponModCatalog.offerable_for(family, one)

	assert_int(narrowed.size()).override_failure_message(
		"the pool did not narrow what the card offers").is_equal(1)
	assert_int(WeaponModCatalog.offerable_for(family, [] as Array[WeaponModData]).size()) \
		.override_failure_message("an empty pool stopped meaning the whole catalogue"
		).is_equal(everything.size())

# THE MARKER IS A STATE, NOT AN EVENT (found in play, 2026-09-07: "every time I change something,
# the 'Update' line gets another asterisk next to it").
#
# mark_unsaved DECORATES the base text it is handed, and refresh_update_button writes only the
# tooltip and the disabled flag -- so a caller passing the button's own live caption re-decorates
# what it already decorated, once per edit, forever. The bug needs TWO edits to exist at all, which
# is why a case that dirties the page once could not see it.
func test_the_unsaved_marker_never_doubles() -> void:
	var character := _a_character()
	if character == null:
		return
	tool_page._on_new_pressed()
	await await_idle_frame()

	for _i in 4:
		tool_page._mark_dirty()

	var update: Button = _overlay.get_node("%UpdateRosterButton")
	assert_int(update.text.count("*")).override_failure_message(
		"the marker grew one star per edit: %s" % update.text).is_equal(1)
