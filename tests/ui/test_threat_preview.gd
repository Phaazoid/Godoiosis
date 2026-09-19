# The enemy range and intent views (#710), through the REAL triggers: an enemy under the pointer
# shows BOTH tones and its leash and none of your own movement layers, V fills every enemy,
# Shift+click pins one past the pointer and past the key, and a queued order drops the cached
# field. The reach LINES this suite used to pin are GONE (slice 3, dev: "a bit too much") -- the
# two-tone fill is what answers "who can reach here" now. Fixture is #114's -- the instanced
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


func test_hovering_an_enemy_shows_both_tones_and_its_leash_and_leaving_clears_them() -> void:
	var sentry := _spawn_sentry(Vector2i(3, 2))
	game.hover_presenter.update_hover_visuals(sentry.movement.cell)
	var field: ThreatField = game.threat_field()
	assert_that(_sorted(_om().danger_overlay.get_used_cells())).is_equal(_sorted(field.reach_of(sentry)))
	assert_bool(_om().danger_overlay.get_used_cells().size() > 0).is_true()
	assert_that(_sorted(_om().enemy_move_overlay.get_used_cells())).override_failure_message(
			"the move tone is not the archetype's own envelope").is_equal(_sorted(field.move_of(sentry)))
	assert_that(_sorted(_om().zone_highlight_overlay.get_used_cells())) \
		.is_equal(_sorted(game.zone_manager.cells_in(ZONE)))
	assert_bool(_om().zone_highlight_overlay.visible).override_failure_message(
			"the leash is painted but the layer is hidden -- the reveal never reached the gate").is_true()
	assert_bool(_om().zone_overlay.visible).override_failure_message(
			"the patrol layer itself leaked into play; only the ONE leash is revealed").is_false()
	game.hover_presenter.update_hover_visuals(Vector2i(0, 0))
	assert_array(_om().danger_overlay.get_used_cells()).is_empty()
	assert_array(_om().enemy_move_overlay.get_used_cells()).is_empty()
	assert_array(_om().zone_highlight_overlay.get_used_cells()).is_empty()
	assert_bool(_om().zone_highlight_overlay.visible).is_false()


func test_hovering_an_enemy_never_borrows_your_own_movement_layers() -> void:
	# #710 slice 3's unify ruling. All three used to paint for ANY hovered unit, and all three
	# answer the RAW question -- where could this body physically walk -- which is not what the
	# enemy tones say. The squad-range one is the sharpest: it is a third picture of enemy
	# movement, and the one ThreatField deliberately ignores.
	var enemy := _spawn(ENEMY, Vector2i(3, 2), AIArchetype.Type.HOLD)
	game.hover_presenter.update_hover_visuals(enemy.movement.cell)
	assert_array(_om().move_overlay.get_used_cells()).override_failure_message(
			"hovering an enemy painted YOUR yellow move range").is_empty()
	assert_array(_om().squadrange_overlay.get_used_cells()).override_failure_message(
			"hovering an enemy painted the orange cohesion bubble").is_empty()
	assert_array(_om().invalidmove_overlay.get_used_cells()).override_failure_message(
			"hovering an enemy painted the red unreachable fill").is_empty()
	# ...and it is not simply drawing nothing: the enemy's own tones ARE up.
	assert_bool(_om().danger_overlay.get_used_cells().size() > 0).is_true()
	assert_bool(_om().enemy_move_overlay.get_used_cells().size() > 0).is_true()


func test_a_hold_enemy_casts_no_move_tone_at_all() -> void:
	# The archetype-honest ruling, at the one archetype where it is visible: a Hold unit fires
	# from where it stands, so the only cell it can be on is its own. Under a raw move range it
	# would paint its whole MOV and read as a charge that is never coming.
	var holder := _spawn(ENEMY, Vector2i(3, 2), AIArchetype.Type.HOLD)
	game.toggle_enemy_ranges()
	assert_that(_om().enemy_move_overlay.get_used_cells()).is_equal([holder.movement.cell])
	assert_bool(_om().danger_overlay.get_used_cells().size() > 1).override_failure_message(
			"the reach tone collapsed too -- this case would then prove nothing").is_true()


func test_the_ranges_key_fills_every_enemy_and_reveals_every_leash() -> void:
	_spawn_sentry(Vector2i(3, 2))
	_spawn(ENEMY, Vector2i(2, 3))   # a second, unleashed enemy inside the boot board
	game.toggle_enemy_ranges()
	assert_bool(game.ranges_shown).is_true()
	var field: ThreatField = game.threat_field()
	assert_that(_sorted(_om().danger_overlay.get_used_cells())).is_equal(_sorted(field.all_cells()))
	assert_int(_om().danger_overlay.get_used_cells().size()).is_greater(4)   # both enemies, not one
	assert_that(_sorted(_om().zone_highlight_overlay.get_used_cells())) \
		.is_equal(_sorted(game.zone_manager.cells_in(ZONE)))
	assert_bool(_om().zone_highlight_overlay.visible).is_true()
	# Hovering elsewhere does not tear the view down -- it belongs to the key, not the pointer.
	game.hover_presenter.update_hover_visuals(Vector2i(0, 0))
	assert_bool(_om().danger_overlay.get_used_cells().size() > 0).is_true()
	game.toggle_enemy_ranges()
	assert_bool(game.ranges_shown).is_false()
	assert_array(_om().danger_overlay.get_used_cells()).is_empty()
	assert_array(_om().enemy_move_overlay.get_used_cells()).is_empty()
	assert_array(_om().zone_highlight_overlay.get_used_cells()).is_empty()


# WHOSE FIELD IS THIS (slice 4, dev: "when hovering a specific unit, their grid should highlight").
# With V on, three enemies union into one blob and the pointer changed nothing about it.
func test_hovering_one_of_several_lit_enemies_dims_the_rest() -> void:
	var focus := _spawn(ENEMY, Vector2i(3, 2))
	_spawn(ENEMY, Vector2i(1, 4))
	_spawn(ENEMY, Vector2i(2, 3))
	game.toggle_enemy_ranges()

	# Nothing hovered: everybody bright, and the dim layers are not merely equal -- they are unused,
	# which is what keeps a board nobody is pointing at looking exactly as it did before slice 4.
	assert_array(_om().danger_dim_overlay.get_used_cells()).override_failure_message(
			"the crowd dimmed with nobody hovered").is_empty()
	assert_array(_om().enemy_move_dim_overlay.get_used_cells()).is_empty()
	var everyone: int = _om().danger_overlay.get_used_cells().size()

	game.hover_presenter.update_hover_visuals(focus.movement.cell)
	var field: ThreatField = game.threat_field()
	assert_that(_sorted(_om().enemy_move_overlay.get_used_cells())).override_failure_message(
			"the bright move tone is not the hovered enemy's own envelope"
			).is_equal(_sorted(field.move_of(focus)))
	assert_that(_sorted(_om().danger_overlay.get_used_cells())).is_equal(_sorted(field.reach_of(focus)))
	assert_bool(_om().danger_dim_overlay.get_used_cells().size() > 0).override_failure_message(
			"the other two enemies vanished instead of dimming").is_true()

	# The crowd is SUBTRACTED from the focus, never stacked under it: four coincident alphas read
	# differently from two, so a focused cell would change tone wherever a neighbour's field crossed.
	for cell: Vector2i in _om().danger_dim_overlay.get_used_cells():
		assert_bool(_om().danger_overlay.get_used_cells().has(cell)).override_failure_message(
				"%s carries a dim quad UNDER a bright one" % cell).is_false()
		assert_bool(_om().enemy_move_overlay.get_used_cells().has(cell)).is_false()
	for cell: Vector2i in _om().enemy_move_dim_overlay.get_used_cells():
		assert_bool(_om().danger_overlay.get_used_cells().has(cell)).is_false()
		assert_bool(_om().enemy_move_overlay.get_used_cells().has(cell)).is_false()

	# ...and nothing was lost in the split: every cell that was lit is still lit, somewhere.
	var lit := {}
	for cell: Vector2i in _om().danger_overlay.get_used_cells():
		lit[cell] = true
	for cell: Vector2i in _om().danger_dim_overlay.get_used_cells():
		lit[cell] = true
	assert_int(lit.size()).override_failure_message(
			"the focus split dropped cells the un-hovered view was painting").is_equal(everyone)
	game.toggle_enemy_ranges()


# The stroke says WHOSE field this is where the two hues alone cannot -- the dev's addition to the
# mockup. One segment per outward-facing cell edge of the whole footprint, move and reach together.
func test_the_hovered_enemys_field_is_outlined() -> void:
	var focus := _spawn(ENEMY, Vector2i(3, 2))
	_spawn(ENEMY, Vector2i(1, 4))
	game.toggle_enemy_ranges()
	assert_array(_om().focus_outline).override_failure_message(
			"a stroke was drawn with nobody under the pointer").is_empty()

	game.hover_presenter.update_hover_visuals(focus.movement.cell)
	var field: ThreatField = game.threat_field()
	var footprint := {}
	for cell: Vector2i in field.move_of(focus):
		footprint[cell] = true
	for cell: Vector2i in field.reach_of(focus):
		footprint[cell] = true

	# The boundary is derived, never counted by hand: one edge per cell side whose neighbour is
	# outside the set, which is what makes the count a property of the footprint's SHAPE.
	var expected := 0
	for cell: Vector2i in footprint:
		for dir: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			if not footprint.has(cell + dir):
				expected += 1
	assert_int(_om().focus_outline.size()).override_failure_message(
			"the stroke is not the footprint's outward-facing boundary").is_equal(expected)
	assert_int(expected).override_failure_message(
			"fixture is vacuous: an empty footprint has no boundary").is_greater(0)

	# Every segment is two points in TRACE space -- cell coordinates, rule height -- which is what
	# lets the flat view flatten it and the mirror lift it exactly as it lifts an intent line.
	for segment: PackedVector3Array in _om().focus_outline:
		assert_int(segment.size()).is_equal(2)

	game.hover_presenter.update_hover_visuals(Vector2i(0, 0))
	assert_array(_om().focus_outline).override_failure_message(
			"the stroke outlived the pointer leaving the enemy").is_empty()
	game.toggle_enemy_ranges()


# The dim tone is DERIVED from the bright one, so a knob on either carries to both.
func test_the_crowds_tone_follows_the_tone_it_dims() -> void:
	_spawn(ENEMY, Vector2i(3, 2))
	var before: Color = _om().enemy_move_dim_overlay.modulate
	OverlayManager.ENEMY_MOVE_MODULATE = Color(0.1, 0.9, 0.2, 0.5)
	_om().restyle_dim_ranges()
	var after: Color = _om().enemy_move_dim_overlay.modulate
	assert_that(after).override_failure_message(
			"the crowd kept the hue the focus tone just left").is_not_equal(before)
	assert_float(after.a).override_failure_message(
			"the dim is not alpha-only -- multiplying RGB pulls the hue into the board"
			).is_equal_approx(0.5 * OverlayManager.ENEMY_RANGE_DIM, 0.001)
	assert_float(after.g).is_equal_approx(0.9, 0.001)
	OverlayManager.ENEMY_MOVE_MODULATE = Color(0.25, 0.45, 1, 0.45)
	_om().restyle_dim_ranges()


func test_the_ranges_key_going_off_drops_every_pin() -> void:
	# REVERSED 2026-09-18 on the dev's own call, and this case is the record of it: it used to be
	# named ..._survives_the_key_being_turned_on_and_off_again and asserted the opposite, on his
	# earlier "a pin OVERRIDES the toggle". The key's OFF is now the one way back to a clean board --
	# nothing else clears a pinned set except shift+clicking each enemy again. What must NOT have
	# come with it is a pin lapsing on the pointer or on a queued order; the case below pins that.
	var pinned := _spawn(ENEMY, Vector2i(3, 2))
	var other := _spawn(ENEMY, Vector2i(1, 4))
	game.toggle_enemy_pin(pinned)
	var field: ThreatField = game.threat_field()
	assert_that(_sorted(_om().enemy_move_overlay.get_used_cells())).is_equal(_sorted(field.move_of(pinned)))

	# ON first: the pin is still up here, which is what makes the press below an OFF rather than the
	# first half of a round trip. Both enemies draw, so the state being cleared is non-empty.
	game.toggle_enemy_ranges()
	assert_bool(game.ranges_shown).is_true()
	assert_bool(_om().enemy_move_overlay.get_used_cells().has(other.movement.cell)).override_failure_message(
			"the key's ON did not draw the unpinned enemy, so this case starts from the wrong state"
			).is_true()
	assert_bool(game.pinned_enemies.has(pinned.get_instance_id())).override_failure_message(
			"the key's ON dropped the pin; only its OFF may").is_true()

	game.toggle_enemy_ranges()
	assert_bool(game.ranges_shown).is_false()
	assert_bool(game.pinned_enemies.is_empty()).override_failure_message(
			"the key's OFF left the pin standing -- the board cannot be cleared").is_true()
	assert_array(_om().enemy_move_overlay.get_used_cells()).override_failure_message(
			"the key is off and every pin is dropped, so nothing should be drawn").is_empty()
	assert_array(_om().danger_overlay.get_used_cells()).override_failure_message(
			"the reach tone outlived the pin its move tone was cleared with").is_empty()


func test_a_pinned_enemy_survives_the_pointer_leaving_it_and_an_order_being_queued() -> void:
	# The second half is the hole the door closed: drop_threat_field used to repaint only while
	# the toggle was on, so a queued order left a pin showing a field built before the board moved.
	var mover := _spawn(PLAYER, Vector2i(1, 1))
	var pinned := _spawn(ENEMY, Vector2i(4, 1))
	game.toggle_enemy_pin(pinned)
	game.hover_presenter.update_hover_visuals(Vector2i(0, 0))
	assert_bool(_om().enemy_move_overlay.get_used_cells().size() > 0).override_failure_message(
			"the pointer moving off the pinned enemy tore its ranges down").is_true()
	game.enter_move_mode(mover)
	game.selected_unit = mover
	game._click_choosing_move(Vector2i(1, 2))
	assert_bool(_om().enemy_move_overlay.get_used_cells().size() > 0).override_failure_message(
			"a queued order cleared the pinned enemy's ranges and never put them back").is_true()


func test_shift_clicking_an_enemy_pins_it_and_opens_no_menu() -> void:
	# Shift CONSUMES the click, because the ordinary one selects an enemy and opens its ring
	# (the hotseat allowance) -- and pinning is not a selection.
	var enemy := _spawn(ENEMY, Vector2i(3, 2))
	game._on_left_click(enemy.movement.cell, true)
	assert_bool(game.pinned_enemies.has(enemy.get_instance_id())).is_true()
	assert_object(game.selected_unit).override_failure_message(
			"shift+click selected the enemy as well as pinning it").is_null()
	assert_int(game.game_state).is_equal(game.GameState.IDLE)
	game._on_left_click(enemy.movement.cell, true)
	assert_bool(game.pinned_enemies.has(enemy.get_instance_id())).override_failure_message(
			"shift+click does not toggle back off").is_false()


func test_the_ranges_key_stands_down_for_the_tile_brush() -> void:
	# The highlight layer has two writers; the brush's pick wins while its tab is up.
	_spawn_sentry(Vector2i(3, 2))
	_om().set_zone_visibility(true)
	game.toggle_enemy_ranges()
	assert_array(_om().zone_highlight_overlay.get_used_cells()).is_empty()
	game.toggle_enemy_ranges()
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


# A shove is what makes the PROJECTION observable, and a player's own move is not: a move reaches
# this field only through occupancy, which a board can render invisible, so the mutant that skips
# the snapshot would pass. A queued knockback moves the ENEMY, which moves its origins -- and a HOLD
# unit's envelope is exactly the one cell it stands on, so the whole assertion is which cell that is.
#
# The lane is SEARCHED rather than written down: the boot board is authored content, and the first
# draft of this fixture put the attacker on a tree at (3, 1). Four clear cells in a row is all the
# geometry the shove needs.
func _clear_lane() -> Vector2i:
	var rect: Rect2i = game.grid.get_used_rect()
	var board: BoardContext = game._board()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x - 3):
			var clear := true
			for step in 4:
				var cell := Vector2i(x + step, y)
				if not board.is_walkable(cell) or board.unit_at_cell(cell) != null:
					clear = false
					break
			if clear:
				return Vector2i(x, y)
	return Vector2i.MAX


func _shoved_enemy() -> Unit:
	var lane := _clear_lane()
	assert_that(lane).override_failure_message(
			"fixture is vacuous: the boot board has no clear four-cell lane").is_not_equal(Vector2i.MAX)
	var attacker: Unit = _spawn(PLAYER, lane)
	var enemy: Unit = _spawn(ENEMY, lane + Vector2i.RIGHT)
	attacker.equipped_weapon.template.main_attack.knockback = 2
	game.enter_attack_mode(attacker)
	game.selected_unit = attacker
	game._click_attack_targeting(enemy.movement.cell)
	return enemy


func test_the_range_tones_read_the_board_the_plan_will_leave() -> void:
	var enemy := _shoved_enemy()

	var landing: Vector2i = enemy.get_projected_destination()
	assert_that(landing).override_failure_message(
			"fixture is vacuous: the shove published no landing").is_not_equal(enemy.movement.cell)

	var field: ThreatField = game.threat_field()
	assert_array(field.move_of(enemy)).override_failure_message(
			"the envelope was drawn where the enemy stands, not where the plan puts it"
			).is_equal([landing])


# The snapshot writes `position` through MovementComponent.set_cell, and a walk is a tween ON that
# property -- so it must not run while a pass is playing back. HoverPresenter._process carries no
# board lock, which is the path that reaches this.
func test_no_repaint_runs_while_a_pass_is_playing_back() -> void:
	var enemy := _spawn(ENEMY, _clear_lane())
	game.toggle_enemy_ranges()
	await await_idle_frame()
	assert_bool(_om().enemy_move_overlay.get_used_cells().size() > 0).is_true()

	_om().clear_enemy_move()
	game.order_executor.executing_plan = ResolvedPlan.new()
	game._redraw_enemy_ranges(enemy)
	assert_array(_om().enemy_move_overlay.get_used_cells()).override_failure_message(
			"a repaint ran mid-pass and would have teleported every walking sprite").is_empty()

	game.order_executor.executing_plan = null
	game.toggle_enemy_ranges()


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

	assert_int(_om().intent_marks.size()).override_failure_message(
			"no intent mark for a unit standing next to an enemy").is_equal(1)
	assert_int(_om().intent_fells.size()).override_failure_message(
			"the lethal flags are not paired one-for-one with the marks").is_equal(1)
	# The shaft is the mark's first stroke; it stops HEAD_INSET short of the victim, so the test
	# asks which cell it is nearest rather than which cell it lands in.
	var shaft: PackedVector3Array = _om().intent_marks[0][0]
	var victim := Vector2(2.5, 2.5)
	assert_float(Vector2(shaft[1].x, shaft[1].z).distance_to(victim)).override_failure_message(
			"the mark does not run toward the unit it names").is_less(0.5)


# #1042's whole first ask: "an arrow indicating direction". The arrowhead's apex has to sit at the
# VICTIM end and its legs open back toward the attacker -- which is the half a symmetric two-point
# line could never say, and the half a from/to swap silently inverts.
func test_an_intents_arrowhead_points_at_its_victim() -> void:
	_enable_enemy_ai()
	var mover := _spawn(PLAYER, Vector2i(1, 1))
	_spawn(ENEMY, Vector2i(3, 2))
	game.enter_move_mode(mover)
	game.selected_unit = mover
	game._click_choosing_move(Vector2i(2, 2))
	game.refresh_threat_plan()

	var strokes: Array = _om().intent_marks[0]
	assert_int(strokes.size()).override_failure_message(
			"the mark is not a shaft plus two arrowhead legs").is_equal(3)
	var shaft: PackedVector3Array = strokes[0]
	var attacker_end := Vector2(shaft[0].x, shaft[0].z)
	var tip := Vector2(shaft[1].x, shaft[1].z)
	for i in [1, 2]:
		var leg: PackedVector3Array = strokes[i]
		# Each leg is built back-to-tip, so its far point IS the apex and it is shared with the
		# shaft's end. Anything else and the head is hanging off the wrong end of the line.
		assert_float(Vector2(leg[1].x, leg[1].z).distance_to(tip)).override_failure_message(
				"an arrowhead leg does not meet the shaft's point").is_less(0.001)
		var heel := Vector2(leg[0].x, leg[0].z)
		assert_bool(heel.distance_to(attacker_end) < tip.distance_to(attacker_end)) \
			.override_failure_message(
				"the arrowhead opens toward the victim rather than back toward the enemy") \
			.is_true()


func test_the_key_cycles_three_states_and_comes_back_round() -> void:
	# The reported bug: T turned the numbers ON and had no way back. Three states, and the third
	# tap has to reach NOTHING or the report stands.
	assert_int(game.threat_view).override_failure_message(
			"boot does not sit at INTENTS, so a stranger who never presses T sees no preview") \
		.is_equal(game.ThreatView.INTENTS)
	game.toggle_threat_view()
	assert_int(game.threat_view).is_equal(game.ThreatView.EVERYTHING)
	game.toggle_threat_view()
	assert_int(game.threat_view).is_equal(game.ThreatView.NONE)
	game.toggle_threat_view()
	assert_int(game.threat_view).is_equal(game.ThreatView.INTENTS)


func test_the_view_survives_a_turn_handover() -> void:
	# Sticky, by the dev's call: a player who turned it off does not want it back every turn.
	game.threat_view = game.ThreatView.NONE
	game._on_turn_started(PLAYER)
	assert_int(game.threat_view).override_failure_message(
			"the hand-over reset the view -- turning it off buys you one turn of quiet").is_equal(game.ThreatView.NONE)


func test_nothing_means_nothing_is_computed() -> void:
	# The saving that makes the OFF state worth having: the preview runs a real AI turn per engaged
	# squad, so NONE must not merely hide it. previewed_squad_count is the observable slice 2 added
	# precisely because an optimisation with no behavioural signature cannot be tested.
	_enable_enemy_ai()
	var mover := _spawn(PLAYER, Vector2i(1, 1))
	_spawn(ENEMY, Vector2i(3, 2))
	game.threat_view = game.ThreatView.NONE
	var version: int = game.threat_plan_version
	AIController.previewed_squad_count = 0
	game.enter_move_mode(mover)
	game.selected_unit = mover
	game._click_choosing_move(Vector2i(2, 2))
	game.refresh_threat_plan()
	assert_int(game.threat_plan_version).override_failure_message(
			"a recompute ran with the view off").is_equal(version)
	assert_int(AIController.previewed_squad_count).override_failure_message(
			"the enemy squads were planned anyway -- the gate hides the answer without saving the work") \
		.is_equal(0)
	assert_array(_om().intent_marks).is_empty()


func test_the_damage_reaches_the_bars_only_at_everything() -> void:
	# The dev's own split: "showing who they intend to attack" and "showing everything" are two
	# states, and the damage is what the second one adds. The lines are up in both.
	_enable_enemy_ai()
	var mover := _spawn(PLAYER, Vector2i(1, 1))
	_spawn(ENEMY, Vector2i(3, 2))
	game.enter_move_mode(mover)
	game.selected_unit = mover
	game._click_choosing_move(Vector2i(2, 2))
	game.refresh_threat_plan()

	assert_int(game.threat_view).is_equal(game.ThreatView.INTENTS)
	assert_int(_om().intent_marks.size()).override_failure_message(
			"no intent line, so neither half of this case proves anything").is_equal(1)
	assert_bool(game.threat_forecast().is_empty()).override_failure_message(
			"the bars are fed at INTENTS, so the two states show the same thing").is_true()

	game.toggle_threat_view()
	game.refresh_threat_plan()
	var forecast: Dictionary = game.threat_forecast()
	assert_bool(forecast.has(mover.get_instance_id())).override_failure_message(
			"EVERYTHING does not name the unit the enemy intends to hit").is_true()
	assert_int(int(forecast[mover.get_instance_id()]["damage"])).is_greater(0)


func test_two_enemies_on_one_target_sum_into_one_forecast() -> void:
	# A bar draws ONE span, so the readout has to be per victim rather than per attacker. Which
	# attacker owns which part of the bite is a separate ticket, and this is the shape it edits.
	_enable_enemy_ai()
	var mover := _spawn(PLAYER, Vector2i(1, 1))
	_spawn(ENEMY, Vector2i(3, 2))
	_spawn(ENEMY, Vector2i(2, 3))
	game.threat_view = game.ThreatView.EVERYTHING
	game.enter_move_mode(mover)
	game.selected_unit = mover
	game._click_choosing_move(Vector2i(2, 2))
	game.refresh_threat_plan()

	assert_int(_om().intent_marks.size()).override_failure_message(
			"both enemies did not intend an attack, so there is nothing to sum").is_equal(2)
	var forecast: Dictionary = game.threat_forecast()
	assert_int(forecast.size()).override_failure_message(
			"two intents on one unit produced two forecast rows").is_equal(1)
	# Summed, not replaced: each attacker alone is a strict fraction of the total.
	var summed := int(forecast[mover.get_instance_id()]["damage"])
	var heaviest := 0
	for intent: ThreatIntent in AIController.preview_turn(PLAYER, game.squad_manager, [ENEMY]):
		heaviest = maxi(heaviest, intent.damage)
	assert_int(heaviest).override_failure_message(
			"neither enemy intends any damage, so there is nothing to sum").is_greater(0)
	assert_int(summed).override_failure_message(
			"the forecast took one attacker.s damage rather than both").is_greater(heaviest)


func test_the_intent_channel_clears_on_board_load() -> void:
	_enable_enemy_ai()
	var mover := _spawn(PLAYER, Vector2i(1, 1))
	_spawn(ENEMY, Vector2i(3, 2))
	game.enter_move_mode(mover)
	game.selected_unit = mover
	game._click_choosing_move(Vector2i(2, 2))
	game.refresh_threat_plan()
	assert_bool(_om().intent_marks.size() > 0).is_true()

	game._clear_threat_plan()
	assert_array(_om().intent_marks).is_empty()
	assert_array(_om().intent_fells).is_empty()


# #1001's cheap half. The commonest shape of the whole feature: you line up the kill, and the board
# goes on saying the dead man is about to hit you -- which undercuts exactly the trust the preview
# is for. Dropped at the harvest, so what the AI DECIDED is untouched (a doomed enemy still
# influenced its squadmates' plan, which is the declared limit).
func test_an_enemy_your_plan_fells_previews_no_intent() -> void:
	_enable_enemy_ai()
	var hero := _spawn(PLAYER, Vector2i(2, 2))
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	game.threat_view = game.ThreatView.EVERYTHING
	game.refresh_threat_plan()
	assert_int(_om().intent_marks.size()).override_failure_message(
			"the enemy intends nothing to begin with, so this case cannot see its own claim") \
		.is_equal(1)

	# Enough of a blow to fell it outright, then queue the aim for real.
	foe.set_current_hp(1)
	hero.equipped_weapon = H.make_weapon(20)
	var attack := AttackAction.declare(hero, hero.movement.cell, foe.movement.cell)
	game.squad_manager.queue_action(hero.squad, attack)
	game.refresh_threat_plan()

	assert_array(_om().intent_marks).override_failure_message(
			"a man your own plan fells is still promising to attack you").is_empty()
	assert_bool(game.threat_forecast().is_empty()).override_failure_message(
			"the mark went but its damage is still coming off the victim's health bar") \
		.is_true()


# ...and the other direction, which is the one that matters more: a blow that does NOT fell leaves
# the warning standing. Erring toward over-warning is the deliberate choice, since an absent mark
# reads as provably safe.
func test_an_enemy_your_plan_only_wounds_still_previews_its_attack() -> void:
	_enable_enemy_ai()
	var hero := _spawn(PLAYER, Vector2i(2, 2))
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	foe.set_current_hp(foe.get_max_hp())
	game.threat_view = game.ThreatView.EVERYTHING
	hero.equipped_weapon = H.make_weapon(1)
	var attack := AttackAction.declare(hero, hero.movement.cell, foe.movement.cell)
	game.squad_manager.queue_action(hero.squad, attack)
	game.refresh_threat_plan()

	assert_bool(foe.is_active()).override_failure_message(
			"the fixture felled it after all, so this case proves nothing").is_true()
	assert_int(_om().intent_marks.size()).override_failure_message(
			"a wounded enemy stopped being previewed -- the filter is dropping the living") \
		.is_equal(1)
