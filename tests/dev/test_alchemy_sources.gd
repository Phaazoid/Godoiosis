# The Alchemy page's Sources tab (#1532 slice 2, AlchemySources): what each ground, tile state, gas and unit state
# is made of, edited live on SubstanceMap's rows.
#
# The content razor (tests/README.md rule 9): no case asserts what an authored row SAYS. A row is
# edited to an id picked from the real catalog by what the code reports, and every expectation is
# derived from the seam under test (CellSubstances.available_near, present_from).
#
# The authored map is process-global (SubstanceMap.authored() is the resource cache's object), so
# after_test puts it back through the page's own Reset -- a leaked row would reach every later suite.
# A case that saves aims the page at a user:// copy, never the shipped file.
extends GdUnitTestSuite

const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")
const PROBE_PATH := "user://__test_alchemy_sources.tres"
const HERE := Vector2i(4, 4)

var _tool: AlchemySources
var _scene: Node3D


class _OneCellBoard extends BoardContext:
	var kind: Terrain.Kind
	func _init(states: TerrainStateManager, k: Terrain.Kind) -> void:
		super(null, [] as Array[Unit], null, states)
		kind = k
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return kind if cell == HERE else Terrain.Kind.NONE
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
	if is_instance_valid(_scene):
		(_scene.get_node("Main/DevOverlay") as DevOverlay).alchemy_tool.sources._on_reset_pressed()
		get_tree().root.remove_child(_scene)
		_scene.free()
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


func _board(kind: Terrain.Kind) -> BoardContext:
	var states: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(states)
	return _OneCellBoard.new(states, kind)


func _present_on(kind: Terrain.Kind) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(CellSubstances.available_near(HERE, _board(kind)).keys())
	return ids


# A real substance a cast on `kind` cannot draw on yet, found rather than named.
func _absent_from(kind: Terrain.Kind) -> String:
	var present := _present_on(kind)
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
	for kind: int in Terrain.Kind.values():
		if kind != Terrain.Kind.NONE:
			expected.append([&"grounds", kind])
	for state: int in Terrain.TileState.values():
		if state != Terrain.TileState.NONE and not Terrain.RETIRED_STATES.has(state):
			expected.append([&"tile_states", state])
	for gas: int in Gas.Kind.values():
		expected.append([&"gases", gas])
	for state: int in Elemental.State.values():
		if state != Elemental.State.NONE:
			expected.append([&"unit_states", state])
	for row: Array in expected:
		assert_object(_field(_tool, row[0], row[1])).override_failure_message(
			"no row for %s %d" % row).is_not_null()
	assert_int(_tool._fields.size()).is_equal(expected.size())


# --- wires ----------------------------------------------------------------------------------

# THE MISSING-WIRE CASE: a row typed on the page is what the next cast reads, with no save.
func test_a_typed_row_reaches_the_next_cast() -> void:
	var pick := _absent_from(Terrain.Kind.MUD)
	assert_str(pick).override_failure_message("every substance is already present on mud").is_not_empty()
	_type(_field(_tool, &"grounds", Terrain.Kind.MUD), pick)
	assert_array(SubstanceMap.authored().of_kind(Terrain.Kind.MUD)).is_equal([pick])
	assert_bool(_present_on(Terrain.Kind.MUD).has(pick)).override_failure_message(
		"the page wrote a row the cast does not read").is_true()


func test_an_unknown_or_repeated_substance_is_refused() -> void:
	var field := _field(_tool, &"grounds", Terrain.Kind.MUD)
	var before := SubstanceMap.authored().of_kind(Terrain.Kind.MUD)
	var any: String = SubstanceCatalog.get_all().keys()[0]
	for text: String in ["no_such_substance_here", "%s + %s" % [any, any]]:
		_type(field, text)
		assert_array(SubstanceMap.authored().of_kind(Terrain.Kind.MUD)).override_failure_message(
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
	var field := _field(_tool, &"grounds", Terrain.Kind.DIRT)
	_type(field, compound)
	var catalog := SubstanceCatalog.get_all()
	for id: String in CellSubstances.present_from([compound] as Array[String]):
		var shown: String = (catalog[id] as Substance).display_name
		assert_str(_tool._readouts[field].text).contains(shown if shown != "" else id)


func test_an_empty_row_holds_nothing_and_is_written() -> void:
	_type(_field(_tool, &"grounds", Terrain.Kind.DIRT), "")
	assert_array(SubstanceMap.authored().of_kind(Terrain.Kind.DIRT)).is_empty()
	assert_bool(_tool.is_dirty()).is_true()


func test_a_write_rereads_the_plan_and_drops_the_enemy_ranges() -> void:
	var game := _StubGame.new()
	_tool.init(game)
	var field := _field(_tool, &"grounds", Terrain.Kind.MUD)
	_type(field, _absent_from(Terrain.Kind.MUD))
	assert_int(game.refreshed).is_equal(1)
	assert_int(game.dropped).is_equal(1)
	_type(field, "no_such_substance_here")
	assert_int(game.refreshed).override_failure_message("a refused row re-resolved the plan").is_equal(1)


# --- save / reset ---------------------------------------------------------------------------

func test_an_edit_marks_save_and_reset_puts_the_file_back() -> void:
	_aim_at_probe()
	assert_bool(_tool._reset_button.disabled).override_failure_message(
		"Reset is offered on a page with nothing to put back").is_true()
	var field := _field(_tool, &"grounds", Terrain.Kind.MUD)
	_type(field, _absent_from(Terrain.Kind.MUD))
	assert_str(_tool._save_button.text).is_equal("Save *")
	assert_bool(_tool._reset_button.disabled).is_false()
	_tool._on_reset_pressed()
	var saved := _on_disk(&"grounds", Terrain.Kind.MUD)
	var live := load(PROBE_PATH) as SubstanceMap
	assert_array(Array(live.grounds.get(Terrain.Kind.MUD, PackedStringArray()))).is_equal(Array(saved))
	assert_str(_field(_tool, &"grounds", Terrain.Kind.MUD).text).is_equal(" + ".join(saved))
	assert_str(_tool._save_button.text).is_equal("Save")
	assert_bool(_tool._reset_button.disabled).is_true()


func test_save_asks_first_and_writes_nothing_until_confirmed() -> void:
	_aim_at_probe()
	var before := _on_disk(&"grounds", Terrain.Kind.MUD)
	_type(_field(_tool, &"grounds", Terrain.Kind.MUD), _absent_from(Terrain.Kind.MUD))
	_tool._on_save_pressed()
	var dialogs := _tool.find_children("*", "ConfirmationDialog", false, false)
	assert_int(dialogs.size()).is_equal(1)
	assert_str((dialogs[0] as ConfirmationDialog).dialog_text).contains(PROBE_PATH)
	assert_array(Array(_on_disk(&"grounds", Terrain.Kind.MUD))).override_failure_message(
		"the save ran before it was confirmed").is_equal(Array(before))
	dialogs[0].free()


func test_a_confirmed_save_writes_the_row_and_clears_the_marker() -> void:
	_aim_at_probe()
	var pick := _absent_from(Terrain.Kind.MUD)
	_type(_field(_tool, &"grounds", Terrain.Kind.MUD), pick)
	_tool.save_now()
	assert_array(Array(_on_disk(&"grounds", Terrain.Kind.MUD))).is_equal([pick])
	assert_bool(_tool.is_dirty()).is_false()
	assert_str(_tool._save_button.text).is_equal("Save")


func test_save_with_nothing_moved_says_so_and_asks_nothing() -> void:
	_tool._on_save_pressed()
	assert_int(_tool.find_children("*", "ConfirmationDialog", false, false).size()).is_equal(0)
	assert_str(_tool._status.text).is_equal("Nothing has moved off what is saved.")


# --- the dev window -------------------------------------------------------------------------

# The page is a leaf of the real window, and the Tiles page's read-only line follows an edit made
# here once it is shown again.
func test_the_tiles_line_follows_an_edit_made_on_this_page() -> void:
	_scene = SCENE.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	var overlay := _scene.get_node("Main/DevOverlay") as DevOverlay
	var tiles := overlay.object_tool
	assert_bool(tiles.has_host()).override_failure_message("the Tiles page has no 3D host").is_true()
	var kind := Terrain.Kind.NONE
	for i in tiles._objects.size():
		kind = GridUtils.terrain_kind_of(tiles._objects[i]["data"])
		if kind != Terrain.Kind.NONE:
			tiles._picked = i
			break
	assert_int(kind).override_failure_message("no tile names a ground").is_not_equal(Terrain.Kind.NONE)
	tiles._rebuild()
	overlay.show_leaf(tiles)
	var pick := _absent_from(kind)
	var shown: String = (SubstanceCatalog.get_all()[pick] as Substance).display_name
	if shown == "":
		shown = pick
	assert_str(tiles._made_of.text).not_contains("Made of: %s" % shown)
	overlay.show_leaf(overlay.alchemy_tool)
	overlay.alchemy_tool.show_tab(overlay.alchemy_tool.sources)
	_type(_field(overlay.alchemy_tool.sources, &"grounds", kind), pick)
	overlay.show_leaf(tiles)
	assert_str(tiles._made_of.text).starts_with("Made of: %s" % shown)
