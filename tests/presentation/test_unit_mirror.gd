# UnitMirror (#215): the reconcile loop against the REAL game — spawn parity with
# Prolog's roster, the pixel-metric position mirror (unit.position / 16 lands on
# standing points; the walk tween drives the glide), downed/death/clear-board
# reconciliation. The 2D game is the authority throughout; the mirror only reads.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const PROLOG := "res://Scenarios/missions/Prolog.tres"

var _scene: Node3D
var _game: Node2D
var _mirror: UnitMirror


func before_test() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	_game = _scene.game
	_mirror = _scene.get_node("UnitMirror") as UnitMirror
	_scene.load_mission(PROLOG)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


# Where the mirror seats a sprite standing on this cell. The y comes through
# BoardSpace.surface_point — the same seam UnitMirror places it with — rather than the literal 1.0
# that is only that seam's answer on a board with no hills painted on it.
func _sprite_seat(cell: Vector2i) -> Vector3:
	var heights: BoardHeights = _game.board_heights
	return Vector3(cell.x + 0.5, BoardSpace.surface_point(cell, heights).y, cell.y + 0.5)


func _live_units() -> Array[Unit]:
	var live: Array[Unit] = []
	for child in _game.units_root.get_children():
		var unit := child as Unit
		if unit != null:
			live.append(unit)
	return live


func test_the_roster_mirrors_one_to_one() -> void:
	var live := _live_units()
	# Non-vacuity, not a census. The claim is PARITY — mirrored_count equals the live roster — and
	# a threshold ("Prolog fields 10") only says the load worked, while breaking the day the roster
	# is re-cast. Every count in this file is derived from the board it just loaded.
	assert_bool(live.size() > 0).override_failure_message(
			"the board spawned nobody; parity over an empty roster proves nothing").is_true()
	assert_int(_mirror.mirrored_count()).is_equal(live.size())
	for unit in live:
		var sprite := _mirror.sprite_for(unit)
		assert_object(sprite).is_not_null()
		assert_that(sprite.position).is_equal(_sprite_seat(unit.movement.cell))


func test_a_real_walk_glides_the_sprite_to_the_destination() -> void:
	var unit := _live_units()[0]
	var from := unit.movement.cell
	var to := from + Vector2i(1, 0)
	unit.movement.move_speed = 4000  # crank: the tween still runs, just fast
	unit.movement.move_along_path([from, to] as Array[Vector2i])
	await unit.movement.movement_finished
	# Two frames, not one: process_frame resumes coroutines BEFORE node _process,
	# and the tween's finish lands after the mirror's sync — one await reads stale.
	await await_idle_frame()
	await await_idle_frame()
	var sprite := _mirror.sprite_for(unit)
	assert_that(sprite.position).is_equal(_sprite_seat(to))
	assert_that(sprite.cell).is_equal(BoardSpace.of_cell(to, _game.board_heights.elevation_at(to)))


func test_downed_and_death_reconcile() -> void:
	var unit := _live_units()[0]
	unit._go_downed(false)
	await await_idle_frame()
	var sprite := _mirror.sprite_for(unit)
	assert_bool(sprite.is_downed()).is_true()

	var before := _mirror.mirrored_count()
	var victim := _live_units()[1]
	victim.die()
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_mirror.mirrored_count()).is_equal(before - 1)


# The rig's own settle: process_frame resumes coroutines BEFORE node _process.
func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func test_a_downed_unit_stays_on_screen() -> void:
	# #232, a 4c regression. The mirror copied $MapSprite.visible to get projected-hide
	# parity, and Unit._show_downed_sprite hides that SAME flag to swap in the separate
	# downed art — so a unit going down vanished from the diorama one line after
	# set_downed had correctly mirrored it. Note that the reconcile case above passes
	# against the bug: it asserts the texture swap, not that anything is drawn.
	var unit := _live_units()[0]
	unit._go_downed(false)
	await _settle()
	var sprite := _mirror.sprite_for(unit)
	assert_bool(sprite.is_downed()).is_true()
	assert_bool(sprite.visible).override_failure_message(
			"the downed unit vanished from the diorama").is_true()


func test_a_projected_unit_still_hides_for_its_ghost() -> void:
	# The other half of the same flag: the hide existed for a real reason, and the fix must
	# not simply delete it. A unit whose planning ghost is drawn elsewhere must not also be
	# standing on the cell it is leaving.
	var unit := _live_units()[0]
	var sprite := _mirror.sprite_for(unit)
	assert_bool(sprite.visible).override_failure_message(
			"it was already hidden; the case proves nothing").is_true()

	unit.visuals.set_projected(true)
	await _settle()
	assert_bool(sprite.visible).override_failure_message(
			"a projected unit is drawn twice — as its ghost AND on its old cell").is_false()

	unit.visuals.set_projected(false)
	await _settle()
	assert_bool(sprite.visible).is_true()


func test_the_faction_tint_reaches_the_diorama() -> void:
	# Reported in play: enemies were not shaded red in 3D. _apply_faction_visuals sets
	# modulate on the UNIT node — 2D multiplies it down the tree for free — while the
	# mirror copied only $MapSprite's own, so the tint never crossed.
	var player: Unit = null
	var enemy: Unit = null
	for unit in _live_units():
		if player == null and unit.get_faction() == Team.Faction.PLAYER:
			player = unit
		if enemy == null and unit.get_faction() == Team.Faction.ENEMY:
			enemy = unit
	assert_object(player).is_not_null()
	assert_object(enemy).override_failure_message("Prolog fields no enemy; the case is vacuous").is_not_null()
	await _settle()

	# Asserted as the PROPERTY the dev reported — the enemy reads red — rather than by
	# restating the production expression, which would only prove the code equals itself.
	var enemy_tint: Color = _mirror.sprite_for(enemy).modulate
	assert_bool(enemy_tint.r > enemy_tint.g and enemy_tint.r > enemy_tint.b) \
		.override_failure_message(
			"the enemy mirrored as %s — the faction tint never left the 2D Unit node" % enemy_tint
			).is_true()
	# ...and non-vacuous: the two factions must actually differ on screen.
	var player_tint: Color = _mirror.sprite_for(player).modulate
	assert_bool(player_tint.is_equal_approx(enemy_tint)).override_failure_message(
			"both factions mirror the same colour — the tint discriminates nothing").is_false()


func test_clear_board_empties_the_mirror() -> void:
	assert_bool(_mirror.mirrored_count() > 0).is_true()
	_game.scenario_manager.clear_board()
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_mirror.mirrored_count()).is_equal(0)
