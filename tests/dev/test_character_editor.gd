# The Character editor (#179): the dev tab that authors the Resources/Units/ cast files (#177).
# Pins the pool chrome's guards (the Update load-gate, Save As refusals, New clearing the loaded
# identity), the by-construction kit rule (a slot pick stages the catalog FILE, so saves write
# ExtResource references), the Rebecca-rule aura guard, the capture projection off
# ScenarioUnitEntry.capture_unit_state, and the Spawn-tab dropdown refresh wire.
#
# No case writes to disk: refusal cases return before any save, and the allowed Update
# direction is asserted at reason level (a real press would re-save a tracked cast file).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

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
	for x in range(8):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	overlay = game.dev_overlay
	await await_idle_frame()

func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()

func _tool() -> CharacterEditorTool:
	return overlay.get_node("%Character")

# ==============================================================================
#  Update: the load gate
# ==============================================================================

func test_update_refuses_an_unloaded_character() -> void:
	var tool := _tool()
	if tool.load_dropdown.item_count == 0:   # content-absent: warn, never fail (tests/README.md rule 9)
		push_warning("the character catalog is empty, so there is nothing to load and refuse")
		return
	tool.load_dropdown.select(0)

	tool.update_button.pressed.emit()

	# The refusal wording, not just "some message": a gate-less Update would still write a label
	# ("Saved, but no map sprite...") -- caught by this suite's own first falsification run.
	assert_str(tool.status_label.text).contains("Load '")

func test_update_allows_the_loaded_character_at_reason_level() -> void:
	# Reason level only -- an actual allowed press would re-save a tracked cast file.
	var tool := _tool()
	if tool.load_dropdown.item_count == 0:   # content-absent: warn, never fail (tests/README.md rule 9)
		push_warning("the character catalog is empty, so there is nothing to load")
		return
	tool.load_dropdown.select(0)
	tool._on_load_pressed()

	assert_str(tool._update_block_reason()).is_empty()
	assert_bool(tool.update_button.disabled).is_false()

func test_new_clears_the_loaded_identity() -> void:
	var tool := _tool()
	if tool.load_dropdown.item_count == 0:   # content-absent: warn, never fail (tests/README.md rule 9)
		push_warning("the character catalog is empty, so there is nothing to load")
		return
	tool.load_dropdown.select(0)
	tool._on_load_pressed()
	assert_str(tool._loaded_name).is_not_empty()

	tool.get_node("VBoxContainer/NewRow/NewButton").pressed.emit()

	assert_str(tool._loaded_name).is_empty()
	assert_int(tool.load_dropdown.selected).is_equal(-1)
	assert_bool(tool.update_button.disabled).is_true()

# ==============================================================================
#  Save As: the refusals (all return before any save)
# ==============================================================================

func test_save_as_refuses_empty_illegal_and_taken_names() -> void:
	var tool := _tool()
	var save_as: Button = overlay.get_node("%SaveAsCharacterButton")

	tool.name_input.text = ""
	save_as.pressed.emit()
	assert_str(tool.status_label.text).is_not_empty()

	tool.name_input.text = "a:b"
	save_as.pressed.emit()
	assert_str(tool.status_label.text).contains("can't contain")

	tool.name_input.text = "Aster"   # a shipped cast file -- Save As creates, Update overwrites
	save_as.pressed.emit()
	assert_str(tool.status_label.text).contains("already exists")

# ==============================================================================
#  The staged form's structural rules
# ==============================================================================

func test_slot_pick_stages_the_catalog_file_itself() -> void:
	# The by-construction fix for the hand-inlined-WeaponInstance trap: a slot pick stages the
	# catalog FILE resource, so a save writes an ExtResource reference, never an embedded copy.
	var tool := _tool()
	var catalog := tool._item_catalog()
	if catalog.is_empty():   # content-absent: warn, never fail (tests/README.md rule 9)
		push_warning("the equippable catalog is empty, so no slot pick can stage a file")
		return
	tool._on_new_pressed()

	tool._on_slot_picked(0, 1)   # first catalog entry

	var staged: EquippableData = tool.current.starting_inventory[0]
	assert_object(staged).is_same(catalog[catalog.keys()[0]])
	assert_str(staged.resource_path).is_not_empty()

func test_unchecking_an_affinity_erases_its_aura() -> void:
	# The Rebecca-rule guard: aura outside affinity is unauthorable here, which is exactly the
	# latent illegality the shipped cast files carry (their spawn drops it with a warning).
	var tool := _tool()
	tool._on_new_pressed()
	tool._on_affinity_toggled(Elemental.Element.FIRE, true)
	tool.current.base_aura[Elemental.Element.FIRE] = 3

	tool._on_affinity_toggled(Elemental.Element.FIRE, false)

	assert_bool(tool.current.base_aura.has(Elemental.Element.FIRE)).is_false()

# ==============================================================================
#  Capture: the live-unit -> character projection
# ==============================================================================

func test_capture_refuses_with_no_unit_selected() -> void:
	var tool := _tool()
	overlay.unit_editor.editing_unit = null

	overlay.get_node("%CaptureCharacterButton").pressed.emit()

	assert_str(tool.status_label.text).contains("No unit selected")

func test_capture_projects_the_live_unit() -> void:
	var abilities := AbilityCatalog.get_abilities()
	assert_int(abilities.size()).is_greater(0)
	var innate: AbilityData = abilities[abilities.keys()[0]]

	var data := H.make_unit_data({Stats.Stat.STR: 9}, Team.Faction.ENEMY)
	data.display_name = "Capture Subject"
	data.innate_abilities.append(innate)
	data.starting_jobs = ["scout"]
	data.starting_inventory = [H.make_weapon(4), H.make_weapon(6)]
	data.starting_equipped_index = 1
	var unit: Unit = game.spawn_unit(data, Vector2i(1, 0))
	assert_object(unit).is_not_null()
	overlay.unit_editor.edit_unit(unit)

	var tool := _tool()
	overlay.get_node("%CaptureCharacterButton").pressed.emit()

	var captured: UnitData = tool.current
	assert_str(captured.display_name).is_equal("Capture Subject")
	assert_int(captured.faction).is_equal(Team.Faction.ENEMY)
	assert_int(captured.base_stats[Stats.Stat.STR]).is_equal(9)
	assert_bool(captured.innate_abilities.has(innate)).is_true()
	assert_array(captured.starting_jobs).contains(["scout"])
	# Dense inventory, and the explicit equip pick survives capture_unit_state's index remap.
	assert_int(captured.starting_inventory.size()).is_equal(2)
	assert_int(captured.starting_equipped_index).is_equal(1)
	# A capture is a NEW character, never the loaded one -- Update must stay blocked.
	assert_str(tool._loaded_name).is_empty()
	# The carried copies have no files behind them; the declared inline loss is said out loud.
	assert_str(tool.status_label.text).contains("inline")

# ==============================================================================
#  The Spawn form's dropdown refresh wires (both doors)
# ==============================================================================

func test_switching_to_the_spawn_subtab_rebuilds_the_character_dropdown() -> void:
	# The inner door: save a character, flip Character -> Spawn, place it. No outer tab change
	# ever fires on that path, so the sub-tab switch must carry its own refresh wire.
	var spawn: SpawnTool = overlay.spawn
	spawn._character_dropdown.clear()   # a stale list, as if the catalog changed underneath
	assert_int(spawn._character_dropdown.item_count).is_equal(0)

	var authoring_tabs: TabContainer = overlay.get_node("%AuthoringTabs")
	authoring_tabs.current_tab = authoring_tabs.get_tab_idx_from_control(_tool())
	authoring_tabs.current_tab = authoring_tabs.get_tab_idx_from_control(spawn)

	assert_int(spawn._character_dropdown.item_count).is_equal(UnitCatalog.get_characters().size() + 1)

func test_entering_the_authoring_tab_rebuilds_the_character_dropdown() -> void:
	# The outer door: authoring can also happen entirely elsewhere (a scenario load, a delete),
	# so entering Unit Authoring refreshes too. Drives the real tab-entry hook.
	var spawn: SpawnTool = overlay.spawn
	spawn._character_dropdown.clear()
	assert_int(spawn._character_dropdown.item_count).is_equal(0)

	var tabs: TabContainer = overlay.get_node("%DevTabs")
	tabs.current_tab = tabs.get_tab_idx_from_control(overlay.unit_editor)
	tabs.current_tab = tabs.get_tab_idx_from_control(overlay.unit_authoring)

	assert_int(spawn._character_dropdown.item_count).is_equal(UnitCatalog.get_characters().size() + 1)
