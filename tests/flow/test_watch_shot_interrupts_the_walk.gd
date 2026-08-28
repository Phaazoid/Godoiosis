# WHEN a triggered shot plays back (#567, docs/design/standing-reactions.md).
#
# tests/law/test_overwatch_trigger.gd proves the resolve records the moment. This suite exists
# because that is exactly the shape that ships broken here -- #103, #126, #131 -- both ends correct
# and nothing joining them: the moment was recorded and the playback ignored it for the mechanic's
# whole first life. So every case drives the real OrderExecutor.execute_orders over a real walk on
# the real game scene, and reads WHERE THE UNITS WERE at the instant the damage landed.
#
# `UnitInstance.hp_changed` is the probe rather than a frame poll, because the question is about an
# INSTANT: a poll answers "some frame near it", and the walk resumes a frame or two after the shot.
#
# Fixture is tests/ui/test_watch_note_reaches_the_panel.gd's -- see tests/README.md -> Testing the
# game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

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
	for x in range(8):
		for y in range(5):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i, power := 4, mhp := 80) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: mhp}, faction), cell)
	assert_object(unit).override_failure_message("fixture failed to spawn at %s" % str(cell)).is_not_null()
	unit.equipped_weapon = H.make_weapon(power)
	return unit


# A watch over a single cell: no pattern means the footprint is the aimed cell alone (Reach's
# fallback), which keeps every case's geometry out of the question.
func _arm(watcher: Unit, cell: Vector2i) -> void:
	var footprint: Array[Vector2i] = [cell]
	watcher.arm_watch(watcher.movement.cell, cell, footprint, watcher.get_default_attack())
	assert_object(watcher.watch).override_failure_message("fixture failed to arm the watch").is_not_null()


# A straight walk east along the unit's own row, ending at x = `to_x`.
func _queue_walk(unit: Unit, to_x: int) -> MoveAction:
	var path: Array[Vector2i] = []
	for x in range(unit.movement.cell.x, to_x + 1):
		path.append(Vector2i(x, unit.movement.cell.y))
	var move := MoveAction.new()
	move.init(unit, path, null)
	assert_bool(game.squad_manager.queue_action(unit.squad, move)) \
		.override_failure_message("fixture failed to queue the walk").is_true()
	return move


# Where `witness` was standing each time `subject` took a hit, in the order the hits landed. The
# whole suite reduces to this list.
func _record_hits(subject: Unit, witness: Unit, into: Array[Vector2i]) -> void:
	subject.unit_instance.hp_changed.connect(
			func(_current: Variant, _max: Variant) -> void: into.append(witness.movement.cell))


# THE case. The shot fires at the crossing MOMENT, so the crosser is standing on the crossing cell
# when it lands -- not at the far end of a walk it has already finished. Deliberately a shot the
# crosser WALKS AWAY FROM: a halting shot would leave it on the crossing cell either way, and the
# assertion would pass against the bug.
func test_the_shot_lands_while_the_crosser_is_still_on_the_crossing_cell() -> void:
	var watcher := _spawn(ENEMY, Vector2i(3, 3))
	var crosser := _spawn(PLAYER, Vector2i(0, 0))
	await await_idle_frame()
	_arm(watcher, Vector2i(3, 0))
	_queue_walk(crosser, 5)

	var struck_at: Array[Vector2i] = []
	_record_hits(crosser, crosser, struck_at)

	await game.order_executor.execute_orders(crosser.squad.get_leader())

	assert_int(struck_at.size()).override_failure_message(
			"the walk took no shot at all -- the fixture is not exercising the rule").is_equal(1)
	if struck_at.size() == 1:
		assert_vector(struck_at[0]).override_failure_message(
				"the shot played after the walk instead of interrupting it").is_equal(Vector2i(3, 0))
	# ...and the walk RESUMED, which is what makes the assertion above a real one: a crosser parked
	# on the crossing cell forever would satisfy it too.
	assert_vector(crosser.movement.cell).override_failure_message(
			"the crosser never finished its walk after the interrupt").is_equal(Vector2i(5, 0))


# The shots play in the order the RESOLVE fired them -- which is queue order -- even when the later
# crosser reaches its own crossing cell first. #412's whole payoff is that dragging a move row
# changes who eats the shot, and a playback sorted by wall clock would show the opposite.
#
# The far crosser is queued FIRST and has four cells to walk; the near one is queued second and
# crosses on its first step.
func test_the_shots_play_in_queue_order_not_in_arrival_order() -> void:
	var far_watcher := _spawn(ENEMY, Vector2i(4, 3))
	var near_watcher := _spawn(ENEMY, Vector2i(1, 4))
	var far_crosser := _spawn(PLAYER, Vector2i(0, 0))
	var near_crosser := _spawn(PLAYER, Vector2i(0, 1))
	await await_idle_frame()
	game.squad_manager.join_squad(near_crosser, far_crosser.squad)
	_arm(far_watcher, Vector2i(4, 0))
	_arm(near_watcher, Vector2i(1, 1))
	_queue_walk(far_crosser, 5)
	_queue_walk(near_crosser, 5)

	var order: Array[Vector2i] = []
	_record_hits(far_crosser, far_crosser, order)
	_record_hits(near_crosser, near_crosser, order)

	await game.order_executor.execute_orders(far_crosser.squad.get_leader())

	# One entry per crosser, each recorded at its own crossing cell -- so the list is both the
	# ORDER the shots played and the proof each played mid-walk.
	assert_array(order).override_failure_message(
			"the near crosser's shot played first: the playback sorted by who arrived, not by the "
			+ "queue order the player set") \
		.is_equal([Vector2i(4, 0), Vector2i(1, 1)])


# The other half of the same rule (#567): a shot a SHOVE set off plays after the volley that threw
# somebody into it. It used to play in one batch ahead of every attack, so the answering shot came
# before the mace -- read here as the victim being hit on the cell it was shoved FROM twice over.
func test_a_shove_triggered_shot_plays_after_the_blow_that_caused_it() -> void:
	var shover := _spawn(PLAYER, Vector2i(0, 0), 6)
	var victim := _spawn(ENEMY, Vector2i(1, 0))
	var watcher := _spawn(PLAYER, Vector2i(2, 3))
	await await_idle_frame()
	(shover.get_equipped_weapon() as WeaponInstance).template.main_attack.knockback = 1
	_arm(watcher, Vector2i(2, 0))
	assert_bool(game.squad_manager.queue_action(shover.squad, H.stamped_attack(shover, victim))) \
		.override_failure_message("fixture failed to queue the attack").is_true()

	# Where the VICTIM stood for each hit it took. take_damage runs before the slide, so the blow is
	# recorded on the cell it was struck on and the answering shot on the cell it landed on.
	var struck_at: Array[Vector2i] = []
	_record_hits(victim, victim, struck_at)

	await game.order_executor.execute_orders(shover.squad.get_leader())

	assert_array(struck_at).override_failure_message(
			"the triggered shot played before the shove that set it off") \
		.is_equal([Vector2i(1, 0), Vector2i(2, 0)])
