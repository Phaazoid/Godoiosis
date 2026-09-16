# The hover tier of the enemy-intent preview (#710), through the REAL triggers: a hovered
# destination in CHOOSING_MOVE draws one line per enemy that could reach it, an enemy under the
# pointer shows its reach and its leash, the T toggle fills the whole field and reveals every
# sentry's zone, and a queued order drops the cached field. Fixture is #114's -- the instanced
# root MUST be named "Main" under /root.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const ZONE := "post"

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
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _om() -> OverlayManager:
	return game.overlay_manager


func _spawn(faction: Team.Faction, cell: Vector2i, archetype := AIArchetype.Type.HOLD) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()   # fixture setup, not the claim under test
	unit.equipped_weapon = H.make_weapon()
	unit.squad.archetype = archetype
	return unit


# A sentry leashed to a 2x2 room painted around it.
func _spawn_sentry(cell: Vector2i) -> Unit:
	var sentry: Unit = _spawn(ENEMY, cell, AIArchetype.Type.SENTRY)
	for dx in [0, 1]:
		for dy in [0, 1]:
			game.zone_manager.paint_cell(ZONE, ZoneManager.Kind.PATROL, cell + Vector2i(dx, dy))
	sentry.squad.zone_name = ZONE
	sentry.squad.home_cell = cell
	return sentry


func _sorted(cells: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = cells.duplicate()
	out.sort()
	return out


func _hover_destination(mover: Unit, cell: Vector2i) -> void:
	game.enter_move_mode(mover)
	game.selected_unit = mover
	game.hover_presenter._hover_choosing_move(cell)


func test_hovering_a_threatened_destination_draws_one_line_per_enemy_that_can_reach_it() -> void:
	var mover := _spawn(PLAYER, Vector2i(1, 1))
	var east := _spawn(ENEMY, Vector2i(3, 2))    # reaches (2, 2)
	var south := _spawn(ENEMY, Vector2i(2, 3))   # reaches (2, 2)
	_hover_destination(mover, Vector2i(2, 2))
	var lines: Array[PackedVector3Array] = _om().threat_lines
	assert_int(lines.size()).is_equal(2)
	# Every line ENDS on the hovered cell, in trace space: cell centre, eye height.
	var end := Vector3(2.5, Reach.EYE_HEIGHT, 2.5)
	var starts: Array[Vector3] = []
	for line in lines:
		assert_that(line[line.size() - 1]).is_equal(end)
		starts.append(line[0])
	assert_bool(starts.has(Vector3(3.5, Reach.EYE_HEIGHT, 2.5))).override_failure_message(
			"no line from %s" % east.movement.cell).is_true()
	assert_bool(starts.has(Vector3(2.5, Reach.EYE_HEIGHT, 3.5))).override_failure_message(
			"no line from %s" % south.movement.cell).is_true()
	game.exit_current_mode()
	assert_array(_om().threat_lines).is_empty()


func test_hovering_a_safe_destination_draws_nothing() -> void:
	var mover := _spawn(PLAYER, Vector2i(1, 1))
	_spawn(ENEMY, Vector2i(3, 3))   # a Hold unit two steps away from (1, 2)
	_hover_destination(mover, Vector2i(1, 2))
	assert_array(_om().threat_lines).is_empty()


func test_hovering_an_enemy_shows_its_reach_and_its_leash_and_leaving_clears_both() -> void:
	var sentry := _spawn_sentry(Vector2i(3, 2))
	game.hover_presenter.update_hover_visuals(sentry.movement.cell)
	var field: ThreatField = game.threat_field()
	assert_that(_sorted(_om().danger_overlay.get_used_cells())).is_equal(_sorted(field.reach_of(sentry)))
	assert_bool(_om().danger_overlay.get_used_cells().size() > 0).is_true()
	assert_that(_sorted(_om().zone_highlight_overlay.get_used_cells())) \
		.is_equal(_sorted(game.zone_manager.cells_in(ZONE)))
	assert_bool(_om().zone_highlight_overlay.visible).override_failure_message(
			"the leash is painted but the layer is hidden -- the reveal never reached the gate").is_true()
	assert_bool(_om().zone_overlay.visible).override_failure_message(
			"the patrol layer itself leaked into play; only the ONE leash is revealed").is_false()
	game.hover_presenter.update_hover_visuals(Vector2i(0, 0))
	assert_array(_om().danger_overlay.get_used_cells()).is_empty()
	assert_array(_om().zone_highlight_overlay.get_used_cells()).is_empty()
	assert_bool(_om().zone_highlight_overlay.visible).is_false()


func test_the_toggle_fills_the_whole_field_and_reveals_every_leash() -> void:
	_spawn_sentry(Vector2i(3, 2))
	_spawn(ENEMY, Vector2i(2, 3))   # a second, unleashed enemy inside the boot board
	game.toggle_threat_view()
	assert_bool(game.threat_view_on).is_true()
	var field: ThreatField = game.threat_field()
	assert_that(_sorted(_om().danger_overlay.get_used_cells())).is_equal(_sorted(field.all_cells()))
	assert_int(_om().danger_overlay.get_used_cells().size()).is_greater(4)   # both enemies, not one
	assert_that(_sorted(_om().zone_highlight_overlay.get_used_cells())) \
		.is_equal(_sorted(game.zone_manager.cells_in(ZONE)))
	assert_bool(_om().zone_highlight_overlay.visible).is_true()
	# Hovering elsewhere does not tear the toggled view down -- it belongs to the key, not the pointer.
	game.hover_presenter.update_hover_visuals(Vector2i(0, 0))
	assert_bool(_om().danger_overlay.get_used_cells().size() > 0).is_true()
	game.toggle_threat_view()
	assert_bool(game.threat_view_on).is_false()
	assert_array(_om().danger_overlay.get_used_cells()).is_empty()
	assert_array(_om().zone_highlight_overlay.get_used_cells()).is_empty()


func test_the_toggle_stands_down_for_the_tile_brush() -> void:
	# The highlight layer has two writers; the brush's pick wins while its tab is up.
	_spawn_sentry(Vector2i(3, 2))
	_om().set_zone_visibility(true)
	game.toggle_threat_view()
	assert_array(_om().zone_highlight_overlay.get_used_cells()).is_empty()
	game.toggle_threat_view()
	_om().set_zone_visibility(false)


func test_a_queued_order_drops_the_cached_field() -> void:
	var mover := _spawn(PLAYER, Vector2i(1, 1))
	_spawn(ENEMY, Vector2i(4, 1))
	var before: ThreatField = game.threat_field()
	assert_object(game.threat_field()).is_same(before)   # cached between reads
	game.enter_move_mode(mover)
	game.selected_unit = mover
	game._click_choosing_move(Vector2i(1, 2))
	assert_int(mover.squad.action_queue.size()).is_greater(0)   # the order really queued
	assert_object(game.threat_field()).is_not_same(before)
