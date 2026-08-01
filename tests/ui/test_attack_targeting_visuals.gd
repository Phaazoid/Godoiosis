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


# A pattern-less weapon (Reach falls back to Manhattan 1, so reach is five known cells) and one
# enemy standing on one of them.
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


func _reach_cells() -> Array[Vector2i]:
	return GridUtils.cells_within_manhattan_range(ATTACKER_CELL, 1)


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
