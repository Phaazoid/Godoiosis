# What ATTACK_TARGETING shows, and on which channel (2026-08-01).
#
# TWO separate signals, and the whole point is that they never compete for the same pixel:
#   * the RED REACH LAYER is the weapon's full range. It is drawn once on entering the mode and is
#     NEVER modified afterwards -- not filtered, not re-tiled, not partially erased.
#   * the AIM is shown by PULSING what it would affect, and WHICH channel pulses is the attack's own
#     `targets`: units for UNIT, the footprint tiles for MAP, both for BOTH. So the kind of attack
#     being held reads at a glance.
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


func _tiles_pulsing() -> bool:
	return game.overlay_manager._tile_pulse != null


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
#  Which channel pulses is the attack's `targets`
# ==============================================================================

func test_a_unit_attack_pulses_the_unit_and_not_the_tiles() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.UNIT)

	_aim_at(attacker, FOE_CELL)

	assert_bool(_unit_pulsing(_foe())).is_true()
	assert_bool(_tiles_pulsing()).is_false()


func test_a_map_attack_pulses_the_tiles_and_not_the_unit() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.MAP)

	_aim_at(attacker, FOE_CELL)

	assert_bool(_tiles_pulsing()).is_true()
	assert_bool(_unit_pulsing(_foe())).is_false()


func test_a_both_attack_pulses_tiles_and_unit_together() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.BOTH)

	_aim_at(attacker, FOE_CELL)

	assert_bool(_tiles_pulsing()).is_true()
	assert_bool(_unit_pulsing(_foe())).is_true()


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


func test_leaving_the_mode_stops_every_pulse() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.BOTH)
	_aim_at(attacker, FOE_CELL)
	assert_bool(_unit_pulsing(_foe())).is_true()
	assert_bool(_tiles_pulsing()).is_true()

	game.exit_current_mode()

	assert_bool(_unit_pulsing(_foe())).is_false()
	assert_bool(_tiles_pulsing()).is_false()
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
	assert_bool(_tiles_pulsing()).is_false()
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
