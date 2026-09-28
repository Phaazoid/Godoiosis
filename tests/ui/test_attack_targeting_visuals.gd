# What ATTACK_TARGETING shows, and on which channel (2026-08-01).
#
# TWO separate signals, and the whole point is that they never compete for the same pixel:
#   * the RED REACH LAYER is the weapon's full range. It is drawn once on entering the mode and is
#     NEVER modified afterwards -- not filtered, not re-tiled, not partially erased.
#   * the AIM is shown on two channels of its own: the victims' sprites PULSE (when the attack hits
#     units), and every footprint tile FLASHES in the order the attack travels (#1057 part 2 -- it
#     used to be only a map-hitting attack whose tiles moved at all).
#
# This replaces a two-tier overlay that stamped a marker tile onto reach cells holding a target. It
# could not work: a TileMapLayer holds ONE tile per cell, so the marker always REPLACED the range
# fill underneath. Worst at scale -- for a ForwardWide attack every cell of a lane containing a
# victim got marked, so a single enemy erased an entire lane of range and the player saw an L of
# whatever was left. The pattern-less case below is the same mechanism with a smaller blast radius,
# which is why "every reach cell keeps its fill" is the assertion that pins it.
#
# Fixture is #114's -- the instanced root MUST be named "Main" under /root.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

const ATTACKER_CELL := Vector2i(1, 1)
const FOE_CELL := Vector2i(2, 1)
const AWAY_CELL := Vector2i(1, 2)   # in reach, empty

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


# A shapeless weapon at the default range 1 -- reach is the four neighbours -- and one enemy
# standing on one of them.
func _armed_attacker(targets: EquippableData.TargetMode) -> Unit:
	var attacker: Unit = game.spawn_unit(H.make_unit_data({}, PLAYER), ATTACKER_CELL)
	var foe: Unit = game.spawn_unit(H.make_unit_data({}, ENEMY), FOE_CELL)
	assert_object(attacker).is_not_null()   # the fixture's own setup, not the thing under test
	assert_object(foe).is_not_null()
	var weapon := H.make_weapon(3)
	weapon.template.main_attack.targets = targets
	attacker.equipped_weapon = weapon
	return attacker


func _foe() -> Unit:
	for unit: Unit in game._all_units():
		if unit.get_faction() == ENEMY:
			return unit
	return null


# Enter the mode and aim at `cell`, the way the mouse does. selected_unit is what the hover branch
# reads; the mode transition itself is covered by test_game_scene_smoke.gd.
func _aim_at(attacker: Unit, cell: Vector2i) -> void:
	game.enter_attack_mode(attacker)
	game.selected_unit = attacker
	game.hover_presenter._hover_attack_targeting(cell)


# The four cells the fixture's weapon reaches, stated rather than re-derived through Reach -- an
# assertion that asks the code under test what it should be proves nothing. min_range 1 means
# ADJACENT, so the attacker's own cell is deliberately not among them (#808).
func _reach_cells() -> Array[Vector2i]:
	return [ATTACKER_CELL + Vector2i.UP, ATTACKER_CELL + Vector2i.DOWN,
		ATTACKER_CELL + Vector2i.LEFT, ATTACKER_CELL + Vector2i.RIGHT]


func _tiles_flashing() -> bool:
	return not game.overlay_manager.aim_flash_steps().is_empty()


func _flash_clock() -> float:
	return game.overlay_manager._aim_flash.clock


func _unit_pulsing(unit: Unit) -> bool:
	return unit != null and unit.visuals.pulse_tween != null


# ==============================================================================
#  The reach layer is inviolable
# ==============================================================================

# THE regression. Nothing about targeting may remove or replace a reach tile -- an occupied cell is
# still a cell you can reach, and the range readout is the only thing that says so.
func test_every_reach_cell_keeps_its_fill_even_with_a_target_standing_in_it() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.UNIT)

	game.enter_attack_mode(attacker)

	for cell in _reach_cells():
		assert_that(game.overlay_manager.attack_overlay.get_cell_atlas_coords(cell)) \
			.override_failure_message("reach cell %s is not the plain range fill" % cell) \
			.is_equal(OverlayManager.ATLAS_COORDS)


# ...and aiming does not disturb it either: the aim's feedback lives entirely on other channels.
func test_aiming_does_not_change_the_reach_layer() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.BOTH)

	_aim_at(attacker, FOE_CELL)

	for cell in _reach_cells():
		assert_that(game.overlay_manager.attack_overlay.get_cell_atlas_coords(cell)) \
			.is_equal(OverlayManager.ATLAS_COORDS)


# Units draw ABOVE the reach layer, or a pulsing target is hidden under the very tile that says you
# can reach it. AttackOverlay/HoverOverlay sat at z 5 against Unit.BASE_SPRITE_INDEX 4 until now.
func test_the_reach_and_aim_layers_sit_below_units() -> void:
	assert_int(game.overlay_manager.attack_overlay.z_index).is_less(Unit.BASE_SPRITE_INDEX)
	assert_int(game.overlay_manager.hover_overlay.z_index).is_less(Unit.BASE_SPRITE_INDEX)


# The reach layer's FILL never changes (above); its COLOR does -- red for damage, green for a heal
# (#123 follow-up), keyed off the fired attack's own `heals` flag.
func test_reach_layer_is_red_for_a_damaging_attack() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.UNIT)

	game.enter_attack_mode(attacker)

	assert_that(game.overlay_manager.attack_overlay.modulate).is_equal(OverlayManager.ATTACK_MODULATE)


func test_reach_layer_is_green_for_a_healing_attack() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.UNIT)
	attacker.get_equipped_weapon().template.main_attack.heals = true

	game.enter_attack_mode(attacker)

	assert_that(game.overlay_manager.attack_overlay.modulate).is_equal(OverlayManager.HEAL_ATTACK_MODULATE)


# ==============================================================================
#  The victims pulse; every footprint flashes
# ==============================================================================

# A SINGLE-TARGET swing previews only as far as its victim (#1057). The wash is the sweep's own
# answer, so the path's tiles past the foe it stops at stay dark -- before #1057 the same path washed
# all three, as an AoE swing still does.
func test_a_path_swing_washes_only_as_far_as_its_victim() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.UNIT)
	var main := (attacker.equipped_weapon as WeaponInstance).template.main_attack
	main.max_range = 0
	main.swing = true
	var ahead: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -3)]
	main.attack_shape = P.pathed([ahead] as Array[Array])
	_aim_at(attacker, FOE_CELL)
	var layer: TileMapLayer = game.overlay_manager.overlay_map[OverlayManager.OverlayType.HOVER]
	assert_array(layer.get_used_cells()).contains_exactly([FOE_CELL])


# Every footprint flashes (#1054 ruling 19), a unit-only attack's included -- which is what retired
# the rule this case used to pin, that only an attack hitting the ground moved its tiles.
func test_a_unit_attack_pulses_the_unit_and_flashes_the_tiles() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.UNIT)

	_aim_at(attacker, FOE_CELL)

	assert_bool(_unit_pulsing(_foe())).is_true()
	assert_bool(_tiles_flashing()).is_true()


# The hover asks no targets question of its own since #1135: nobody pulses because the sweep finds
# nobody, RulesService.is_attack_victim refusing every unit a map-only attack reaches.
func test_a_map_attack_flashes_the_tiles_and_does_not_pulse_the_unit() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.MAP)

	_aim_at(attacker, FOE_CELL)

	assert_bool(_tiles_flashing()).is_true()
	assert_bool(_unit_pulsing(_foe())).is_false()


# ...but the CURRENT still catches (dev, 2026-09-28), and a soaked body on the aimed cell conducts,
# so a map-only shock pulses the unit it will really hit. A hover that kept its own targets gate
# would hide exactly this unit -- the second answer to "who is hit" #1135 deleted.
func test_a_map_only_shock_pulses_the_wet_unit_its_current_catches() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.MAP)
	(attacker.equipped_weapon as WeaponInstance).template.main_attack.elemental_damage_type = Elemental.Element.SHOCK
	_foe().add_element_state(Elemental.State.WET)

	_aim_at(attacker, FOE_CELL)

	assert_bool(_unit_pulsing(_foe())).is_true()


func test_a_both_attack_flashes_the_tiles_and_pulses_the_unit_together() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.BOTH)

	_aim_at(attacker, FOE_CELL)

	assert_bool(_tiles_flashing()).is_true()
	assert_bool(_unit_pulsing(_foe())).is_true()


# THE WIRE for the travel order: what the hover hands the flash, for a swing and for a true AoE.
# Stated rather than re-derived -- a two-cell line fired east from (1,1) reaches (2,1) then (3,1),
# and a true AoE lands both at once. Two cells, because the cleared board ends at x 3.
func _line_of_two(attacker: Unit, swing: bool) -> void:
	var main := (attacker.equipped_weapon as WeaponInstance).template.main_attack
	P.line(main, 2)
	main.swing = swing


func test_a_swing_flashes_its_tiles_in_the_order_it_travels() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.MAP)
	_line_of_two(attacker, true)

	_aim_at(attacker, FOE_CELL)

	var steps: Dictionary[Vector2i, Array] = game.overlay_manager.aim_flash_steps()
	assert_array(steps.get(Vector2i(2, 1), [])).contains_exactly([0])
	assert_array(steps.get(Vector2i(3, 1), [])).contains_exactly([1])


func test_a_true_aoe_flashes_its_whole_footprint_at_once() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.MAP)
	_line_of_two(attacker, false)

	_aim_at(attacker, FOE_CELL)

	var steps: Dictionary[Vector2i, Array] = game.overlay_manager.aim_flash_steps()
	assert_int(steps.size()).is_equal(2)
	for cell: Vector2i in steps:
		assert_array(steps[cell]).contains_exactly([0])


# A path swing's flash stops where its wash does: at the victim (ruling 19, "a path stops flashing
# where it hits").
func test_a_path_swing_flashes_only_as_far_as_its_victim() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.UNIT)
	var main := (attacker.equipped_weapon as WeaponInstance).template.main_attack
	main.max_range = 0
	main.swing = true
	var ahead: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -3)]
	main.attack_shape = P.pathed([ahead] as Array[Array])

	_aim_at(attacker, FOE_CELL)

	assert_array(game.overlay_manager.aim_flash_steps().keys()).contains_exactly([FOE_CELL])


# An ALLY is not a target unless the attack splashes -- same hits_allies rule the resolver uses, so
# the pulse marks exactly what would be hit.
func test_an_ally_does_not_pulse_for_a_non_splashing_attack() -> void:
	var attacker: Unit = game.spawn_unit(H.make_unit_data({}, PLAYER), ATTACKER_CELL)
	var ally: Unit = game.spawn_unit(H.make_unit_data({}, PLAYER), FOE_CELL)
	var weapon := H.make_weapon(3)
	assert_bool(weapon.template.main_attack.hits_allies).is_false()   # the setup's own premise
	attacker.equipped_weapon = weapon

	_aim_at(attacker, FOE_CELL)

	assert_bool(_unit_pulsing(ally)).is_false()


# ==============================================================================
#  Starting and stopping — a loop nobody kills keeps writing modulate forever
# ==============================================================================

# Aiming elsewhere releases the previous target. set_target_pulse diffs rather than restarting, so
# this also guards against the whole set being torn down and rebuilt on every mouse move.
func test_aiming_away_stops_the_previous_targets_pulse() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.UNIT)
	_aim_at(attacker, FOE_CELL)
	assert_bool(_unit_pulsing(_foe())).is_true()

	game.hover_presenter._hover_attack_targeting(AWAY_CELL)

	assert_bool(_unit_pulsing(_foe())).is_false()


# Holding the same aim must NOT restart the tween -- a restart per hover event resets the phase and
# reads as a strobe rather than a pulse.
func test_holding_the_same_aim_keeps_one_continuous_pulse() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.UNIT)
	_aim_at(attacker, FOE_CELL)
	var first: Tween = _foe().visuals.pulse_tween

	game.hover_presenter._hover_attack_targeting(FOE_CELL)

	assert_object(_foe().visuals.pulse_tween).is_same(first)


# ...and the same for the flash: re-hovering one aim keeps its loop where it is, or every mouse move
# restarts the travel from the top and it never gets past its first step.
func test_holding_the_same_aim_keeps_the_flash_running() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.UNIT)
	_aim_at(attacker, FOE_CELL)
	for i in 3:
		await await_idle_frame()
	var running := _flash_clock()
	assert_float(running).is_greater(0.0)   # the clock really runs, or the next line proves nothing

	game.hover_presenter._hover_attack_targeting(FOE_CELL)

	assert_float(_flash_clock()).is_equal(running)


func test_a_new_aim_restarts_the_flash_from_the_top() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.UNIT)
	_aim_at(attacker, FOE_CELL)
	for i in 3:
		await await_idle_frame()
	assert_float(_flash_clock()).is_greater(0.0)

	game.hover_presenter._hover_attack_targeting(AWAY_CELL)

	assert_float(_flash_clock()).is_equal(0.0)


# The flash's clock lives under Game, so the freeze a modal puts on Game stops it -- which is what
# holds the flash still in BOTH views behind the pause menu, the diorama having no clock of its own.
func test_a_modal_freezes_the_flash() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.UNIT)
	_aim_at(attacker, FOE_CELL)
	await await_idle_frame()
	var modal := Control.new()
	get_tree().root.add_child(modal)
	ModalLock.claim(modal, game)
	var frozen := _flash_clock()

	for i in 3:
		await await_idle_frame()

	assert_float(_flash_clock()).is_equal(frozen)
	modal.queue_free()
	await await_idle_frame()


func test_leaving_the_mode_stops_every_pulse_and_the_flash() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.BOTH)
	_aim_at(attacker, FOE_CELL)
	assert_bool(_unit_pulsing(_foe())).is_true()
	assert_bool(_tiles_flashing()).is_true()

	game.exit_current_mode()

	assert_bool(_unit_pulsing(_foe())).is_false()
	assert_bool(_tiles_flashing()).is_false()
	assert_that(_foe().visuals.sprite.modulate).is_equal(_foe().visuals.base_modulate)


# ==============================================================================
#  Vertical tolerance (#258): blocked cells say so, and the click agrees
# ==============================================================================

# Raise AWAY_CELL past the weapon's up-tolerance and arm the attacker. Every case below shares
# this shape; the flat cases above are untouched because clear_board wipes the heights store.
func _armed_attacker_below_a_ledge() -> Unit:
	var attacker := _armed_attacker(EquippableData.TargetMode.UNIT)
	# Tolerance and height are both in units (#427): reaches one level, the ledge is two.
	(attacker.get_equipped_weapon() as WeaponInstance).template.main_attack.up_tolerance = 2
	game.board_heights.set_cell(AWAY_CELL, 4)
	return attacker


# Membership never changes; the blocked cell wears the hatched fill instead of vanishing.
func test_a_blocked_cell_wears_the_hatched_fill_and_membership_holds() -> void:
	var attacker := _armed_attacker_below_a_ledge()

	game.enter_attack_mode(attacker)

	for cell in _reach_cells():
		var expected: Vector2i = OverlayManager.BLOCKED_ATLAS_COORDS if cell == AWAY_CELL else OverlayManager.ATLAS_COORDS
		assert_that(game.overlay_manager.attack_overlay.get_cell_atlas_coords(cell)) \
			.override_failure_message("reach cell %s wears the wrong fill" % cell) \
			.is_equal(expected)


# The wire test: the real click handler on a blocked cell queues NOTHING, and the identical click
# on a hittable cell still queues -- so the hatch and the refusal can never disagree. Counted as
# ATTACK orders: activating a squad in the real scene also inserts the hold-move filler.
func _queued_attacks(unit: Unit) -> int:
	var count := 0
	for action in unit.squad.action_queue:
		if action.action_type == BaseAction.ActionType.ATTACK:
			count += 1
	return count


func test_clicking_a_blocked_cell_queues_nothing() -> void:
	var attacker := _armed_attacker_below_a_ledge()

	game.enter_attack_mode(attacker)
	game.selected_unit = attacker
	game._click_attack_targeting(AWAY_CELL)
	assert_int(_queued_attacks(attacker)).is_equal(0)

	game.enter_attack_mode(attacker)
	game.selected_unit = attacker
	game._click_attack_targeting(FOE_CELL)
	assert_int(_queued_attacks(attacker)).is_equal(1)


func test_hovering_a_blocked_cell_previews_nothing() -> void:
	var attacker := _armed_attacker_below_a_ledge()

	_aim_at(attacker, AWAY_CELL)

	assert_array(game.overlay_manager.hover_overlay.get_used_cells()).is_empty()
	assert_bool(_tiles_flashing()).is_false()
	assert_bool(_unit_pulsing(_foe())).is_false()


# ==============================================================================
#  The sight trace (#258): the bead path the aim gate judged, stored for both stacks
# ==============================================================================

func test_hovering_an_aim_stores_its_sight_trace_and_exit_clears_it() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.UNIT)

	_aim_at(attacker, FOE_CELL)
	var trace: Reach.SightTrace = game.overlay_manager.sight_trace
	assert_object(trace).is_not_null()
	assert_bool(trace.blocked).is_false()

	game.exit_current_mode()
	assert_object(game.overlay_manager.sight_trace).is_null()


func test_a_wall_covered_aim_stores_a_blocked_trace() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.UNIT)
	P.point((attacker.get_equipped_weapon() as WeaponInstance).template.main_attack, 2, 1)
	game.board_heights.set_cell(Vector2i(1, 2), 6)   # a wall between (1,1) and the target at (1,3)

	_aim_at(attacker, Vector2i(1, 3))

	var trace: Reach.SightTrace = game.overlay_manager.sight_trace
	assert_object(trace).is_not_null()
	assert_bool(trace.blocked).is_true()
	assert_array(game.overlay_manager.hover_overlay.get_used_cells()).is_empty()   # the aim is refused


# Melee draws no sight line (dev, 2026-08-20: "visually obvious anytime") -- the aim itself still
# previews; only the trace stays away. Ranged aims keep theirs (the cases above).
func test_a_melee_aim_draws_no_sight_line() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.UNIT)
	(attacker.get_equipped_weapon() as WeaponInstance).template.main_attack.vertical_rule = AttackData.VerticalRule.MELEE

	_aim_at(attacker, FOE_CELL)

	assert_object(game.overlay_manager.sight_trace).is_null()
	assert_bool(game.overlay_manager.hover_overlay.get_used_cells().is_empty()).is_false()


# ==============================================================================
#  What the aim DROPS (#1058 D2b, ruling 52)
# ==============================================================================

func _main_attack(attacker: Unit) -> WeaponAttackData:
	return (attacker.equipped_weapon as WeaponInstance).template.main_attack


# A payload that covers the one tile it goes off on.
func _bomb(named: String) -> WeaponAttackData:
	var bomb := WeaponAttackData.new()
	bomb.display_name = named
	bomb.power = 1
	bomb.targets = EquippableData.TargetMode.MAP
	P.point(bomb, 1)
	return bomb


# ...and one that goes off as a 3x3 true AoE centred on it.
func _blast(named: String, targets := EquippableData.TargetMode.MAP) -> WeaponAttackData:
	var blast := WeaponAttackData.new()
	blast.display_name = named
	blast.power = 1
	blast.targets = targets
	var square: Array[Vector2i] = []
	for x in range(-1, 2):
		for y in range(-1, 2):
			square.append(Vector2i(x, y))
	P.stamped(blast, 3, square)
	blast.swing = false
	return blast


func _insets() -> Array[Vector2i]:
	return game.overlay_manager.payload_overlay.get_used_cells()


func _steps_at(cell: Vector2i) -> Array:
	return game.overlay_manager.aim_flash_steps().get(cell, [])


# The 3x3 round AWAY_CELL, stated rather than derived -- open ground on the cleared board, where the
# column at x 3 is not for its top rows.
func _square_round_away() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(0, 3):
		for y in range(1, 4):
			cells.append(Vector2i(x, y))
	return cells


# A sticky bomber: a UNIT hit that shoves one tile and drops a bomb, and its foe at AWAY_CELL, so the
# shove runs south onto open ground.
func _sticky_bomber() -> Unit:
	var attacker: Unit = game.spawn_unit(H.make_unit_data({}, PLAYER), ATTACKER_CELL)
	var foe: Unit = game.spawn_unit(H.make_unit_data({}, ENEMY), AWAY_CELL)
	assert_object(attacker).is_not_null()
	assert_object(foe).is_not_null()
	var weapon := H.make_weapon(3)
	weapon.template.main_attack.targets = EquippableData.TargetMode.UNIT
	weapon.template.main_attack.knockback = 1
	weapon.template.main_attack.payload = _bomb("Bomb")
	attacker.equipped_weapon = weapon
	return attacker


# Ruling 43 at the hover: a sticky bomb goes off where the hit LEAVES its victim, so its square sits
# on the landing tile. Only the resolve knows that tile, which is why the hover asks one.
func test_a_sticky_bombs_inset_sits_where_the_shove_leaves_the_foe() -> void:
	var attacker := _sticky_bomber()
	var landing := AWAY_CELL + Vector2i.DOWN

	_aim_at(attacker, AWAY_CELL)

	assert_array(_insets()).override_failure_message(
			"the bomb's square is at %s -- the landing tile is %s" % [_insets(), landing]
		).contains_exactly([landing])
	assert_array(_steps_at(landing)).override_failure_message(
			"the bomb does not flash one step after the hit that sticks it").contains_exactly([1])


# A tile only the payload reaches is an INSET; the tile the aim strikes itself stays the aim's full
# tile, and flashes a second time when the payload goes off on it (ruling 52).
func test_a_payloads_own_tiles_are_insets_flashing_one_step_after_the_aim() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.MAP)
	_main_attack(attacker).payload = _blast("Blast")
	var expected := _square_round_away()
	expected.erase(AWAY_CELL)

	_aim_at(attacker, AWAY_CELL)

	assert_array(_insets()).override_failure_message(
			"the blast's insets are %s" % [_insets()]).contains_exactly_in_any_order(expected)
	assert_array(game.overlay_manager.hover_overlay.get_used_cells()).override_failure_message(
			"the payload's tiles joined the aim's own footprint").contains_exactly([AWAY_CELL])
	for cell in expected:
		assert_array(_steps_at(cell)).override_failure_message(
				"payload tile %s flashes at %s, not one step after the aim" % [cell, _steps_at(cell)]
			).contains_exactly([1])
	assert_array(_steps_at(AWAY_CELL)).override_failure_message(
			"the tile the aim and its payload both hit does not flash twice").contains_exactly([0, 1])


# Each LEVEL is one step later than the one above it, however deep the chain runs.
func test_each_level_of_a_chain_flashes_one_step_after_the_last() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.MAP)
	var bomb := _bomb("Bomb")
	bomb.payload = _bomb("Second")
	_main_attack(attacker).payload = bomb

	_aim_at(attacker, FOE_CELL)

	assert_array(_steps_at(FOE_CELL)).override_failure_message(
			"a two-deep chain on one tile flashes at %s" % [_steps_at(FOE_CELL)]).contains_exactly([0, 1, 2])


# Whoever a payload hits pulses with the aim's own victims: they are hit by this aim.
func test_a_unit_the_payload_hits_pulses() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.MAP)
	var main := _main_attack(attacker)
	P.point(main, 2)
	main.payload = _blast("Blast", EquippableData.TargetMode.BOTH)

	_aim_at(attacker, Vector2i(2, 2))   # a tile only; the blast round it reaches the foe at (2,1)

	assert_bool(_unit_pulsing(_foe())).override_failure_message(
			"the foe the blast will hit is not pulsing").is_true()


# The hover's resolve publishes the candidate's shove onto the board, so the restore has to follow it:
# nothing a hover merely LOOKED at may be left projected.
func test_the_hovers_shove_is_not_left_on_the_board() -> void:
	var attacker := _sticky_bomber()

	_aim_at(attacker, AWAY_CELL)
	assert_array(_insets()).contains_exactly([AWAY_CELL + Vector2i.DOWN])   # the resolve saw the shove

	assert_that(_foe().get_projected_destination()).override_failure_message(
			"the foe is drawn where a shove nobody queued would leave them").is_equal(AWAY_CELL)


# ...and a QUEUED shove survives it. Re-aiming displaces the queued order inside the hypothetical, so
# without the restore the foe's real landing would be wiped by merely moving the pointer.
func test_a_queued_shove_survives_the_hover() -> void:
	var attacker := _sticky_bomber()
	game.squad_manager.queue_action(attacker.squad, AttackAction.declare(attacker, ATTACKER_CELL, AWAY_CELL))
	game.squad_manager.resolve_plan(attacker.squad, game._board())
	var landing := AWAY_CELL + Vector2i.DOWN
	assert_that(_foe().get_projected_destination()).is_equal(landing)   # the queued shove, published

	_aim_at(attacker, FOE_CELL)

	assert_that(_foe().get_projected_destination()).override_failure_message(
			"hovering another aim wiped the queued shove off the board").is_equal(landing)


func test_leaving_aim_mode_clears_the_payload_tiles() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.MAP)
	_main_attack(attacker).payload = _blast("Blast")
	_aim_at(attacker, FOE_CELL)
	assert_bool(_insets().is_empty()).is_false()   # non-vacuity

	game.exit_current_mode()

	assert_array(_insets()).override_failure_message(
			"the payload's squares outlived the aim").is_empty()
	assert_array(game.overlay_manager._aim_flash.insets).is_empty()


# A WATCH shows no payloads: its shot fires later, from wherever the crosser is.
func test_a_watch_declaration_shows_no_payloads() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.MAP)
	_main_attack(attacker).payload = _blast("Blast")

	game.enter_overwatch_mode(attacker)
	game.selected_unit = attacker
	game.hover_presenter._hover_attack_targeting(FOE_CELL)

	assert_bool(_tiles_flashing()).is_true()   # the watch's own aim still previews
	assert_array(_insets()).override_failure_message(
			"a watch previewed payloads that cannot know where they will go off").is_empty()
