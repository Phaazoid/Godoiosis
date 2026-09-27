# THE INFO CARD ON CLICK (#1105, dev 2026-09-27: "Nothing on hover, at all. While the radial menu is
# up for a unit, we get that unit's card up. Inspect from the menu brings up the full one. For tiles,
# nothing on hover. Clicking a tile brings up the full tile for it.")
#
# So: hovering shows no card; a unit's ring carries that unit's card for exactly as long as it is
# up; the ring's Inspect opens the dock AND the tile the unit stands on, in the card beside the dock;
# clicking an empty tile shows its full card. Right-click closes a card before it undoes an order.
#
# Clicks go through game._on_left_click / _on_right_click, the doors the 3D host calls. Ring picks go
# through the REAL controller (aim_at + commit), because the card's lifetime rides the controller's
# own cancelled-before-action_selected ordering. The pointer rides HoverPresenter.pointer_source, the
# seam the 3D picker uses. Expectations come off the seams (TileReadout, Glossary, ACTION_DATA),
# never off authored content -- the content razor, tests/README.md #9.
#
# Fixture is tests/flow/test_watch_shot_interrupts_the_walk.gd's (tests/README.md -> Testing the
# game scene).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const MD := preload("res://tests/support/menu_drive.gd")
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
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func _panel() -> UnitInfoPanelControl:
	return game.unit_info_panel


func _card() -> HoverInfoPanelControl:
	return game.hover_info_panel


func _card_texts() -> String:
	return "\n".join(_card().tile_texts())


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


func _click(cell: Vector2i) -> void:
	game._on_left_click(cell)
	await await_idle_frame()


func _ring() -> ActionMenuController:
	return MD.controller_of(game)


func _verb_name(id: int) -> String:
	return String(MainActionMenu.ACTION_DATA[id]["name"])


# Pick a ring leaf the way the mouse does -- aim into its slice, then commit -- level by level.
func _pick(id: int) -> void:
	var ring := _ring()
	assert_object(ring).override_failure_message("no ring is open to pick from").is_not_null()
	var path := MD.path_to(ring.level_nodes(), _verb_name(id))
	assert_bool(path.is_empty()).override_failure_message(
			"the ring offers no %s" % _verb_name(id)).is_false()
	for index in path:
		ring.aim_at(ring.point_in_slice(index))
		ring.commit()
	await await_idle_frame()


# Orders the player gave -- hold-position fillers are nobody's order.
func _orders(unit: Unit) -> int:
	var count := 0
	for action: BaseAction in unit.squad.action_queue:
		if action is MoveAction and (action as MoveAction).is_hold_position:
			continue
		count += 1
	return count


# A named tile whose readout says nothing at all, painted onto `cell` -- FOUND in the tileset rather
# than named, so the case does not pin which tiles are authored that way (the content razor).
func _paint_quiet_tile(cell: Vector2i) -> bool:
	var source := game.grid.tile_set.get_source(GRASS_SOURCE) as TileSetAtlasSource
	for i in range(source.get_tiles_count()):
		game.grid.set_cell(cell, GRASS_SOURCE, source.get_tile_id(i))
		if TileReadout.compose(game, cell).is_empty() and TileReadout.title_of(game, cell) != "":
			return true
	return false


# Three watches, two zones and a fire on one cell -- busier than any authored board makes a single
# tile, and the measure the card was sized against (675 of 704 since #955 split its zones by kind).
func _build_busy_tile(cell: Vector2i) -> void:
	_set_burning(cell)
	for i in range(3):
		var watcher := _spawn(ENEMY if i != 1 else PLAYER, Vector2i(i, 0), "Watcher Number %d" % i)
		_arm(watcher, cell, "A Long Attack Name %d" % i)
	game.refresh_watch_markers()
	game.zone_manager.paint_cell("The Far Ground", ZoneManager.Kind.CAPTURE, cell)
	game.zone_manager.paint_cell("The Landing Field", ZoneManager.Kind.DEPLOYMENT, cell)


# ------------------------------------------------------------------------------
#  Nothing on hover
# ------------------------------------------------------------------------------

func test_hovering_shows_no_card() -> void:
	var cell := Vector2i(3, 3)
	_set_burning(cell)
	var ours := _spawn(PLAYER, Vector2i(1, 2), "Aldin")
	var theirs := _spawn(ENEMY, Vector2i(6, 2), "Brigand")

	for spot: Vector2i in [cell, ours.movement.cell, theirs.movement.cell]:
		await _point(spot)
		assert_bool(_card().visible).override_failure_message(
				"hovering %s put up a card -- nothing shows on hover" % str(spot)).is_false()


# ------------------------------------------------------------------------------
#  A unit's ring carries its card
# ------------------------------------------------------------------------------

func test_clicking_your_unit_opens_its_ring_with_its_card_up() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2), "Aldin")

	await _click(unit.movement.cell)

	assert_object(_ring()).override_failure_message("clicking your unit opened no ring").is_not_null()
	assert_bool(_card().visible and _card().is_showing_unit_card()).override_failure_message(
			"the ring is up without its unit's card").is_true()
	assert_object(_card().current_unit).is_same(unit)


func test_dismissing_the_ring_takes_the_card_away() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2), "Aldin")
	await _click(unit.movement.cell)
	assert_bool(_card().is_showing_unit_card()).is_true()

	_ring().dismiss()
	await await_idle_frame()

	assert_bool(_card().visible).override_failure_message(
			"the unit card outlived the ring it came with").is_false()


func test_picking_move_takes_the_card_away() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2), "Aldin")
	await _click(unit.movement.cell)

	await _pick(MainActionMenu.MOVE)

	assert_int(game.game_state).override_failure_message(
			"precondition: picking Move did not enter the move pick").is_equal(game.GameState.CHOOSING_MOVE)
	assert_bool(_card().visible).override_failure_message(
			"the unit card stayed up after a verb closed the ring").is_false()


# An enemy's ring holds Inspect alone, and its card is up while that ring is.
func test_clicking_an_enemy_opens_its_ring_with_its_card() -> void:
	var enemy := _spawn(ENEMY, Vector2i(5, 2), "Brigand")

	await _click(enemy.movement.cell)

	assert_object(_ring()).override_failure_message("clicking an enemy opened no ring").is_not_null()
	assert_array(MD.path_to(_ring().level_nodes(), _verb_name(MainActionMenu.INSPECT))).override_failure_message(
			"an enemy's ring does not offer Inspect").is_not_empty()
	assert_object(_card().current_unit).is_same(enemy)


func test_with_the_dock_on_that_unit_clicking_it_shows_no_second_card() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2), "Aldin")
	await _click(unit.movement.cell)
	await _pick(MainActionMenu.INSPECT)
	assert_bool(_panel().is_showing_unit(unit)).is_true()

	await _click(unit.movement.cell)

	assert_bool(_card().is_showing_unit_card()).override_failure_message(
			"a unit card for the unit the dock already shows").is_false()
	assert_bool(_card().is_showing_tile()).override_failure_message(
			"the ring took down the tile card that sits beside the dock").is_true()


# ------------------------------------------------------------------------------
#  Inspect: the dock, and the tile card beside it
# ------------------------------------------------------------------------------

func test_the_ring_offers_inspect_again() -> void:
	var unit := _spawn(PLAYER, Vector2i(2, 2), "Aldin")
	assert_array(MD.path_to(game.main_action_menu.build_tree(unit), _verb_name(MainActionMenu.INSPECT))) \
			.override_failure_message("the ring has no Inspect").is_not_empty()


func test_inspect_opens_the_dock_with_its_tile_card_beside_it() -> void:
	var cell := Vector2i(3, 2)
	_set_burning(cell)
	var unit := _spawn(PLAYER, cell, "Aldin")
	await _click(cell)

	await _pick(MainActionMenu.INSPECT)

	assert_bool(_panel().is_showing_unit(unit)).override_failure_message("Inspect opened no dock").is_true()
	assert_bool(_card().visible and _card().is_showing_tile_at(cell)).override_failure_message(
			"Inspect did not open the unit's tile card").is_true()
	assert_str(_card_texts()).contains(Glossary.short(Glossary.Term.BURNING))
	assert_float(_card().position.x).override_failure_message(
			"the tile card is under the dock rather than beside it").is_greater_equal(_panel().panel_width())


func test_closing_the_dock_closes_both() -> void:
	var unit := _spawn(PLAYER, Vector2i(3, 2), "Aldin")
	await _click(unit.movement.cell)
	await _pick(MainActionMenu.INSPECT)
	assert_bool(_card().is_showing_tile()).is_true()

	(_panel().get_node("UnitInfoPanel/Margin/VBox/HeaderRow/CloseButton") as Button).pressed.emit()
	await await_idle_frame()

	assert_bool(_panel().is_showing()).is_false()
	assert_bool(_card().visible).override_failure_message(
			"the tile card outlived the dock it was opened beside").is_false()


# The dock stays open through Execute, so the unit can walk while its tile card is up. The card goes
# with it: one fixed on the old cell would describe where the unit used to stand.
func test_the_tile_card_follows_its_unit() -> void:
	var start := Vector2i(3, 2)
	var there := Vector2i(5, 3)
	_set_burning(start)
	game.zone_manager.paint_cell("Test Point", ZoneManager.Kind.CAPTURE, there)
	var unit := _spawn(PLAYER, start, "Aldin")
	await _click(start)
	await _pick(MainActionMenu.INSPECT)
	assert_str(_card_texts()).contains(Glossary.short(Glossary.Term.BURNING))

	unit.movement.set_cell(there)
	await await_idle_frame()

	assert_str(_card_texts()).override_failure_message(
			"the tile card stayed on the cell the unit left").contains("Test Point")
	assert_str(_card_texts()).not_contains(Glossary.short(Glossary.Term.BURNING))


# ------------------------------------------------------------------------------
#  Clicking a tile
# ------------------------------------------------------------------------------

func test_clicking_an_empty_tile_shows_its_full_card() -> void:
	var cell := Vector2i(3, 3)
	_set_burning(cell)

	await _click(cell)

	assert_bool(_card().visible and _card().is_showing_tile_at(cell)).override_failure_message(
			"clicking an empty tile showed no card").is_true()
	assert_str(_card_texts()).contains(TileReadout.title_of(game, cell))
	for line in TileReadout.ground_lines(game, cell):
		assert_str(_card_texts()).override_failure_message(
				"the card left out a ground line: %s" % line).contains(line)
	assert_bool(_panel().is_showing()).override_failure_message(
			"an empty tile opened the dock").is_false()
	assert_object(_ring()).override_failure_message("an empty tile opened a ring").is_null()


func test_clicking_it_again_closes_it() -> void:
	var cell := Vector2i(3, 3)
	await _click(cell)
	assert_bool(_card().is_showing_tile_at(cell)).is_true()

	await _click(cell)

	assert_bool(_card().visible).override_failure_message("a second click left the card up").is_false()


func test_clicking_another_tile_swaps_it() -> void:
	var first := Vector2i(3, 3)
	var second := Vector2i(6, 1)
	_set_burning(first)
	await _click(first)

	await _click(second)

	assert_bool(_card().is_showing_tile_at(second)).override_failure_message(
			"clicking another tile did not move the card to it").is_true()
	assert_str(_card_texts()).not_contains(Glossary.short(Glossary.Term.BURNING))


# THE GIANT CARD (dev report, 2026-09-27: "giant display"). A second tile with the SAME readout settles
# to exactly the height the first one had, so a shrink that waits for the minimum to change never
# comes -- and every case above clicks two tiles of different heights.
func _assert_fits() -> void:
	for i in range(3):
		await await_idle_frame()
	var panel: Control = _card()._tile_panel
	var wanted: float = panel.get_combined_minimum_size().y
	assert_float(panel.size.y).override_failure_message(
			"the card is %d tall for %d of content" % [panel.size.y, wanted]).is_less_equal(wanted + 1.0)
	var rect: Rect2 = panel.get_global_rect()
	var screen: Rect2 = _card().get_viewport_rect()
	assert_float(rect.position.y).override_failure_message("the card starts above the screen") \
			.is_greater_equal(0.0)
	assert_float(rect.end.y).override_failure_message(
			"the card runs off the bottom (%d of %d)" % [rect.end.y, screen.size.y]).is_less_equal(screen.size.y)


func _settle() -> void:
	for i in range(3):
		await await_idle_frame()


func test_a_second_tile_with_the_same_readout_keeps_the_card_its_size() -> void:
	var first := Vector2i(3, 3)
	var second := Vector2i(5, 3)
	assert_str(TileReadout.signature(TileReadout.compose(game, second))).override_failure_message(
			"precondition: the two tiles must say the same thing").is_equal(
			TileReadout.signature(TileReadout.compose(game, first)))
	await _click(first)
	await _settle()

	await _click(second)

	await _assert_fits()


func test_the_same_readout_across_a_unit_card_keeps_the_card_its_size() -> void:
	var unit := _spawn(PLAYER, Vector2i(1, 1), "Aldin")
	await _click(Vector2i(3, 3))
	await _settle()
	await _click(unit.movement.cell)
	_ring().dismiss()
	await _settle()

	await _click(Vector2i(5, 3))

	await _assert_fits()


func test_a_click_off_the_map_closes_the_card() -> void:
	await _click(Vector2i(3, 3))
	assert_bool(_card().visible).is_true()

	await _click(Vector2i(50, 50))

	assert_bool(_card().visible).override_failure_message(
			"a click off the map left a card up, or opened an empty one").is_false()


func test_an_empty_tile_shows_its_card_while_deploying() -> void:
	game.game_state = game.GameState.PRE_MISSION
	var cell := Vector2i(3, 3)
	assert_bool(game.mission_controller.open_deployment_cells().has(cell)).override_failure_message(
			"precondition: the cell must not be a deployment cell, or it opens the deploy menu").is_false()

	await _click(cell)

	assert_bool(_card().is_showing_tile_at(cell)).override_failure_message(
			"clicking a tile while deploying showed no card").is_true()


# ------------------------------------------------------------------------------
#  Right-click closes a card before it undoes
# ------------------------------------------------------------------------------

func test_right_click_closes_the_card_and_keeps_your_order() -> void:
	var unit := _spawn(PLAYER, Vector2i(1, 2), "Aldin")
	await _click(unit.movement.cell)
	await _pick(MainActionMenu.MOVE)
	var step := GridUtils.NO_CELL
	for cell: Vector2i in game.compute_move_range(unit).reachable.keys():
		if cell != unit.movement.cell:
			step = cell
			break
	await _click(step)
	assert_int(_orders(unit)).override_failure_message("precondition: no order was queued").is_equal(1)
	var empty := Vector2i(7, 4) if unit.get_projected_destination() != Vector2i(7, 4) else Vector2i(7, 3)
	await _click(empty)
	assert_bool(_card().is_showing_tile()).override_failure_message("precondition: no card to close").is_true()

	game._on_right_click()

	assert_bool(_card().visible).override_failure_message("right-click left the card up").is_false()
	assert_int(_orders(unit)).override_failure_message(
			"closing the card cost the player their order").is_equal(1)

	game._on_right_click()   # nothing is open now, so this one reaches the queue as before

	assert_int(game.game_state).override_failure_message(
			"the second press did not reach the queue").is_equal(game.GameState.CHOOSING_MOVE)


# ------------------------------------------------------------------------------
#  What the tile card says
# ------------------------------------------------------------------------------

func test_a_watch_is_named_by_side_unit_and_attack() -> void:
	var watcher := _spawn(ENEMY, Vector2i(2, 1), "Brigand Archer")
	_arm(watcher, WATCHED, "Test Longbow")
	game.refresh_watch_markers()

	await _click(WATCHED)

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

	await _click(WATCHED)

	assert_bool(_card().is_showing_tile()).is_true()
	assert_str(_card_texts()).override_failure_message(
			"the card named a watch whose reticle is gone").not_contains("Brigand Archer")


func test_two_watches_on_one_cell_are_both_named_and_explained_once() -> void:
	var theirs := _spawn(ENEMY, Vector2i(2, 1), "Brigand Archer")
	var ours := _spawn(PLAYER, Vector2i(6, 1), "Rook")
	_arm(theirs, WATCHED)
	_arm(ours, WATCHED)
	game.refresh_watch_markers()

	await _click(WATCHED)

	var texts := _card_texts()
	assert_str(texts).contains("Brigand Archer (%s)" % TileReadout.SIDE_WORDS[ENEMY])
	assert_str(texts).contains("Rook (%s)" % TileReadout.SIDE_WORDS[PLAYER])
	assert_int(texts.count(Glossary.short(Glossary.Term.OVERWATCH))).is_equal(1)


func test_a_capture_zone_is_named_until_it_is_claimed() -> void:
	var cell := Vector2i(5, 3)
	game.zone_manager.paint_cell("Test Point", ZoneManager.Kind.CAPTURE, cell)

	await _click(cell)

	var texts := _card_texts()
	assert_str(texts).contains("Test Point")
	assert_str(texts).contains(Glossary.title(Glossary.Term.CAPTURE_ZONE))
	assert_str(texts).override_failure_message(
			"the zone says what it is but not how to take it").contains(
			Glossary.title(Glossary.Term.CAPTURE))

	# Claimed, the board stops tinting it (hidden_zone_names), so the card must let go of it too --
	# without another click.
	game.mission_controller.capture("Test Point")
	await await_idle_frame()

	assert_str(_card_texts()).override_failure_message(
			"a claimed zone the board no longer draws is still named on the card").not_contains("Test Point")


func test_a_patrol_zone_is_never_named() -> void:
	var cell := Vector2i(5, 3)
	_set_burning(cell)
	game.zone_manager.paint_cell("Leash", ZoneManager.Kind.PATROL, cell)
	assert_bool(game.zone_manager.contains("Leash", cell)).is_true()

	await _click(cell)

	var texts := _card_texts()
	assert_str(texts).not_contains("Leash")
	# The ground still reads, so the tile was composed at all rather than aborted on the way.
	assert_str(texts).contains(Glossary.short(Glossary.Term.BURNING))


# THE ROCK BUG (dev report, 2026-09-26: "rock clicked from above, showing burning"). A tile with
# nothing to say composes to an empty readout, whose signature is "" -- and "" was also the marker
# for "nothing drawn yet", so the rock never redrew and wore the grass tile's sections before it.
func test_a_tile_with_nothing_to_say_drops_the_last_tiles_sections() -> void:
	var quiet := Vector2i(6, 3)
	assert_bool(_paint_quiet_tile(quiet)).override_failure_message(
			"precondition: the tileset has no named tile with an empty readout to test with").is_true()
	var watcher := _spawn(ENEMY, Vector2i(2, 1), "Brigand Archer")
	_arm(watcher, WATCHED)
	_set_burning(WATCHED)
	game.refresh_watch_markers()
	await _click(WATCHED)
	assert_str(_card_texts()).override_failure_message(
			"precondition: the first tile drew nothing to go stale").contains("Brigand Archer")

	await _click(quiet)

	assert_bool(_card().is_showing_tile_at(quiet)).is_true()
	assert_str(_card_texts()).override_failure_message(
			"the quiet tile is wearing the last tile's watch").not_contains("Brigand Archer")
	assert_str(_card_texts()).override_failure_message(
			"the quiet tile is wearing the last tile's fire").not_contains(
			Glossary.short(Glossary.Term.BURNING))


# ------------------------------------------------------------------------------
#  The card cannot scroll, so it has to fit
# ------------------------------------------------------------------------------

func _assert_on_screen() -> void:
	for i in range(3):
		await await_idle_frame()
	assert_int(_card().tile_texts().size()).override_failure_message(
			"precondition: the card drew nothing, so this measures nothing").is_greater(8)
	var screen: Rect2 = _card().get_viewport_rect()
	var tile_card: Rect2 = _card()._tile_panel.get_global_rect()
	assert_float(tile_card.position.y).override_failure_message(
			"the tile card starts above the screen").is_greater_equal(0.0)
	assert_float(tile_card.end.y).override_failure_message(
			"the tile card runs off the bottom (%d of %d)" % [tile_card.end.y, screen.size.y]) \
			.is_less_equal(screen.size.y)


func test_the_busiest_tile_card_stays_on_screen() -> void:
	var cell := Vector2i(4, 2)
	_build_busy_tile(cell)

	await _click(cell)

	await _assert_on_screen()


func test_the_busiest_tile_card_beside_the_dock_stays_on_screen() -> void:
	var cell := Vector2i(4, 2)
	_build_busy_tile(cell)
	_spawn(PLAYER, cell, "Aldin")
	await _click(cell)
	await _pick(MainActionMenu.INSPECT)

	await _assert_on_screen()
	var dock: Rect2 = (_panel().get_node("UnitInfoPanel") as Control).get_global_rect()
	assert_float(_card()._tile_panel.get_global_rect().position.x).override_failure_message(
			"the tile card overlaps the dock").is_greater_equal(dock.end.x)
