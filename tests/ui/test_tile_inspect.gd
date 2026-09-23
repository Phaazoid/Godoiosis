# The Inspect dock's TILE MODE (#1105): clicking an empty tile opens what is on it -- who is watching
# it, which objective zones it belongs to, and its ground -- in the same dock a unit's Inspect uses,
# and a unit's Inspect reaches its own tile through the Unit/Tile switch.
#
# Every case clicks through game._on_left_click (the door both views' pickers call) and reads the
# labels the dock actually drew, because the bugs this guards are wires: a card that reads a second
# answer to "who is watching" (case 3), a zone the board stopped drawing (case 5), a body that went
# stale while open (case 8). Expectations come off the seams (TileReadout, Glossary), never off
# authored content -- the content razor, tests/README.md #9.
#
# Fixture is tests/flow/test_watch_shot_interrupts_the_walk.gd's (tests/README.md -> Testing the
# game scene).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

const WATCHED := Vector2i(4, 1)

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		for y in range(5):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _panel() -> UnitInfoPanelControl:
	return game.unit_info_panel


func _texts() -> String:
	return "\n".join(_panel().tile_texts())


func _spawn(faction: Team.Faction, cell: Vector2i, unit_name: String) -> Unit:
	var data := H.make_unit_data({Stats.Stat.MHP: 80}, faction)
	data.display_name = unit_name
	var unit: Unit = game.spawn_unit(data, cell)
	assert_object(unit).override_failure_message("fixture failed to spawn at %s" % str(cell)).is_not_null()
	unit.equipped_weapon = H.make_weapon(4)
	return unit


# A single-cell watch aimed from where the watcher stands, then published the way a settled pass
# publishes it -- through the one door the board's marks are drawn from.
func _arm(watcher: Unit, cell: Vector2i, attack_name := "") -> void:
	var footprint: Array[Vector2i] = [cell]
	var attack: AttackData = watcher.get_default_attack()
	attack.display_name = attack_name
	watcher.arm_watch(watcher.movement.cell, cell, footprint, attack)
	assert_object(watcher.watch).override_failure_message("fixture failed to arm the watch").is_not_null()


func _set_burning(cell: Vector2i) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added = [Terrain.TileState.BURNING]
	game.terrain_states.apply(effect)


func _click(cell: Vector2i) -> void:
	game._on_left_click(cell)
	await await_idle_frame()


func test_clicking_an_empty_tile_opens_it_in_the_dock() -> void:
	var cell := Vector2i(3, 3)
	_set_burning(cell)

	await _click(cell)

	assert_bool(_panel().is_showing()).override_failure_message(
			"clicking an empty tile opened nothing").is_true()
	assert_str(_panel().name_label.text).is_equal(TileReadout.title_of(game, cell))
	for line in TileReadout.ground_lines(game, cell):
		assert_str(_texts()).override_failure_message(
				"the dock left out a ground line the hover card shows: %s" % line).contains(line)
	assert_str(_texts()).contains(Glossary.short(Glossary.Term.BURNING))


func test_the_hover_card_steps_aside_for_an_open_tile() -> void:
	# is_showing() is what HoverPresenter parks the card by. It used to mean "a UNIT is open", so a
	# tile in the dock would have had the hover card drawn straight over it.
	await _click(Vector2i(3, 3))
	game.hover_presenter.update_hover_visuals(Vector2i(6, 2))
	await await_idle_frame()

	assert_bool(game.hover_info_panel.visible).is_true()
	assert_float(game.hover_info_panel.position.x).override_failure_message(
			"the hover card sits on top of the tile open in the dock").is_greater_equal(
			_panel().panel_width())


func test_a_watch_is_named_by_side_unit_and_attack() -> void:
	var watcher := _spawn(ENEMY, Vector2i(2, 1), "Brigand Archer")
	_arm(watcher, WATCHED, "Test Longbow")
	game.refresh_watch_markers()

	await _click(WATCHED)

	var texts := _texts()
	assert_str(texts).contains(Glossary.title(Glossary.Term.OVERWATCH))
	assert_str(texts).contains(Glossary.short(Glossary.Term.OVERWATCH))
	assert_str(texts).contains("Brigand Archer (%s), Test Longbow" % TileReadout.SIDE_WORDS[ENEMY])


func test_a_watch_whose_mark_is_gone_is_not_named() -> void:
	# THE STORE, NOT THE UNITS. Moved off the cell it aimed from, the watcher's watch still reads
	# armed -- but the anchor rule drops its mark, so the dock must drop it too. A dock that walked
	# the units would name a watch the board no longer shows.
	var watcher := _spawn(ENEMY, Vector2i(2, 1), "Brigand Archer")
	_arm(watcher, WATCHED)
	watcher.movement.set_cell(Vector2i(2, 3))
	game.refresh_watch_markers()
	assert_bool(watcher.watch.is_armed()).override_failure_message(
			"precondition: the live watch must still read armed, or this proves nothing").is_true()
	assert_array(game.overlay_manager.watch_cells).override_failure_message(
			"precondition: the board must have dropped the mark").not_contains([WATCHED])

	await _click(WATCHED)

	assert_bool(_panel().is_showing()).is_true()
	assert_str(_texts()).override_failure_message(
			"the dock named a watch whose reticle is gone").not_contains("Brigand Archer")


func test_two_watches_on_one_cell_are_both_named_and_explained_once() -> void:
	var theirs := _spawn(ENEMY, Vector2i(2, 1), "Brigand Archer")
	var ours := _spawn(PLAYER, Vector2i(6, 1), "Rook")
	_arm(theirs, WATCHED)
	_arm(ours, WATCHED)
	game.refresh_watch_markers()

	await _click(WATCHED)

	var texts := _texts()
	assert_str(texts).contains("Brigand Archer (%s)" % TileReadout.SIDE_WORDS[ENEMY])
	assert_str(texts).contains("Rook (%s)" % TileReadout.SIDE_WORDS[PLAYER])
	assert_int(texts.count(Glossary.short(Glossary.Term.OVERWATCH))).is_equal(1)


func test_a_capture_zone_is_named_until_it_is_claimed() -> void:
	var cell := Vector2i(5, 3)
	game.zone_manager.paint_cell("Test Point", ZoneManager.Kind.CAPTURE, cell)

	await _click(cell)

	var texts := _texts()
	assert_str(texts).contains("Test Point")
	assert_str(texts).contains(Glossary.title(Glossary.Term.CAPTURE_ZONE))
	assert_str(texts).override_failure_message(
			"the zone says what it is but not how to take it").contains(
			Glossary.title(Glossary.Term.CAPTURE))

	# Claimed, the board stops tinting it (hidden_zone_names), so the open dock must let go of it
	# too -- without another click.
	game.mission_controller.capture("Test Point")
	await await_idle_frame()

	assert_str(_texts()).override_failure_message(
			"a claimed zone the board no longer draws is still named in the dock").not_contains("Test Point")


func test_a_patrol_zone_is_never_named() -> void:
	var cell := Vector2i(5, 3)
	_set_burning(cell)
	game.zone_manager.paint_cell("Leash", ZoneManager.Kind.PATROL, cell)
	assert_bool(game.zone_manager.contains("Leash", cell)).is_true()

	await _click(cell)

	var texts := _texts()
	assert_str(texts).not_contains("Leash")
	# The ground still reads, so the tile was composed at all rather than aborted on the way.
	assert_str(texts).contains(Glossary.short(Glossary.Term.BURNING))


func test_a_units_tile_is_one_switch_away() -> void:
	var cell := Vector2i(3, 2)
	_set_burning(cell)
	var unit := _spawn(PLAYER, cell, "Aldin")
	_panel().set_unit(unit, true, game._board())
	await await_idle_frame()
	assert_array(_panel().tile_texts()).override_failure_message(
			"Inspect opened on the tile rather than the unit").is_empty()

	_panel().switch_button(UnitInfoPanelControl.View.TILE).pressed.emit()
	await await_idle_frame()

	assert_str(_texts()).contains(Glossary.short(Glossary.Term.BURNING))
	assert_bool(_panel().stats_section.visible).override_failure_message(
			"the unit body is still drawn under the tile").is_false()

	_panel().switch_button(UnitInfoPanelControl.View.UNIT).pressed.emit()
	await await_idle_frame()

	assert_bool(_panel().stats_section.visible).is_true()
	assert_array(_panel().tile_texts()).is_empty()


func test_inspecting_someone_else_opens_on_the_unit() -> void:
	var first := _spawn(PLAYER, Vector2i(3, 2), "Aldin")
	var second := _spawn(PLAYER, Vector2i(3, 3), "Aster")
	_panel().set_unit(first, true, game._board())
	_panel().switch_button(UnitInfoPanelControl.View.TILE).pressed.emit()

	_panel().set_unit(second, true, game._board())
	await await_idle_frame()

	assert_bool(_panel().stats_section.visible).is_true()
	assert_array(_panel().tile_texts()).is_empty()


func test_the_open_tile_follows_the_board() -> void:
	var cell := Vector2i(3, 3)
	await _click(cell)
	var burning := Glossary.short(Glossary.Term.BURNING)
	assert_str(_texts()).not_contains(burning)

	_set_burning(cell)
	await await_idle_frame()

	assert_str(_texts()).override_failure_message(
			"the dock kept showing the tile as it was when clicked").contains(burning)


func test_clicking_off_the_map_opens_nothing() -> void:
	await _click(Vector2i(50, 50))

	assert_bool(_panel().is_showing()).is_false()


func test_the_pre_mission_board_inspects_a_tile_too() -> void:
	var cell := Vector2i(3, 3)
	game.game_state = game.GameState.PRE_MISSION
	assert_array(game.mission_controller.open_deployment_cells()).override_failure_message(
			"precondition: on a deployment cell this click opens the deploy menu instead").not_contains([cell])

	await _click(cell)

	assert_bool(_panel().is_showing()).is_true()
