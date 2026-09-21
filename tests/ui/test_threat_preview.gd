# The range and reach views (#710, re-cut by #1066 and #1069), through the REAL triggers: an enemy
# under the pointer shows ONE unbroken field and its leash and none of your own layers, a FRIENDLY
# under the pointer shows where it may stand, V fills every enemy, Shift+click pins one past the
# pointer and past the key and makes its sprite flash, and a queued order drops the cached field.
#
# THE REACH LINES ARE BACK (#1069), after slice 3 deleted them for being "a bit too much" at rest:
# bound to move hover they answer "who reaches ME if I stop here", which the fill cannot. What went
# instead is slice 2's INTENT readout -- the T cycle, the debounce, the damage on a victim's bar --
# while the prediction behind it stays live and keeps its own cases at the bottom of this file.
#
# Fixture is #114's -- the instanced root MUST be named "Main" under /root.
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


# The enemy's WHOLE field -- move and reach unioned -- derived rather than retyped, so a retuned
# archetype moves the expectation with the board.
func _field_of(units: Array[Unit]) -> Array[Vector2i]:
	var field: ThreatField = game.threat_field()
	var all := {}
	for cell: Vector2i in field.move_cells_of(units):
		all[cell] = true
	for cell: Vector2i in field.reach_cells_of(units):
		all[cell] = true
	var out: Array[Vector2i] = []
	out.assign(all.keys())
	return _sorted(out)


func test_hovering_an_enemy_shows_one_unbroken_field_and_its_leash_and_leaving_clears_them() -> void:
	# ONE layer, not two (#1066, the Fire Emblem ruling): an enemy stops answering "where could I
	# stand" as against "where could I hit". Both halves are still in it -- that is what the union
	# below asserts -- they simply stopped being separate statements.
	var sentry := _spawn_sentry(Vector2i(3, 2))
	game.hover_presenter.update_hover_visuals(sentry.movement.cell)
	assert_that(_sorted(_om().threat_overlay.get_used_cells())).override_failure_message(
			"the field is not the union of where it may stand and what it may hit"
			).is_equal(_field_of([sentry]))
	assert_bool(_om().threat_overlay.get_used_cells().size() > 0).is_true()
	assert_that(_sorted(_om().zone_highlight_overlay.get_used_cells())) \
		.is_equal(_sorted(game.zone_manager.cells_in(ZONE)))
	assert_bool(_om().zone_highlight_overlay.visible).override_failure_message(
			"the leash is painted but the layer is hidden -- the reveal never reached the gate").is_true()
	assert_bool(_om().zone_overlay.visible).override_failure_message(
			"the patrol layer itself leaked into play; only the ONE leash is revealed").is_false()
	game.hover_presenter.update_hover_visuals(Vector2i(0, 0))
	assert_array(_om().threat_overlay.get_used_cells()).is_empty()
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
	assert_array(_om().reach_overlay.get_used_cells()).override_failure_message(
			"hovering an enemy painted YOUR red attack reach").is_empty()
	# ...and it is not simply drawing nothing: the enemy's own field IS up.
	assert_bool(_om().threat_overlay.get_used_cells().size() > 0).is_true()


# --- YOUR unit's two tones (#1066, retimed and narrowed by #1069) ------------------------------

# Every cell this unit's weapon could touch from `origins` BY THE GEOMETRY ALONE -- no vertical
# gate, no counter rim -- so it is a strict superset of what the readout may legally paint. A
# second derivation on purpose: containment against it says the red grew from those cells without
# restating the rule that narrows it.
func _geometric_reach(unit: Unit, origins: Array[Vector2i]) -> Dictionary:
	var out := {}
	for origin: Vector2i in origins:
		for cell: Vector2i in Reach.get_all_attack_cells_from(unit, origin, unit.get_fired_attack()):
			out[cell] = true
	return out


func test_a_hovered_friendly_says_where_it_may_stand_and_nothing_about_its_reach() -> void:
	# #1066 drew both on hover, on the dev's ruling then. #1069 repeals that half of it after he
	# looked at 3D FE again: "hovering a unit doesn't show the attack range at all, actually."
	var friend := _spawn(PLAYER, Vector2i(2, 2))
	game.hover_presenter.update_hover_visuals(friend.movement.cell)
	var standable: Array[Vector2i] = game.get_move_range(game.compute_move_range(friend), friend)
	assert_that(_sorted(_om().move_overlay.get_used_cells())).override_failure_message(
			"the blue is not this unit's move range").is_equal(_sorted(standable))
	assert_array(_om().reach_overlay.get_used_cells()).override_failure_message(
			"hovering a unit still paints its attack range").is_empty()


# ...and SELECTING it does (dev: "Selecting a unit, though (for us, bringing up the radial menu,
# and also choosing a move, etc), brings up the unit's attack radius from the unit's tile").
#
# Driven through the real click arm, not by calling the door: opening the ring paints no overlays of
# its own, so what a case calling show_selected_reach directly could not see is whether anything
# reaches it.
func test_selecting_a_unit_shows_its_reach_from_the_tile_it_stands_on() -> void:
	var friend := _spawn(PLAYER, Vector2i(2, 2))
	game._click_idle(friend.movement.cell)

	var red: Array[Vector2i] = _om().reach_overlay.get_used_cells()
	assert_bool(red.size() > 0).override_failure_message(
			"selecting a unit says nothing about where it could hit").is_true()
	# FROM ONE CELL, not from the envelope. #1066 grew it from every cell drawn blue, which answers
	# "could this unit ever hit that square" -- true of most of the board. The envelope is derived
	# here only to prove the narrow answer is strictly smaller, which is the whole repeal.
	var here := _geometric_reach(friend, [friend.movement.cell])
	for cell: Vector2i in red:
		assert_bool(here.has(cell)).override_failure_message(
				"%s is red and this unit cannot reach it from the tile it stands on" % cell).is_true()
	var standable: Array[Vector2i] = game.get_move_range(game.compute_move_range(friend), friend)
	assert_int(_geometric_reach(friend, standable).size()).override_failure_message(
			"fixture is vacuous: walking first reaches nothing extra, so one origin and the whole "
			+ "envelope are the same answer here").is_greater(here.size())


# ...and choosing a move moves it to the cell under the pointer, which is the question actually
# being asked while you stand over a candidate: not "could I ever hit that" but "what do I threaten
# if I stop HERE".
func test_choosing_a_move_shows_the_reach_from_the_cell_under_the_pointer() -> void:
	var friend := _spawn(PLAYER, Vector2i(2, 2))
	game.enter_move_mode(friend)
	game.selected_unit = friend
	var resting := _sorted(_om().reach_overlay.get_used_cells())
	assert_bool(resting.size() > 0).override_failure_message(
			"entering move mode drew no reach at all, so the move below proves nothing").is_true()

	var candidate := Vector2i(4, 2)
	game.hover_presenter.update_hover_visuals(candidate)
	var moved := _sorted(_om().reach_overlay.get_used_cells())
	assert_bool(moved == resting).override_failure_message(
			"the reach stayed on the body's own cell while the pointer named another").is_false()
	var from_candidate := _geometric_reach(friend, [candidate])
	for cell: Vector2i in moved:
		assert_bool(from_candidate.has(cell)).override_failure_message(
				"%s is red and the hovered cell cannot reach it" % cell).is_true()


func test_a_hold_enemys_field_never_spreads_past_what_it_can_hit_from_where_it_stands() -> void:
	# The archetype-honest ruling SURVIVES the merge (#710's, kept by #1066): a Hold unit fires
	# from where it stands, so the only cell it can be on is its own, and its field is therefore
	# exactly its reach. Under a raw move range it would paint its whole MOV and read as a charge
	# that is never coming -- which the merged field would hide rather than fix.
	var holder := _spawn(ENEMY, Vector2i(3, 2), AIArchetype.Type.HOLD)
	game.toggle_enemy_ranges()
	var field: ThreatField = game.threat_field()
	assert_that(field.move_of(holder)).override_failure_message(
			"a Hold unit's envelope grew past the cell it stands on").is_equal([holder.movement.cell])
	assert_that(_sorted(_om().threat_overlay.get_used_cells())).is_equal(_field_of([holder]))
	assert_bool(_om().threat_overlay.get_used_cells().size() > 1).override_failure_message(
			"the field collapsed to one cell -- this case would then prove nothing").is_true()


func test_the_ranges_key_fills_every_enemy_and_reveals_every_leash() -> void:
	var sentry := _spawn_sentry(Vector2i(3, 2))
	var other := _spawn(ENEMY, Vector2i(2, 3))   # a second, unleashed enemy inside the boot board
	game.toggle_enemy_ranges()
	assert_bool(game.ranges_shown).is_true()
	assert_that(_sorted(_om().threat_overlay.get_used_cells())).is_equal(_field_of([sentry, other]))
	assert_int(_om().threat_overlay.get_used_cells().size()).is_greater(4)   # both enemies, not one
	assert_that(_sorted(_om().zone_highlight_overlay.get_used_cells())) \
		.is_equal(_sorted(game.zone_manager.cells_in(ZONE)))
	assert_bool(_om().zone_highlight_overlay.visible).is_true()
	# Hovering elsewhere does not tear the view down -- it belongs to the key, not the pointer.
	game.hover_presenter.update_hover_visuals(Vector2i(0, 0))
	assert_bool(_om().threat_overlay.get_used_cells().size() > 0).is_true()
	game.toggle_enemy_ranges()
	assert_bool(game.ranges_shown).is_false()
	assert_array(_om().threat_overlay.get_used_cells()).is_empty()
	assert_array(_om().zone_highlight_overlay.get_used_cells()).is_empty()


# WHOSE FIELD IS THIS (slice 4's question, #1066's answer). Slice 4 dimmed the crowd; the dev
# played it and REPEALED that: "if multiple are highlighted, and you hover one, the other ranges
# become too dim. They shouldn't dim at all, the outline on the main one should be the only
# differentiator." So the property is that the pointer changes the FIELD not at all -- the same
# cells, at the same strength, with a stroke added round one of them.
func test_hovering_one_of_several_lit_enemies_dims_nothing() -> void:
	var focus := _spawn(ENEMY, Vector2i(3, 2))
	var b := _spawn(ENEMY, Vector2i(1, 4))
	var c := _spawn(ENEMY, Vector2i(2, 3))
	game.toggle_enemy_ranges()
	var everyone := _sorted(_om().threat_overlay.get_used_cells())
	assert_that(everyone).is_equal(_field_of([focus, b, c]))

	game.hover_presenter.update_hover_visuals(focus.movement.cell)
	assert_that(_sorted(_om().threat_overlay.get_used_cells())).override_failure_message(
			"hovering one enemy changed which cells the field covers -- a dim tier is back, or " +
			"the crowd is being subtracted from the focus again").is_equal(everyone)
	assert_bool(_om().focus_outline.size() > 0).override_failure_message(
			"nothing distinguishes the hovered enemy at all now that nothing dims").is_true()
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


# A tuned colour reaches the layer it tints, or the Game tab's slider is #264's born-dead one.
# The VALUES are never pinned -- every one of them is a slider the dev may drag tomorrow -- only
# that turning one moves the board.
func test_a_tuned_range_colour_reaches_the_layer_it_tints() -> void:
	var was_threat := OverlayManager.THREAT_MODULATE
	var was_reach := OverlayManager.REACH_MODULATE
	OverlayManager.THREAT_MODULATE = Color(0.1, 0.9, 0.2, 0.5)
	OverlayManager.REACH_MODULATE = Color(0.2, 0.3, 0.9, 0.4)
	_om().restyle_threat()
	_om().restyle_reach()
	assert_that(_om().threat_overlay.modulate).override_failure_message(
			"the enemy field kept the hue its knob just left").is_equal(OverlayManager.THREAT_MODULATE)
	assert_that(_om().reach_overlay.modulate).override_failure_message(
			"your reach kept the hue its knob just left").is_equal(OverlayManager.REACH_MODULATE)
	OverlayManager.THREAT_MODULATE = was_threat
	OverlayManager.REACH_MODULATE = was_reach
	_om().restyle_threat()
	_om().restyle_reach()


func test_the_ranges_key_going_off_drops_every_pin() -> void:
	# REVERSED 2026-09-18 on the dev's own call, and this case is the record of it: it used to be
	# named ..._survives_the_key_being_turned_on_and_off_again and asserted the opposite, on his
	# earlier "a pin OVERRIDES the toggle". The key's OFF is now the one way back to a clean board --
	# nothing else clears a pinned set except shift+clicking each enemy again. What must NOT have
	# come with it is a pin lapsing on the pointer or on a queued order; the case below pins that.
	var pinned := _spawn(ENEMY, Vector2i(3, 2))
	var other := _spawn(ENEMY, Vector2i(1, 4))
	game.toggle_enemy_pin(pinned)
	assert_that(_sorted(_om().threat_overlay.get_used_cells())).is_equal(_field_of([pinned]))

	# ON first: the pin is still up here, which is what makes the press below an OFF rather than the
	# first half of a round trip. Both enemies draw, so the state being cleared is non-empty.
	game.toggle_enemy_ranges()
	assert_bool(game.ranges_shown).is_true()
	assert_bool(_om().threat_overlay.get_used_cells().has(other.movement.cell)).override_failure_message(
			"the key's ON did not draw the unpinned enemy, so this case starts from the wrong state"
			).is_true()
	assert_bool(game.pinned_enemies.has(pinned.get_instance_id())).override_failure_message(
			"the key's ON dropped the pin; only its OFF may").is_true()

	game.toggle_enemy_ranges()
	assert_bool(game.ranges_shown).is_false()
	assert_bool(game.pinned_enemies.is_empty()).override_failure_message(
			"the key's OFF left the pin standing -- the board cannot be cleared").is_true()
	assert_array(_om().threat_overlay.get_used_cells()).override_failure_message(
			"the key is off and every pin is dropped, so nothing should be drawn").is_empty()
	assert_object(pinned.visuals.pin_tween).override_failure_message(
			"the sprite is still flashing for a pin the key just dropped").is_null()


func test_a_pinned_enemy_survives_the_pointer_leaving_it_and_an_order_being_queued() -> void:
	# The second half is the hole the door closed: drop_threat_field used to repaint only while
	# the toggle was on, so a queued order left a pin showing a field built before the board moved.
	var mover := _spawn(PLAYER, Vector2i(1, 1))
	var pinned := _spawn(ENEMY, Vector2i(4, 1))
	game.toggle_enemy_pin(pinned)
	game.hover_presenter.update_hover_visuals(Vector2i(0, 0))
	assert_bool(_om().threat_overlay.get_used_cells().size() > 0).override_failure_message(
			"the pointer moving off the pinned enemy tore its ranges down").is_true()
	game.enter_move_mode(mover)
	game.selected_unit = mover
	game._click_choosing_move(Vector2i(1, 2))
	assert_bool(_om().threat_overlay.get_used_cells().size() > 0).override_failure_message(
			"a queued order cleared the pinned enemy's ranges and never put them back").is_true()


func test_a_pinned_enemys_sprite_flashes_and_an_unpinned_one_does_not() -> void:
	# Dev (#1066): "units that are toggled need to be indicated in some way. I think they should
	# flash, too." On the unit SPRITE, his own ruling from the same batch -- not a marker -- which
	# is what gets the diorama it for free through UnitMirror's per-frame modulate copy.
	var pinned := _spawn(ENEMY, Vector2i(3, 2))
	var other := _spawn(ENEMY, Vector2i(1, 4))
	game.toggle_enemy_pin(pinned)
	assert_object(pinned.visuals.pin_tween).override_failure_message(
			"a pinned enemy wears nothing at all that says so").is_not_null()
	assert_object(other.visuals.pin_tween).override_failure_message(
			"an enemy nobody pinned is flashing").is_null()
	game.toggle_enemy_pin(pinned)
	assert_object(pinned.visuals.pin_tween).override_failure_message(
			"the flash outlived the pin").is_null()


func test_an_aim_pulse_outranks_a_pin_flash_and_the_pin_comes_back() -> void:
	# Both write sprite.modulate and a live pulse OWNS that channel (#442), so exactly one may run.
	# "This unit is about to be hit" is news; "you pinned it" is a bookmark you set yourself. The
	# second half is what a plain precedence misses: the pin has to return when the aim moves on,
	# which is why `pinned` is a flag rather than a reading of the tween.
	var enemy := _spawn(ENEMY, Vector2i(3, 2))
	game.toggle_enemy_pin(enemy)
	assert_object(enemy.visuals.pin_tween).is_not_null()
	enemy.visuals.start_pulse()
	assert_object(enemy.visuals.pin_tween).override_failure_message(
			"the pin flash kept the sprite while an aim was on the body").is_null()
	assert_object(enemy.visuals.pulse_tween).override_failure_message(
			"the aim pulse never started").is_not_null()
	enemy.visuals.stop_pulse()
	assert_object(enemy.visuals.pin_tween).override_failure_message(
			"the pin flash never came back after the aim moved on").is_not_null()


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
	assert_bool(_om().threat_overlay.get_used_cells().size() > 0).is_true()

	_om().clear_threat()
	game.order_executor.executing_plan = ResolvedPlan.new()
	game._redraw_enemy_ranges(enemy)
	assert_array(_om().threat_overlay.get_used_cells()).override_failure_message(
			"a repaint ran mid-pass and would have teleported every walking sprite").is_empty()

	game.order_executor.executing_plan = null
	game.toggle_enemy_ranges()
# moment the height goes back to reading Reach.EYE_HEIGHT -- which is a RULE about what a wall is
# and must never move for a look.
func test_the_mark_hangs_at_its_own_height_and_not_the_sight_beams() -> void:
	var probe := 0.21875   # nothing else in the game is this
	var kept := ThreatLines2D.MARK_HEIGHT
	ThreatLines2D.MARK_HEIGHT = probe
	var chord := ThreatLines2D.segment(Vector2i(1, 1), Vector2i(4, 1), game._board())
	ThreatLines2D.MARK_HEIGHT = kept
	assert_float(chord[0].y).override_failure_message(
			"the mark ignores its own height -- it is still hanging at the sight beam's").is_equal_approx(probe, 0.001)
	assert_float(chord[1].y).override_failure_message(
			"only one end of the mark reads the height").is_equal_approx(probe, 0.001)


# ...and WHAT IT MEASURES FROM. board.elevation_at is a cell's LOW side, while a body on a ramp
# stands at the slope's midpoint -- so a mark measured from the low corner sinks into the slope.
# EYE_HEIGHT's 1.0 happened to equal that half level, which is why the old mark cleared a ramp by
# coincidence rather than by rule.
func test_a_mark_on_a_ramp_leaves_from_the_surface_a_body_stands_on() -> void:
	var board: BoardContext = game._board()
	var ramp := Vector2i(2, 2)
	game.board_heights.set_corners(ramp, Vector4i(0, 0, 2, 2))
	board = game._board()
	var corners := board.corners_at(ramp)
	assert_int(board.elevation_at(ramp)).override_failure_message(
			"the fixture did not build a ramp -- its low side is not the floor").is_equal(0)
	var surface := Terrain.height_at_uv(corners, 0.5, 0.5)
	assert_bool(surface > float(board.elevation_at(ramp))).override_failure_message(
			"the fixture's ramp is flat, so this case cannot tell the two reads apart").is_true()
	var chord := ThreatLines2D.segment(ramp, Vector2i(5, 2), board)
	assert_float(chord[0].y).override_failure_message(
			"the mark measures from the ramp's LOW corner, so it sinks into the slope") \
		.is_equal_approx(surface + ThreatLines2D.MARK_HEIGHT, 0.001)


# The arc, and the reason its lift is authored PER CELL: "shallow" is a property of the shape, so a
# two-cell mark and a nine-cell one have to bow by the same amount relative to their own run.
func test_the_mark_bows_above_its_own_chord_in_proportion_to_its_length() -> void:
	var board: BoardContext = game._board()
	var short_mark := ThreatLines2D.mark(ThreatLines2D.segment(Vector2i(1, 1), Vector2i(4, 1), board))
	var long_mark := ThreatLines2D.mark(ThreatLines2D.segment(Vector2i(1, 3), Vector2i(10, 3), board))
	var flat := ThreatLines2D.MARK_HEIGHT
	var short_rise := _peak(short_mark) - flat
	var long_rise := _peak(long_mark) - flat
	assert_bool(short_rise > 0.001).override_failure_message(
			"the mark runs straight -- nothing is bowing it above its chord").is_true()
	assert_bool(long_rise > short_rise * 1.5).override_failure_message(
			"the bow does not scale with the run, so one lift cannot read as shallow at every length") \
		.is_true()


# The highest point any of a mark's strokes reaches.
func _peak(strokes: Array[PackedVector3Array]) -> float:
	var top := -INF
	for stroke in strokes:
		for p in stroke:
			top = maxf(top, p.y)
	return top



# --- WHO REACHES YOU HERE (#1069) --------------------------------------------------------------
#
# The lines are #710 slice 1's channel, deleted by slice 3 and brought back with a narrower
# trigger: they answer who could hit the cell you are hovering a MOVE onto, and they exist only
# while that gesture is running. Everything about slice 2's INTENT readout -- the T cycle, the
# debounce, the damage on the victim's bar -- went with it; the prediction behind it did not, and
# its own cases are at the bottom of this file.

# The preview only speaks for factions the AI actually DRIVES -- an unmanaged faction is nobody's
# to predict. clear_board() empties that set, so every case below has to put the enemy back.
func _enable_enemy_ai() -> void:
	game.ai_controller.set_faction_ai_enabled(ENEMY, true)


# Walk the real gesture: enter move mode, put the pointer on a candidate destination, and read what
# was drawn. Driven through HoverPresenter rather than through the door, because the whole claim is
# WHEN these appear and a case calling show_reach_lines_at directly could not see a trigger that
# never fires.
func _hover_destination(unit: Unit, cell: Vector2i) -> void:
	game.enter_move_mode(unit)
	game.selected_unit = unit
	game.hover_presenter.update_hover_visuals(cell)


func test_choosing_a_move_says_who_could_hit_you_on_the_cell_you_are_hovering() -> void:
	var mover := _spawn(PLAYER, Vector2i(1, 1))
	_spawn(ENEMY, Vector2i(3, 2))
	_hover_destination(mover, Vector2i(2, 2))

	assert_int(_om().reach_line_marks.size()).override_failure_message(
			"no mark for a destination standing right beside an enemy").is_equal(1)
	# The mark's LAST point is its tip; it stops MARK_INSET short, so the case asks which cell it is
	# nearest rather than which cell it lands in.
	var strokes: Array = _om().reach_line_marks[0]
	var last: PackedVector3Array = strokes[strokes.size() - 1]
	var tip := last[last.size() - 1]
	assert_float(Vector2(tip.x, tip.z).distance_to(Vector2(2.5, 2.5))).override_failure_message(
			"the mark does not run toward the cell you are hovering").is_less(0.5)


# EXACTLY the field's own answer, not a second walk. What would break this is somebody deriving
# "who can reach here" a second way -- which is the divergence Law #4 exists for, and which nothing
# cheaper than asking both sides can see.
func test_the_marks_name_exactly_the_enemies_the_field_says_reach_that_cell() -> void:
	var mover := _spawn(PLAYER, Vector2i(1, 1))
	_spawn(ENEMY, Vector2i(3, 2))
	_spawn(ENEMY, Vector2i(8, 8))   # far away; must NOT be named
	var cell := Vector2i(2, 2)
	_hover_destination(mover, cell)

	var expected: int = game.threat_field().attackers_of(cell).size()
	assert_int(expected).override_failure_message(
			"nobody reaches that cell, so this case cannot see its own claim").is_greater(0)
	assert_int(_om().reach_line_marks.size()).override_failure_message(
			"the marks and the threat field disagree about who reaches this cell") \
		.is_equal(expected)


# The whole reason slice 3 deleted these: a beam channel standing up at rest was "a bit too much".
# Bound to the gesture, they must be absent everywhere else -- including over the very cell that
# would have drawn one a moment ago.
func test_the_marks_are_drawn_only_while_a_move_is_being_chosen() -> void:
	var mover := _spawn(PLAYER, Vector2i(1, 1))
	_spawn(ENEMY, Vector2i(3, 2))

	game.hover_presenter.update_hover_visuals(Vector2i(2, 2))   # IDLE over the same cell
	assert_array(_om().reach_line_marks).override_failure_message(
			"the marks are up at rest, which is what slice 3 deleted them for").is_empty()

	_hover_destination(mover, Vector2i(2, 2))
	assert_int(_om().reach_line_marks.size()).override_failure_message(
			"the gesture drew nothing, so the teardown below proves nothing").is_equal(1)

	game.exit_current_mode()
	assert_array(_om().reach_line_marks).override_failure_message(
			"the marks outlived the move gesture -- leaving a mode is not a cell change, so the "
			+ "hover sweep never comes along to take them down").is_empty()


# --- The prediction that STAYS (#710 slice 2, kept at #1069) ------------------------------------
#
# The dev, retiring the readout: "don't get rid of the intent logic, we might end up using it
# somewhere else." So these ask about AIController.preview_faction_turn directly -- it has no
# production caller now, and a seam nobody draws is exactly the kind that rots quietly.

# A man your own plan kills makes no promises. Without this the preview goes on saying the dead man
# is about to hit you, which undercuts exactly the trust it is for. Dropped at the HARVEST, so what
# the AI decided is untouched (a doomed enemy still influenced its squadmates' plan, the declared
# limit).
func test_an_enemy_your_plan_fells_previews_no_intent() -> void:
	_enable_enemy_ai()
	var hero := _spawn(PLAYER, Vector2i(2, 2))
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	assert_int(game.ai_controller.preview_faction_turn(PLAYER).size()).override_failure_message(
			"the enemy intends nothing to begin with, so this case cannot see its own claim") \
		.is_equal(1)

	# Enough of a blow to fell it outright, then queue the aim for real.
	foe.set_current_hp(1)
	hero.equipped_weapon = H.make_weapon(20)
	var attack := AttackAction.declare(hero, hero.movement.cell, foe.movement.cell)
	game.squad_manager.queue_action(hero.squad, attack)

	assert_array(game.ai_controller.preview_faction_turn(PLAYER)).override_failure_message(
			"a man your own plan fells is still promising to attack you").is_empty()


# ...and the other direction, which is the one that matters more: a blow that does NOT fell leaves
# the warning standing. Erring toward over-warning is the deliberate choice, since an absent mark
# reads as provably safe.
func test_an_enemy_your_plan_only_wounds_still_previews_its_attack() -> void:
	_enable_enemy_ai()
	var hero := _spawn(PLAYER, Vector2i(2, 2))
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	foe.set_current_hp(foe.get_max_hp())
	hero.equipped_weapon = H.make_weapon(1)
	var attack := AttackAction.declare(hero, hero.movement.cell, foe.movement.cell)
	game.squad_manager.queue_action(hero.squad, attack)

	assert_bool(foe.is_active()).override_failure_message(
			"the fixture felled it after all, so this case proves nothing").is_true()
	assert_int(game.ai_controller.preview_faction_turn(PLAYER).size()).override_failure_message(
			"a wounded enemy stopped being previewed -- the filter is dropping the living") \
		.is_equal(1)


# --- The movement range draws as GRIDLINES (#1069) ----------------------------------------------

# The flat view's half of it. MOVE's own tileset carries the hollow tile; the two washes under it
# are duplicated off MOVE for their tree position and cell metric, so they have to be handed a fill
# tileset back explicitly -- and a duplicate that quietly inherited the frame is exactly the bug
# this pins, because it would leave the enemy's whole field drawn as an empty grid.
func test_the_flat_view_draws_your_movement_range_hollow_and_the_two_washes_solid() -> void:
	var om := _om()
	assert_object(om.reach_overlay).override_failure_message(
			"the reach layer was never built, so this case cannot see its own claim").is_not_null()
	assert_bool(om.reach_overlay.tile_set == om.move_overlay.tile_set).override_failure_message(
			"your reach inherited the movement range's hollow tile -- the wash is drawing as a grid") \
		.is_false()
	assert_bool(om.threat_overlay.tile_set == om.move_overlay.tile_set).override_failure_message(
			"the enemy's field inherited the movement range's hollow tile").is_false()
	assert_bool(om.reach_overlay.tile_set == om.threat_overlay.tile_set).override_failure_message(
			"the two washes stopped sharing one tileset, which is a second thing to keep in step") \
		.is_true()


# --- The move-hover GHOST (#1069) ---------------------------------------------------------------

# The dev: "we currently don't show the unit's plan ghost until a new tile is selected, but I think
# we should show it on move hover, along with the attack radius from each tile." Measured before
# building: there was no code path at all -- show_hover_move_path draws ARROWS, and
# redraw_projected_units rebuilds only from moves that queue_action has already accepted.
func test_hovering_a_destination_stands_a_ghost_on_it() -> void:
	var friend := _spawn(PLAYER, Vector2i(2, 2))
	game.enter_move_mode(friend)
	game.selected_unit = friend
	game.hover_presenter.update_hover_visuals(Vector2i(4, 2))

	assert_int(_om().hover_ghost_sprites.size()).override_failure_message(
			"hovering a destination put no stand-in on it").is_equal(1)
	assert_that(_om().hover_ghost_sprites[0].global_position).override_failure_message(
			"the ghost is not standing on the cell under the pointer") \
		.is_equal(GridUtils.cell_world(game.grid, Vector2i(4, 2)))


# ...and the UNIT STAYS PUT. Every other ghost in OverlayManager pairs "draw a stand-in" with
# "hide the real sprite", because unit_at_pointer leans on that identity -- so a preview of a move
# nobody has made must not take it. This is the case that refuses the tidy-up making this one
# consistent with the others.
func test_the_hover_ghost_does_not_move_where_the_unit_is() -> void:
	var friend := _spawn(PLAYER, Vector2i(2, 2))
	game.enter_move_mode(friend)
	game.selected_unit = friend
	game.hover_presenter.update_hover_visuals(Vector2i(4, 2))

	assert_bool(friend.visuals.projected).override_failure_message(
			"the hover ghost hid the real sprite, so the board now says the unit has moved") \
		.is_false()
	assert_object(game.unit_at_pointer(Vector2i(2, 2))).override_failure_message(
			"the unit stopped answering for the cell it is standing on").is_same(friend)


# It leaves with the gesture. Both doors: moving the pointer onto a cell outside the footprint,
# and leaving the mode outright.
func test_the_hover_ghost_leaves_with_the_gesture() -> void:
	var friend := _spawn(PLAYER, Vector2i(2, 2))
	game.enter_move_mode(friend)
	game.selected_unit = friend
	game.hover_presenter.update_hover_visuals(Vector2i(4, 2))
	assert_int(_om().hover_ghost_sprites.size()).is_equal(1)   # precondition, not the claim

	game.exit_current_mode()
	assert_array(_om().hover_ghost_sprites).override_failure_message(
			"the stand-in outlived the move gesture").is_empty()


# THE FLASH GOES WHITE AND SITS THERE (#1069). The dev, playing #1066's version: "the flashes are
# very hard to see. Instead of going dark, the flashes should be going white, and linger on the
# white part of the flash a bit longer, to draw attention."
#
# The VALUES are never pinned -- both are sliders he may drag tomorrow -- only the two properties
# that make it a flash rather than a breathe: the peak is BRIGHTER than resting, and the cycle
# spends real time AT it. A symmetric ramp touches its peak for one frame, which is what made the
# dips read as the event.
func test_the_pin_flash_is_a_flash_rather_than_a_breathe() -> void:
	var enemy := _spawn(ENEMY, Vector2i(3, 2))
	game.toggle_enemy_pin(enemy)
	assert_object(enemy.visuals.pin_tween).override_failure_message(
			"nothing is flashing, so this case cannot see its own claim").is_not_null()

	var base: Color = enemy.visuals.base_modulate
	var peak: Color = UnitVisuals.PIN_PULSE_MODULATE
	assert_bool(peak.r > base.r and peak.g > base.g and peak.b > base.b).override_failure_message(
			"the pin's peak is not brighter than the sprite at rest, so the cue is a DIP") \
		.is_true()
	assert_float(UnitVisuals.PIN_PULSE_HOLD).override_failure_message(
			"the flash holds for no time at all -- it touches white for one frame and spends the "
			+ "rest of the cycle coming back, which is what reads as going dark").is_greater(0.0)




# A turned knob reaches a STANDING flash. _sync_pin_flashes is idempotent by design -- it compares
# "should there be one" against "is there one" -- so it would leave the old endpoints running: a
# Tween holds what it was started with. #591 found exactly this on the aim pulse, where a retuned
# colour breathed back to the old one twice a second.
func test_turning_the_pin_flash_rebuilds_the_one_already_running() -> void:
	var enemy := _spawn(ENEMY, Vector2i(3, 2))
	game.toggle_enemy_pin(enemy)
	var before: Tween = enemy.visuals.pin_tween
	assert_object(before).is_not_null()

	game.restyle_pin_flashes()
	assert_object(enemy.visuals.pin_tween).override_failure_message(
			"the standing flash was torn down and not rebuilt").is_not_null()
	assert_bool(enemy.visuals.pin_tween == before).override_failure_message(
			"the standing flash is the SAME tween, so it is still running the old endpoints") \
		.is_false()


# ...and the hold reaches the TWEEN, not just the constant. Pulse gained an optional interval for
# this, and a caller that forgot to pass it would leave every assertion above green while the flash
# on screen was unchanged -- the "test the wire" shape, one knob along.
#
# Stepped by hand rather than waited out: Tween.custom_step advances a paused tween by an exact
# delta, so this asks what the two shapes are DOING at one moment instead of putting a second of
# real clock on the suite.
func test_a_held_pulse_is_still_at_its_peak_when_a_plain_one_has_started_falling() -> void:
	var probe := Sprite2D.new()
	game.add_child(probe)
	var peak := Color(2.0, 2.0, 2.0, 1.0)

	var plain_target := Sprite2D.new()
	game.add_child(plain_target)
	var plain := Pulse.start(probe, plain_target, &"modulate", Color.WHITE, peak, 0.2, 0.0)
	var held_target := Sprite2D.new()
	game.add_child(held_target)
	var held := Pulse.start(probe, held_target, &"modulate", Color.WHITE, peak, 0.2, 0.4)
	plain.pause()
	held.pause()

	plain.custom_step(0.2)   # both have just reached the peak
	held.custom_step(0.2)
	assert_float(held_target.modulate.r).override_failure_message(
			"the held pulse never reached its peak at all").is_equal_approx(peak.r, 0.01)

	plain.custom_step(0.1)   # ...and now, halfway into what the hold covers
	held.custom_step(0.1)
	assert_bool(plain_target.modulate.r < peak.r - 0.01).override_failure_message(
			"the plain pulse is not falling, so this case cannot tell the two shapes apart").is_true()
	assert_float(held_target.modulate.r).override_failure_message(
			"the hold never reached the tween -- the flash starts coming back the instant it "
			+ "arrives, which is what reads as a dip rather than a flash").is_equal_approx(peak.r, 0.01)

	plain.kill()
	held.kill()
	probe.queue_free()
	plain_target.queue_free()
	held_target.queue_free()


# ...and NOT for an enemy, which a plain click also selects -- the ring opens on anybody, the
# hotseat allowance. #710 slice 3's ruling holds at the click exactly as it does on hover: an enemy
# is read in the enemy's own vocabulary, so painting your red over one would be a second picture of
# the same fact, in the colour that means "yours".
func test_selecting_an_enemy_paints_its_field_and_never_your_red() -> void:
	var foe := _spawn(ENEMY, Vector2i(3, 2))
	game._click_idle(foe.movement.cell)
	assert_array(_om().reach_overlay.get_used_cells()).override_failure_message(
			"selecting an enemy painted its reach in YOUR red").is_empty()
