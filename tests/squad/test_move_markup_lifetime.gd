# A move's markup lifetime (#558): the path ARROW and the destination GHOST come down when THAT
# unit arrives, not when its squad's pass ends.
#
# The bug the dev reported: nothing pulled a ghost until _end_squad_turn, so a unit that finished
# walking spent the rest of its squad's pass -- every other member's walk, every attack, every
# side-channel hold -- standing underneath a translucent copy of itself.
#
# The arrow was NOT the same bug and had to be ruled on rather than assumed (dev, 2026-08-26: "let's
# have the arrow match the ghost's lifecycle"). MoveAction.execute used to free its own preview
# sprites at the FIRST STEP, so the trail vanished exactly when it was most useful -- and only by
# luck, since redraw_planned_paths rebuilds every arrow from planned_move_by_unit, which still named
# the walking unit. Both now end at one moment, through OverlayManager.clear_move_markup.
#
# Needs the real game scene: the ghosts are real Sprite2D children of OverlayManager and the arrows
# are a MoveAction's own preview sprites, so the bare SquadManager fixture has no markup to watch.
# Fixture is tests/ai/test_ai_turn_terminates.gd's -- the instanced root MUST be named "Main".
#
# The mid-pass window these cases need EXISTS headless because movement is a real tween:
# MovementComponent walks one cell at a time on create_tween, so a three-step move genuinely
# outlives a one-step move and the phase genuinely spans frames. (Contrast Pacing.beat, which is a
# no-op headless -- nothing here may lean on a hold.)
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true, move_cost=1 in TestTiles.tres

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
		for y in range(3):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


# ------------------------------------------------------------------------------
#  Fixtures
# ------------------------------------------------------------------------------

func _spawn(cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), cell)
	assert_object(unit).override_failure_message(
			"fixture: nothing spawned at %s -- off-map or unwalkable" % cell).is_not_null()
	return unit


# Ordered the way a player orders one, so the markup is DRAWN by the code that draws it in play
# (_click_choosing_move queues and then shows both markers). Queueing alone draws nothing, and a
# case that hand-drew the markup would be asserting against its own setup.
func _order_move(unit: Unit, cell: Vector2i) -> MoveAction:
	game.enter_move_mode(unit)
	game.selected_unit = unit
	game._on_left_click(cell)
	var drawn: Dictionary = game.overlay_manager.planned_move_by_unit
	assert_bool(drawn.has(unit)).override_failure_message(
			"fixture: the order drew no path at all, so there is no markup to watch").is_true()
	return drawn[unit]


# One squad, two members, DIFFERENT path lengths -- which is the whole fixture. The phase ends with
# the SLOWER walker, so per-unit and per-phase clearing are indistinguishable unless one member is
# still going when the other lands.
func _two_walkers() -> Dictionary:
	var quick := _spawn(Vector2i(0, 0))
	var slow := _spawn(Vector2i(0, 2))
	game.squad_manager.join_squad(slow, quick.squad)
	await await_idle_frame()
	var quick_move := _order_move(quick, Vector2i(1, 0))
	var slow_move := _order_move(slow, Vector2i(3, 2))
	assert_int(quick.squad.action_queue.size()).override_failure_message(
			"fixture: both moves must be queued, or there is no pass to watch").is_equal(2)
	return {"quick": quick, "slow": slow, "quick_move": quick_move, "slow_move": slow_move}


# What is on screen for this unit right now. The ARROW is counted off the MoveAction captured at
# ORDER time, never looked up through planned_move_by_unit: a clear that erased the store and left
# the sprites standing would read as zero arrows through the store while leaking a trail on screen
# that nothing can ever free again.
func _markup(unit: Unit, move: MoveAction) -> Dictionary:
	var om: OverlayManager = game.overlay_manager
	return {
		"arrows": move.preview.size(),
		"ghost": om.projected_unit_sprites.has(unit),
	}


# Frames until this unit's walk is done, plus the ones the executor's poll needs to observe the flip.
func _walk_out(unit: Unit) -> void:
	while unit.movement.moving:
		await await_idle_frame()
	await await_idle_frame()
	await await_idle_frame()


# Let the pass reach its own end rather than tearing the scene down mid-coroutine.
func _finish_pass() -> void:
	while game.order_executor.executing_plan != null:
		await await_idle_frame()
	await await_idle_frame()


# ------------------------------------------------------------------------------
#  A move's markup ends with the move
# ------------------------------------------------------------------------------

func test_a_units_markup_comes_down_when_it_arrives_not_when_the_pass_ends() -> void:
	var board := await _two_walkers()
	var quick: Unit = board["quick"]
	var slow: Unit = board["slow"]

	# Started, NOT awaited: the claim is about a moment INSIDE the pass.
	game.order_executor.execute_orders(quick)
	await _walk_out(quick)

	assert_bool(slow.movement.moving).override_failure_message(
			"fixture: the slow walker finished too -- there is no mid-pass moment to assert about") \
		.is_true()
	var arrived := _markup(quick, board["quick_move"])
	assert_bool(arrived["ghost"]).override_failure_message(
			"the arrived unit is still standing under its own ghost").is_false()
	assert_int(arrived["arrows"]).override_failure_message(
			"the arrived unit's path arrow is still drawn").is_equal(0)

	await _finish_pass()


# ...and the other half: a unit that is WALKING keeps both. This is the dev's arrow ruling and it is
# a real change -- MoveAction.execute used to free the arrow at the first step.
#
# ASSERTED WITH NO FRAME AWAITED, and that is the whole case rather than an optimisation. A first
# draft waited for the quick walker to arrive and PASSED against the mutant that restores the old
# first-step clear: clear_move_markup's own redraw_planned_paths rebuilds every OTHER unit's arrow
# from planned_move_by_unit, so the arrival republishes the very sprites the mutant had freed. The
# moves start synchronously (execute() runs to the poll's first process_frame await), so this is the
# one moment in the pass with no publisher standing between the bug and the assertion.
func test_a_unit_still_walking_keeps_its_arrow_and_its_ghost() -> void:
	var board := await _two_walkers()
	var quick: Unit = board["quick"]
	var slow: Unit = board["slow"]

	game.order_executor.execute_orders(quick)

	assert_bool(slow.movement.moving).override_failure_message(
			"fixture: no walk had started, so there is nothing mid-walk to assert about").is_true()
	var walking := _markup(slow, board["slow_move"])
	assert_bool(walking["ghost"]).override_failure_message(
			"a unit that has not arrived lost its destination ghost").is_true()
	assert_int(walking["arrows"]).override_failure_message(
			"the walking unit's path arrow was pulled the moment it set off").is_greater(0)

	await _finish_pass()


# The DURABLE half, and the one that owns the store claim. planned_move_by_unit is what both
# redraw_* rebuild from, so a clear that frees sprites and leaves the store is undone by the next
# redraw -- and a redraw during a pass is not hypothetical, it is one line of #520 choreography away.
#
# Asserted through a redraw rather than by reading the store, deliberately: the case above used to
# check planned_move_by_unit directly, which made THIS case unfalsifiable -- every store-shaped
# mutant reddened there first and truncated the file before reaching it. Two cases, two mutants, two
# messages: leaked SPRITES red above, a leaked STORE reds here.
func test_a_redraw_during_the_pass_cannot_bring_a_retired_markup_back() -> void:
	var board := await _two_walkers()
	var quick: Unit = board["quick"]

	game.order_executor.execute_orders(quick)
	await _walk_out(quick)

	game.overlay_manager.redraw_planned_paths()
	game.overlay_manager.redraw_projected_units()
	await await_idle_frame()

	var after := _markup(quick, board["quick_move"])
	assert_bool(after["ghost"]).override_failure_message(
			"a redraw rebuilt the ghost of a move that had already been carried out").is_false()
	assert_int(after["arrows"]).override_failure_message(
			"a redraw rebuilt the arrow of a move that had already been carried out").is_equal(0)

	await _finish_pass()


# Cancelling is the OTHER door into the same moment, and it has to stay one call -- two markers whose
# clears are written separately is exactly how the ghost and the arrow drifted apart to begin with.
func test_cancelling_a_move_takes_both_markers_with_it() -> void:
	var mover := _spawn(Vector2i(0, 0))
	await await_idle_frame()
	var move := _order_move(mover, Vector2i(2, 0))
	var queued := _markup(mover, move)
	assert_bool(queued["ghost"]).override_failure_message(
			"fixture: queueing drew no ghost, so there is nothing to cancel").is_true()
	assert_int(queued["arrows"]).override_failure_message(
			"fixture: queueing drew no arrow").is_greater(0)

	for action in mover.squad.action_queue.duplicate():
		game.squad_manager.remove_action(mover.squad, action)
	await await_idle_frame()

	var cancelled := _markup(mover, move)
	assert_bool(cancelled["ghost"]).override_failure_message(
			"a cancelled move left its ghost standing").is_false()
	assert_int(cancelled["arrows"]).override_failure_message(
			"a cancelled move left its arrow drawn").is_equal(0)
