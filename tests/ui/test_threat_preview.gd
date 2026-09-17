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


# --- The exact tier's cadence (#710 slice 2) ---------------------------------------------------

# The preview only speaks for factions the AI actually DRIVES -- an unmanaged faction is nobody's
# to predict. clear_board() empties that set, so every case below has to put the enemy back.
func _enable_enemy_ai() -> void:
	game.ai_controller.set_faction_ai_enabled(ENEMY, true)

# The debounce's whole job: a burst of orders costs ONE recompute. threat_plan_version is the only
# observable -- the intents themselves are identical either way, so counting is the test.
func test_a_burst_of_orders_costs_one_recompute() -> void:
	var mover := _spawn(PLAYER, Vector2i(1, 1))
	_spawn(ENEMY, Vector2i(4, 1))
	var before: int = game.threat_plan_version

	game._restart_threat_plan()
	game._restart_threat_plan()
	game._restart_threat_plan()
	assert_int(game.threat_plan_version).override_failure_message(
			"the preview ran while the timer was still counting -- the debounce is not debouncing").is_equal(before)
	assert_bool(game._threat_plan_timer.is_stopped()).is_false()

	game.refresh_threat_plan()   # what the timeout does
	assert_int(game.threat_plan_version).is_equal(before + 1)
	assert_bool(game._threat_plan_timer.is_stopped()).override_failure_message(
			"a recompute left the timer running -- it would fire a second time").is_true()
	assert_object(mover).is_not_null()


func test_execute_stops_a_pending_recompute() -> void:
	_spawn(PLAYER, Vector2i(1, 1))
	_spawn(ENEMY, Vector2i(4, 1))
	game._restart_threat_plan()
	assert_bool(game._threat_plan_timer.is_stopped()).is_false()

	game._on_queue_execute_requested()   # no active squad, so it returns early -- after stopping the timer
	assert_bool(game._threat_plan_timer.is_stopped()).override_failure_message(
			"a recompute was still pending over a board that is about to move").is_true()


# The exact tier draws a line per intent and a number on it, and the toggle asks for it immediately
# rather than after the debounce.
func test_the_toggle_draws_intent_lines_with_their_numbers() -> void:
	_enable_enemy_ai()
	var mover := _spawn(PLAYER, Vector2i(1, 1))
	_spawn(ENEMY, Vector2i(3, 2))
	game.enter_move_mode(mover)
	game.selected_unit = mover
	game._click_choosing_move(Vector2i(2, 2))   # walk into reach, for real
	game.refresh_threat_plan()

	assert_int(_om().intent_lines.size()).override_failure_message(
			"no intent line for a unit standing next to an enemy").is_equal(1)
	assert_int(_om().intent_labels.size()).is_equal(1)
	assert_str(str(_om().intent_labels[0]["text"])).is_not_equal("0")
	var seg: PackedVector3Array = _om().intent_lines[0]
	assert_that(Vector2i(int(seg[1].x - 0.5), int(seg[1].z - 0.5))).override_failure_message(
			"the line does not end on the unit it names").is_equal(Vector2i(2, 2))


func test_the_intent_channel_clears_on_board_load() -> void:
	_enable_enemy_ai()
	var mover := _spawn(PLAYER, Vector2i(1, 1))
	_spawn(ENEMY, Vector2i(3, 2))
	game.enter_move_mode(mover)
	game.selected_unit = mover
	game._click_choosing_move(Vector2i(2, 2))
	game.refresh_threat_plan()
	assert_bool(_om().intent_lines.size() > 0).is_true()

	game._clear_threat_plan()
	assert_array(_om().intent_lines).is_empty()
	assert_array(_om().intent_labels).is_empty()
