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


func _live_units() -> Array[Unit]:
	var live: Array[Unit] = []
	for child in _game.units_root.get_children():
		var unit := child as Unit
		if unit != null:
			live.append(unit)
	return live


func test_the_roster_mirrors_one_to_one() -> void:
	var live := _live_units()
	assert_bool(live.size() >= 8).is_true()  # Prolog fields 10
	assert_int(_mirror.mirrored_count()).is_equal(live.size())
	for unit in live:
		var sprite := _mirror.sprite_for(unit)
		assert_object(sprite).is_not_null()
		var expected := Vector3(
				unit.movement.cell.x + 0.5, 1.0, unit.movement.cell.y + 0.5)
		assert_that(sprite.position).is_equal(expected)


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
	assert_that(sprite.position).is_equal(Vector3(to.x + 0.5, 1.0, to.y + 0.5))
	assert_that(sprite.cell).is_equal(Vector3i(to.x, 0, to.y))


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


func test_clear_board_empties_the_mirror() -> void:
	assert_bool(_mirror.mirrored_count() > 0).is_true()
	_game.scenario_manager.clear_board()
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_mirror.mirrored_count()).is_equal(0)
