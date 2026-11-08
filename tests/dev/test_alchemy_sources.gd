# The Alchemy page's Sources tab (#1532 slice 2, AlchemySources): what each tile state, gas and unit
# state is made of, edited live on SubstanceMap's rows. A ground's makeup is on the Tiles page (#1315),
# and its cases are in test_object_fields.gd.
#
# The content razor (tests/README.md rule 9): no case asserts what an authored row SAYS. A row is
# edited to an id picked from the real catalog by what the code reports, and every expectation is
# derived from the seam under test (CellSubstances.available_near, present_from).
#
# The authored map is process-global (SubstanceMap.authored() is the resource cache's object), so
# after_test puts it back through the page's own Reset -- a leaked row would reach every later suite.
# A case that saves aims the page at a user:// copy, never the shipped file.
extends GdUnitTestSuite

const PROBE_PATH := "user://__test_alchemy_sources.tres"
const HERE := Vector2i(4, 4)
const STATE := Terrain.TileState.FROZEN   # the row the cases edit; any tile state's row would do

var _tool: AlchemySources


# One cell with a tile state lying on it, and nothing else made of anything.
class _OneCellBoard extends BoardContext:
	var state: Terrain.TileState
	func _init(states: TerrainStateManager, s: Terrain.TileState) -> void:
		super(null, [] as Array[Unit], null, states)
		state = s
	func terrain_kind_at(_cell: Vector2i) -> Terrain.Kind:
		return Terrain.Kind.NONE
	func tile_states_at(cell: Vector2i) -> Array[Terrain.TileState]:
		var out: Array[Terrain.TileState] = []
		if cell == HERE:
			out.append(state)
		return out
	func prop_lit_at(_cell: Vector2i) -> bool:
		return false


# What the page re-reads the plan through: counts, so a case can ask whether a write reached it.
class _StubSquads extends RefCounted:
	var active_squad = null

class _StubGame extends RefCounted:
	var squad_manager := _StubSquads.new()
	var refreshed := 0
	var dropped := 0
	func refresh_action_queue(_squad) -> void:
		refreshed += 1
	func drop_threat_field() -> void:
		dropped += 1


func before_test() -> void:
	_tool = AlchemySources.new()
	add_child(_tool)


func after_test() -> void:
	if is_instance_valid(_tool):
		_tool.path = SubstanceMap.PATH
		_tool._on_reset_pressed()
		_tool.free()
	if FileAccess.file_exists(PROBE_PATH):
		DirAccess.remove_absolute(PROBE_PATH)
	await await_idle_frame()   # #93/#101 orphan workaround


func _field(page: AlchemySources, table: StringName, key: int) -> LineEdit:
	for field: LineEdit in page._fields:
		var row: Dictionary = page._fields[field]
		if row["table"] == table and row["key"] == key:
			return field
	return null


func _type(field: LineEdit, text: String) -> void:
	field.text = text
	field.text_changed.emit(text)   # setting text from code emits nothing; a keystroke does


func _board(state: Terrain.TileState) -> BoardContext:
	var states: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(states)
	return _OneCellBoard.new(states, state)


func _present_on(state: Terrain.TileState) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(CellSubstances.available_near(HERE, _board(state)).keys())
	return ids


# A real substance a cast beside `state` cannot draw on yet, found rather than named.
func _absent_from(state: Terrain.TileState) -> String:
	var present := _present_on(state)
	for id: String in SubstanceCatalog.get_all():
		if not present.has(id):
			return id
	return ""


func _aim_at_probe() -> void:
	assert_int(ResourceSaver.save(SubstanceMap.authored().duplicate(true), PROBE_PATH)).is_equal(OK)
	var fresh := ResourceLoader.load(PROBE_PATH, "", ResourceLoader.CACHE_MODE_REPLACE)   # not a past case's copy
	assert_object(fresh).is_not_null()
	_tool.path = PROBE_PATH
	_tool.refresh_on_show()


func _on_disk(table: StringName, key: int) -> PackedStringArray:
	var saved := ResourceLoader.load(PROBE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as SubstanceMap
	return (saved.get(table) as Dictionary).get(key, PackedStringArray())


# --- laws -----------------------------------------------------------------------------------

# Every member test_substance_map holds to a row has one here, derived from the enums.
func test_every_member_of_every_table_has_a_row() -> void:
	var expected: Array[Array] = []
	for state: int in Terrain.TileState.values():
		if state != Terrain.TileState.NONE and not Terrain.RETIRED_STATES.has(state):
			expected.append([&"tile_states", state])
	for gas: int in Gas.Kind.values():
		expected.append([&"gases", gas])
	for state: int in Elemental.State.values():
		if state != Elemental.State.NONE:
			expected.append([&"unit_states", state])
	for kind: int in Vein.Kind.values():
		if kind != Vein.Kind.NONE:
			expected.append([&"veins", kind])
	for row: Array in expected:
		assert_object(_field(_tool, row[0], row[1])).override_failure_message(
			"no row for %s %d" % row).is_not_null()
	assert_int(_tool._fields.size()).is_equal(expected.size())


# --- wires ----------------------------------------------------------------------------------

# THE MISSING-WIRE CASE: a row typed on the page is what the next cast reads, with no save.
func test_a_typed_row_reaches_the_next_cast() -> void:
	var pick := _absent_from(STATE)
	assert_str(pick).override_failure_message("every substance is already present where the state lies").is_not_empty()
	_type(_field(_tool, &"tile_states", STATE), pick)
	assert_array(SubstanceMap.authored().of_tile_state(STATE)).is_equal([pick])
	assert_bool(_present_on(STATE).has(pick)).override_failure_message(
		"the page wrote a row the cast does not read").is_true()


func test_an_unknown_or_repeated_substance_is_refused() -> void:
	var field := _field(_tool, &"tile_states", STATE)
	var before := SubstanceMap.authored().of_tile_state(STATE)
	var any: String = SubstanceCatalog.get_all().keys()[0]
	for text: String in ["no_such_substance_here", "%s + %s" % [any, any]]:
		_type(field, text)
		assert_array(SubstanceMap.authored().of_tile_state(STATE)).override_failure_message(
			"\"%s\" was written" % text).is_equal(before)
		assert_str(_tool._readouts[field].text).contains("Not written")
	assert_bool(_tool.is_dirty()).is_false()


# The readout names everything the walk a cast runs makes present -- here a compound and its parts.
func test_the_readout_names_what_a_cast_would_find() -> void:
	var compound := ""
	for id: String in SubstanceCatalog.get_all():
		if CellSubstances.present_from([id] as Array[String]).size() > 1:
			compound = id
			break
	assert_str(compound).override_failure_message("no substance lends a part").is_not_empty()
	var field := _field(_tool, &"tile_states", STATE)
	_type(field, compound)
	var catalog := SubstanceCatalog.get_all()
	for id: String in CellSubstances.present_from([compound] as Array[String]):
		var shown: String = (catalog[id] as Substance).display_name
		assert_str(_tool._readouts[field].text).contains(shown if shown != "" else id)


func test_an_empty_row_holds_nothing_and_is_written() -> void:
	_type(_field(_tool, &"tile_states", STATE), "")
	assert_array(SubstanceMap.authored().of_tile_state(STATE)).is_empty()
	assert_bool(_tool.is_dirty()).is_true()


func test_a_write_rereads_the_plan_and_drops_the_enemy_ranges() -> void:
	var game := _StubGame.new()
	_tool.init(game)
	var field := _field(_tool, &"tile_states", STATE)
	_type(field, _absent_from(STATE))
	assert_int(game.refreshed).is_equal(1)
	assert_int(game.dropped).is_equal(1)
	_type(field, "no_such_substance_here")
	assert_int(game.refreshed).override_failure_message("a refused row re-resolved the plan").is_equal(1)


# --- save / reset ---------------------------------------------------------------------------

func test_an_edit_marks_save_and_reset_puts_the_file_back() -> void:
	_aim_at_probe()
	assert_bool(_tool._reset_button.disabled).override_failure_message(
		"Reset is offered on a page with nothing to put back").is_true()
	var field := _field(_tool, &"tile_states", STATE)
	_type(field, _absent_from(STATE))
	assert_str(_tool._save_button.text).is_equal("Save *")
	assert_bool(_tool._reset_button.disabled).is_false()
	_tool._on_reset_pressed()
	var saved := _on_disk(&"tile_states", STATE)
	var live := load(PROBE_PATH) as SubstanceMap
	assert_array(Array(live.tile_states.get(STATE, PackedStringArray()))).is_equal(Array(saved))
	assert_str(_field(_tool, &"tile_states", STATE).text).is_equal(" + ".join(saved))
	assert_str(_tool._save_button.text).is_equal("Save")
	assert_bool(_tool._reset_button.disabled).is_true()


func test_save_asks_first_and_writes_nothing_until_confirmed() -> void:
	_aim_at_probe()
	var before := _on_disk(&"tile_states", STATE)
	_type(_field(_tool, &"tile_states", STATE), _absent_from(STATE))
	_tool._on_save_pressed()
	var dialogs := _tool.find_children("*", "ConfirmationDialog", false, false)
	assert_int(dialogs.size()).is_equal(1)
	assert_str((dialogs[0] as ConfirmationDialog).dialog_text).contains(PROBE_PATH)
	assert_array(Array(_on_disk(&"tile_states", STATE))).override_failure_message(
		"the save ran before it was confirmed").is_equal(Array(before))
	dialogs[0].free()


func test_a_confirmed_save_writes_the_row_and_clears_the_marker() -> void:
	_aim_at_probe()
	var pick := _absent_from(STATE)
	_type(_field(_tool, &"tile_states", STATE), pick)
	_tool.save_now()
	assert_array(Array(_on_disk(&"tile_states", STATE))).is_equal([pick])
	assert_bool(_tool.is_dirty()).is_false()
	assert_str(_tool._save_button.text).is_equal("Save")


func test_save_with_nothing_moved_says_so_and_asks_nothing() -> void:
	_tool._on_save_pressed()
	assert_int(_tool.find_children("*", "ConfirmationDialog", false, false).size()).is_equal(0)
	assert_str(_tool._status.text).is_equal("Nothing has moved off what is saved.")

