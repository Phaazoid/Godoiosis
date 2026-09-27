# THE INSPECT KEY (#1105): Z reads what is under the pointer. Over an empty tile the hover card GROWS
# into the tile's full readout -- who is watching it, which objective zones it belongs to, its
# ground -- and shrinks when the pointer moves on; over a unit it opens the Inspect dock, a second Z
# swaps the dock to the tile that unit stands on, and a third closes it. A left-click on an empty
# tile opens nothing, and the ring has no Inspect row.
#
# Every case presses Z as a real key event through game._input, built on physical_keycode the way
# project.godot binds it (test_pre_mission_bar's pattern), so a bound-and-dead key reds. The pointer
# rides HoverPresenter.pointer_source, the seam the 3D picker uses. Expectations come off the seams
# (TileReadout, Glossary), never off authored content -- the content razor, tests/README.md #9.
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
var _pointer := GridUtils.NO_CELL


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
	_pointer = GridUtils.NO_CELL
	game.hover_presenter.pointer_source = func() -> Vector2i: return _pointer
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _panel() -> UnitInfoPanelControl:
	return game.unit_info_panel


func _card() -> HoverInfoPanelControl:
	return game.hover_info_panel


func _card_texts() -> String:
	return "\n".join(_card().grown_texts())


func _dock_texts() -> String:
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


func _point(cell: Vector2i) -> void:
	_pointer = cell
	await await_idle_frame()


func _rings() -> int:
	var count := 0
	for child in game.get_children():
		if child is ActionMenuController:
			count += 1
	return count


func _press_z() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_Z
	key.pressed = true
	game._input(key)
	await await_idle_frame()


# A named tile whose readout says nothing at all, painted onto `cell` -- FOUND in the tileset rather
# than named, so the case does not pin which tiles are authored that way (the content razor).
func _paint_quiet_tile(cell: Vector2i, walkable: bool) -> bool:
	var source := game.grid.tile_set.get_source(GRASS_SOURCE) as TileSetAtlasSource
	for i in range(source.get_tiles_count()):
		game.grid.set_cell(cell, GRASS_SOURCE, source.get_tile_id(i))
		if not TileReadout.compose(game, cell).is_empty() or TileReadout.title_of(game, cell) == "":
			continue
		var board: BoardContext = game._board()
		if walkable and not board.is_walkable(cell):
			continue
		return true
	return false


func test_z_over_an_empty_tile_grows_the_hover_card() -> void:
	var cell := Vector2i(3, 3)
	_set_burning(cell)
	await _point(cell)
	assert_bool(_card().visible).override_failure_message("precondition: no hover card to grow").is_true()

	await _press_z()

	assert_bool(_card().is_grown()).override_failure_message("Z over an empty tile grew nothing").is_true()
	for line in TileReadout.ground_lines(game, cell):
		assert_str(_card_texts()).override_failure_message(
				"the grown card left out a ground line: %s" % line).contains(line)
	assert_str(_card_texts()).contains(Glossary.short(Glossary.Term.BURNING))
	assert_bool(_panel().is_showing()).override_failure_message(
			"an empty tile opened the dock -- the dev ruled that too big").is_false()


func test_z_again_shrinks_it() -> void:
	await _point(Vector2i(3, 3))
	await _press_z()
	assert_bool(_card().is_grown()).is_true()

	await _press_z()

	assert_bool(_card().is_grown()).override_failure_message("a second Z left the card grown").is_false()
	assert_bool(_card().visible).override_failure_message("shrinking hid the card outright").is_true()


func test_moving_to_another_tile_shrinks_it() -> void:
	var cell := Vector2i(3, 3)
	await _point(cell)
	await _press_z()
	assert_bool(_card().is_grown()).is_true()

	await _point(Vector2i(5, 3))

	assert_bool(_card().is_grown()).override_failure_message(
			"the card stayed grown on a tile nobody asked about").is_false()
	await _point(cell)
	assert_bool(_card().is_grown()).override_failure_message(
			"coming back re-grew a card the pointer had left").is_false()


func test_a_left_click_on_an_empty_tile_opens_nothing() -> void:
	var cell := Vector2i(3, 3)
	await _point(cell)

	game._on_left_click(cell)
	await await_idle_frame()

	assert_bool(_panel().is_showing()).override_failure_message(
			"a left-click on an empty tile opened the dock").is_false()
	assert_bool(_card().is_grown()).override_failure_message(
			"a left-click grew the card -- that is the Inspect key's job").is_false()


func test_a_watch_is_named_by_side_unit_and_attack() -> void:
	var watcher := _spawn(ENEMY, Vector2i(2, 1), "Brigand Archer")
	_arm(watcher, WATCHED, "Test Longbow")
	game.refresh_watch_markers()

	await _point(WATCHED)
	await _press_z()

	var texts := _card_texts()
	assert_str(texts).contains(Glossary.title(Glossary.Term.OVERWATCH))
	assert_str(texts).contains(Glossary.short(Glossary.Term.OVERWATCH))
	assert_str(texts).contains("Brigand Archer (%s), Test Longbow" % TileReadout.SIDE_WORDS[ENEMY])


func test_a_watch_whose_mark_is_gone_is_not_named() -> void:
	# THE STORE, NOT THE UNITS. Moved off the cell it aimed from, the watcher's watch still reads
	# armed -- but the anchor rule drops its mark, so the card must drop it too. A card that walked
	# the units would name a watch the board no longer shows.
	var watcher := _spawn(ENEMY, Vector2i(2, 1), "Brigand Archer")
	_arm(watcher, WATCHED)
	watcher.movement.set_cell(Vector2i(2, 3))
	game.refresh_watch_markers()
	assert_bool(watcher.watch.is_armed()).override_failure_message(
			"precondition: the live watch must still read armed, or this proves nothing").is_true()
	assert_array(game.overlay_manager.watch_cells).override_failure_message(
			"precondition: the board must have dropped the mark").not_contains([WATCHED])

	await _point(WATCHED)
	await _press_z()

	assert_bool(_card().is_grown()).is_true()
	assert_str(_card_texts()).override_failure_message(
			"the card named a watch whose reticle is gone").not_contains("Brigand Archer")


func test_two_watches_on_one_cell_are_both_named_and_explained_once() -> void:
	var theirs := _spawn(ENEMY, Vector2i(2, 1), "Brigand Archer")
	var ours := _spawn(PLAYER, Vector2i(6, 1), "Rook")
	_arm(theirs, WATCHED)
	_arm(ours, WATCHED)
	game.refresh_watch_markers()

	await _point(WATCHED)
	await _press_z()

	var texts := _card_texts()
	assert_str(texts).contains("Brigand Archer (%s)" % TileReadout.SIDE_WORDS[ENEMY])
	assert_str(texts).contains("Rook (%s)" % TileReadout.SIDE_WORDS[PLAYER])
	assert_int(texts.count(Glossary.short(Glossary.Term.OVERWATCH))).is_equal(1)


func test_a_capture_zone_is_named_until_it_is_claimed() -> void:
	var cell := Vector2i(5, 3)
	game.zone_manager.paint_cell("Test Point", ZoneManager.Kind.CAPTURE, cell)

	await _point(cell)
	await _press_z()

	var texts := _card_texts()
	assert_str(texts).contains("Test Point")
	assert_str(texts).contains(Glossary.title(Glossary.Term.CAPTURE_ZONE))
	assert_str(texts).override_failure_message(
			"the zone says what it is but not how to take it").contains(
			Glossary.title(Glossary.Term.CAPTURE))

	# Claimed, the board stops tinting it (hidden_zone_names), so the grown card must let go of it
	# too -- without another press.
	game.mission_controller.capture("Test Point")
	await await_idle_frame()

	assert_str(_card_texts()).override_failure_message(
			"a claimed zone the board no longer draws is still named on the card").not_contains("Test Point")


func test_a_patrol_zone_is_never_named() -> void:
	var cell := Vector2i(5, 3)
	_set_burning(cell)
	game.zone_manager.paint_cell("Leash", ZoneManager.Kind.PATROL, cell)
	assert_bool(game.zone_manager.contains("Leash", cell)).is_true()

	await _point(cell)
	await _press_z()

	var texts := _card_texts()
	assert_str(texts).not_contains("Leash")
	# The ground still reads, so the tile was composed at all rather than aborted on the way.
	assert_str(texts).contains(Glossary.short(Glossary.Term.BURNING))


# THE ROCK BUG (dev report, 2026-09-26: "rock clicked from above, showing burning"). A tile with
# nothing to say composes to an empty readout, whose signature is "" -- and "" was also the marker
# for "nothing drawn yet", so the rock never redrew and wore the grass tile's sections before it.
func test_a_tile_with_nothing_to_say_drops_the_last_tiles_sections() -> void:
	var quiet := Vector2i(6, 3)
	assert_bool(_paint_quiet_tile(quiet, false)).override_failure_message(
			"precondition: the tileset has no named tile with an empty readout to test with").is_true()
	var watcher := _spawn(ENEMY, Vector2i(2, 1), "Brigand Archer")
	_arm(watcher, WATCHED)
	_set_burning(WATCHED)
	game.refresh_watch_markers()
	await _point(WATCHED)
	await _press_z()
	assert_str(_card_texts()).override_failure_message(
			"precondition: the first tile drew nothing to go stale").contains("Brigand Archer")

	await _point(quiet)
	await _press_z()

	assert_bool(_card().is_grown()).is_true()
	assert_str(_card_texts()).override_failure_message(
			"the quiet tile is wearing the last tile's watch").not_contains("Brigand Archer")
	assert_str(_card_texts()).override_failure_message(
			"the quiet tile is wearing the last tile's fire").not_contains(
			Glossary.short(Glossary.Term.BURNING))


# ...and the dock's Tile view shares the same diff, so it cannot keep a stale tile either.
func test_a_units_quiet_tile_drops_the_last_units_tile() -> void:
	var quiet := Vector2i(6, 3)
	assert_bool(_paint_quiet_tile(quiet, true)).override_failure_message(
			"precondition: the tileset has no walkable named tile with an empty readout").is_true()
	var first_cell := Vector2i(3, 2)
	_set_burning(first_cell)
	var first := _spawn(PLAYER, first_cell, "Aldin")
	var second := _spawn(PLAYER, quiet, "Aster")
	await _point(first.movement.cell)
	await _press_z()
	await _press_z()
	assert_str(_dock_texts()).override_failure_message(
			"precondition: the first unit's tile drew nothing to go stale").contains(
			Glossary.short(Glossary.Term.BURNING))

	await _point(second.movement.cell)
	await _press_z()
	await _press_z()

	assert_bool(_panel().is_showing_unit(second)).is_true()
	assert_str(_dock_texts()).override_failure_message(
			"the second unit's quiet tile is wearing the first unit's fire").not_contains(
			Glossary.short(Glossary.Term.BURNING))


func test_z_over_a_unit_opens_its_dock_on_the_unit() -> void:
	var unit := _spawn(PLAYER, Vector2i(3, 2), "Aldin")
	await _point(unit.movement.cell)

	await _press_z()

	assert_bool(_panel().is_showing_unit(unit)).override_failure_message(
			"Z over a unit did not open its dock").is_true()
	assert_bool(_panel().stats_section.visible).override_failure_message(
			"the dock opened on the tile rather than the unit").is_true()
	assert_array(_panel().tile_texts()).is_empty()


func test_z_again_shows_its_tile() -> void:
	var cell := Vector2i(3, 2)
	_set_burning(cell)
	var unit := _spawn(PLAYER, cell, "Aldin")
	await _point(cell)
	await _press_z()

	await _press_z()

	assert_bool(_panel().is_showing_unit(unit)).is_true()
	assert_str(_dock_texts()).override_failure_message(
			"a second Z did not swap the dock to the unit's tile").contains(
			Glossary.short(Glossary.Term.BURNING))
	assert_bool(_panel().stats_section.visible).override_failure_message(
			"the unit body is still drawn under the tile").is_false()


# The Unit/Tile buttons beside the portrait do the same swap by mouse.
func test_the_dock_buttons_swap_too() -> void:
	var cell := Vector2i(3, 2)
	_set_burning(cell)
	var unit := _spawn(PLAYER, cell, "Aldin")
	await _point(cell)
	await _press_z()

	_panel().switch_button(UnitInfoPanelControl.View.TILE).pressed.emit()
	await await_idle_frame()
	assert_str(_dock_texts()).contains(Glossary.short(Glossary.Term.BURNING))

	_panel().switch_button(UnitInfoPanelControl.View.UNIT).pressed.emit()
	await await_idle_frame()
	assert_bool(_panel().is_showing_unit(unit)).is_true()
	assert_bool(_panel().stats_section.visible).is_true()
	assert_array(_panel().tile_texts()).is_empty()


func test_a_third_z_closes_the_dock() -> void:
	var unit := _spawn(PLAYER, Vector2i(3, 2), "Aldin")
	await _point(unit.movement.cell)
	await _press_z()
	await _press_z()

	await _press_z()

	assert_bool(_panel().is_showing()).override_failure_message("a third Z left the dock open").is_false()


# One of the two, never both (dev: "Only one of the two should appear at a time"). With the dock on
# a unit's tile, pointing at that unit must not also put its tile on the hover card.
func test_the_units_open_tile_is_not_repeated_on_the_hover_card() -> void:
	var cell := Vector2i(3, 2)
	var unit := _spawn(PLAYER, cell, "Aldin")
	await _point(cell)
	await _press_z()
	await _press_z()
	assert_bool(_panel().is_showing_unit(unit)).is_true()

	assert_bool(_card().visible).override_failure_message(
			"the hover card repeats the tile the dock is already showing").is_false()


# Inspect left the ring (#1105), so a unit with nothing else to offer -- an enemy on your turn --
# would open an EMPTY ring. It opens none. A unit of yours still opens one, which is what shows the
# check below can see a ring at all.
func test_clicking_an_enemy_opens_no_ring() -> void:
	var enemy := _spawn(ENEMY, Vector2i(5, 2), "Brigand")
	var ours := _spawn(PLAYER, Vector2i(2, 2), "Aldin")

	game._on_left_click(enemy.movement.cell)
	await await_idle_frame()

	assert_int(_rings()).override_failure_message(
			"clicking an enemy opened an empty ring").is_equal(0)
	assert_int(game.game_state).is_equal(game.GameState.IDLE)

	game._on_left_click(ours.movement.cell)
	await await_idle_frame()
	assert_int(_rings()).override_failure_message(
			"precondition: a unit of yours opened no ring, so this check sees nothing").is_greater(0)


func test_the_ring_offers_no_inspect() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2), "Aldin")
	var tree: Array = game.main_action_menu.build_tree(unit)
	assert_array(tree).override_failure_message("precondition: the ring built nothing").is_not_empty()
	for node: Dictionary in tree:
		assert_str(String(node.get("name", ""))).override_failure_message(
				"the ring still offers Inspect -- it moved to the Z key").is_not_equal("Inspect")


# The dock is as tall as the screen, so a unit's tile stacked past it must SCROLL rather than run
# off the bottom -- test_unit_info_panel_refresh's height law, asked of the Tile view. Three
# watches, two zones and a fire on one cell is busier than any authored board makes a single tile.
func test_a_busy_units_tile_scrolls_inside_the_dock() -> void:
	var cell := Vector2i(4, 2)
	_set_burning(cell)
	for i in range(3):
		var watcher := _spawn(ENEMY if i != 1 else PLAYER, Vector2i(i, 0), "Watcher Number %d" % i)
		_arm(watcher, cell, "A Long Attack Name %d" % i)
	game.refresh_watch_markers()
	game.zone_manager.paint_cell("The Far Ground", ZoneManager.Kind.CAPTURE, cell)
	game.zone_manager.paint_cell("The Landing Field", ZoneManager.Kind.DEPLOYMENT, cell)
	_spawn(PLAYER, cell, "Aldin")

	await _point(cell)
	await _press_z()
	await _press_z()
	await await_idle_frame()

	assert_int(_panel().tile_texts().size()).override_failure_message(
			"precondition: the tile body drew nothing, so this measures nothing").is_greater(8)
	var body: Control = _panel().get_node("UnitInfoPanel/Margin/VBox")
	assert_float(body.get_combined_minimum_size().y).override_failure_message(
			"a busy tile wants %d of the %d the dock has -- its bottom rows are off screen"
				% [body.get_combined_minimum_size().y, _panel().size.y]).is_less_equal(_panel().size.y)
	var scroll: ScrollContainer = _panel()._tile_scroll
	var dock: Rect2 = (_panel().get_node("UnitInfoPanel") as Control).get_global_rect()
	assert_float(scroll.get_global_rect().end.y).override_failure_message(
			"the tile's scroll area itself runs off the dock").is_less_equal(dock.end.y)
	assert_bool(scroll.get_v_scroll_bar().visible).override_failure_message(
			"the overflow has no scrollbar, so its last rows cannot be reached").is_true()


# ...and the scroll is a safety net, never the ordinary look (dev, 2026-09-23): a watch, a zone and a
# fire together still fit without a bar.
func test_an_ordinary_units_tile_shows_no_scrollbar() -> void:
	var cell := Vector2i(4, 2)
	_set_burning(cell)
	_arm(_spawn(ENEMY, Vector2i(0, 0), "Brigand Archer"), cell, "Longbow")
	game.refresh_watch_markers()
	game.zone_manager.paint_cell("The Far Ground", ZoneManager.Kind.CAPTURE, cell)
	_spawn(PLAYER, cell, "Aldin")

	await _point(cell)
	await _press_z()
	await _press_z()
	await await_idle_frame()

	assert_str(_dock_texts()).contains("The Far Ground")
	assert_bool(_panel()._tile_scroll.get_v_scroll_bar().visible).override_failure_message(
			"an ordinary tile needed a scrollbar -- the tile body is not getting the dock's height").is_false()


# The grown card cannot scroll -- the pointer is on the board -- so it has to fit. The busiest tile
# the dock's scroll case builds is the measure (636 of 704 when this was written).
func test_the_grown_card_stays_on_screen() -> void:
	var cell := Vector2i(4, 2)
	_set_burning(cell)
	for i in range(3):
		var watcher := _spawn(ENEMY if i != 1 else PLAYER, Vector2i(i, 0), "Watcher Number %d" % i)
		_arm(watcher, cell, "A Long Attack Name %d" % i)
	game.refresh_watch_markers()
	game.zone_manager.paint_cell("The Far Ground", ZoneManager.Kind.CAPTURE, cell)
	game.zone_manager.paint_cell("The Landing Field", ZoneManager.Kind.DEPLOYMENT, cell)

	await _point(cell)
	await _press_z()
	for i in range(3):
		await await_idle_frame()

	assert_int(_card().grown_texts().size()).override_failure_message(
			"precondition: the grown card drew nothing, so this measures nothing").is_greater(8)
	var screen: Rect2 = _card().get_viewport_rect()
	var tile_block: Rect2 = _card()._tile_panel.get_global_rect()
	assert_float(tile_block.position.y).override_failure_message(
			"the grown card starts above the screen").is_greater_equal(0.0)
	assert_float(tile_block.end.y).override_failure_message(
			"the grown card runs off the bottom (%d of %d)" % [tile_block.end.y, screen.size.y]) \
			.is_less_equal(screen.size.y)


func test_z_off_the_map_does_nothing() -> void:
	await _point(Vector2i(50, 50))

	await _press_z()

	assert_bool(_card().is_grown()).is_false()
	assert_bool(_panel().is_showing()).is_false()


func test_z_works_in_the_pre_mission_phase() -> void:
	game.game_state = game.GameState.PRE_MISSION
	await _point(Vector2i(3, 3))

	await _press_z()

	assert_bool(_card().is_grown()).override_failure_message(
			"Z did nothing while deploying").is_true()
