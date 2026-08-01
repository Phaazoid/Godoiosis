# The ATTACK targeting overlay draws TWO tiers on one layer: the weapon's full reach, then a marker
# on each reach cell that actually holds a target. One layer means the marker tile REPLACES the fill
# on its own cell, and that is the whole hazard this suite exists for -- mark every cell and the
# range information is gone, which is exactly what shipped (2026-07-31): RulesService returned the
# entire reach as "marked" for any hits_map() attack, so a rune user's Fireball (TargetMode.BOTH,
# authored on the real Prolog carving) repainted its whole range as reticles with no fill left.
#
# The rule the fix rests on: the MARKER answers "is there something to hit here", never "is this aim
# legal". A MAP attack may legally aim at bare ground -- the fill already says so -- and marking
# every cell distinguishes nothing while destroying the layer underneath.
#
# Needs the real game scene: enter_attack_mode reads game._board() and draws through the live
# OverlayManager. Calling it directly rather than through a menu pick is fine HERE (unlike #105/
# #107, whose bugs lived in the clear_selection ordering) because the defect is inside the draw.
# Fixture is #114's -- the instanced root MUST be named "Main" under /root.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

const ATTACKER_CELL := Vector2i(1, 1)
const FOE_CELL := Vector2i(2, 1)

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


# An attacker with a pattern-less weapon (Reach falls back to Manhattan 1, so the reach is five
# known cells) and one enemy standing on exactly one of them.
func _armed_attacker(targets: EquippableData.TargetMode) -> Unit:
	var attacker: Unit = game.spawn_unit(H.make_unit_data({}, PLAYER), ATTACKER_CELL)
	var foe: Unit = game.spawn_unit(H.make_unit_data({}, ENEMY), FOE_CELL)
	assert_object(attacker).is_not_null()   # the fixture's own setup, not the thing under test
	assert_object(foe).is_not_null()
	var weapon := H.make_weapon(3)
	weapon.template.main_attack.targets = targets
	attacker.equipped_weapon = weapon
	return attacker


func _atlas_at(cell: Vector2i) -> Vector2i:
	return game.overlay_manager.attack_overlay.get_cell_atlas_coords(cell)


func _reach_cells() -> Array[Vector2i]:
	return GridUtils.cells_within_manhattan_range(ATTACKER_CELL, 1)


# Every reach cell EXCEPT the occupied one still carries the plain range fill.
func _assert_range_fill_survives() -> void:
	var filled := 0
	for cell in _reach_cells():
		if cell == FOE_CELL:
			continue
		assert_that(_atlas_at(cell)) \
			.override_failure_message("reach cell %s lost its range fill to a marker" % cell) \
			.is_equal(OverlayManager.ATLAS_COORDS)
		filled += 1
	assert_int(filled).is_greater(0)


# ==============================================================================
#  The two tiers
# ==============================================================================

func test_a_unit_attack_marks_the_occupied_cell_and_fills_the_rest() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.UNIT)

	game.enter_attack_mode(attacker)

	assert_that(_atlas_at(FOE_CELL)).is_equal(OverlayManager.TARGET_ATLAS_COORDS)
	_assert_range_fill_survives()


# THE regression. A map-hitting attack is legal on bare ground, but that is the GATE's business --
# the marker still means "someone is standing here", so the range fill must be untouched. Reinstate
# the `if attack.hits_map(): return reach` shortcut in RulesService and this fails on every cell.
func test_a_map_hitting_attack_does_not_repaint_its_whole_range_as_markers() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.BOTH)

	game.enter_attack_mode(attacker)

	_assert_range_fill_survives()


# ...and it still marks the target it can hit. The negative twin: a fix that simply stopped marking
# anything would pass the test above, and this is what refuses that.
func test_a_map_hitting_attack_still_marks_an_occupied_cell() -> void:
	var attacker := _armed_attacker(EquippableData.TargetMode.BOTH)

	game.enter_attack_mode(attacker)

	assert_that(_atlas_at(FOE_CELL)).is_equal(OverlayManager.TARGET_ATLAS_COORDS)


# Nothing in reach -> the range draws with no markers at all. This is the case the whole two-tier
# design exists to keep honest: the player must still see how far the weapon reaches.
func test_an_empty_range_still_draws_the_reach() -> void:
	var attacker: Unit = game.spawn_unit(H.make_unit_data({}, PLAYER), ATTACKER_CELL)
	attacker.equipped_weapon = H.make_weapon(3)

	game.enter_attack_mode(attacker)

	for cell in _reach_cells():
		assert_that(_atlas_at(cell)) \
			.override_failure_message("reach cell %s was not drawn at all" % cell) \
			.is_equal(OverlayManager.ATLAS_COORDS)


# An ALLY on a reach cell is not a marker unless the attack splashes -- same hits_allies rule
# gather_attack_victims applies, so the board marks exactly what the resolver would hit.
func test_an_ally_is_not_marked_by_a_non_splashing_attack() -> void:
	var attacker: Unit = game.spawn_unit(H.make_unit_data({}, PLAYER), ATTACKER_CELL)
	var ally: Unit = game.spawn_unit(H.make_unit_data({}, PLAYER), FOE_CELL)
	assert_object(ally).is_not_null()
	var weapon := H.make_weapon(3)
	assert_bool(weapon.template.main_attack.hits_allies).is_false()   # the setup's own premise
	attacker.equipped_weapon = weapon

	game.enter_attack_mode(attacker)

	assert_that(_atlas_at(FOE_CELL)).is_equal(OverlayManager.ATLAS_COORDS)
