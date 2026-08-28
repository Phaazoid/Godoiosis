# Does the watch annotation reach the PANEL? (#592)
#
# tests/squad/test_watch_queue_annotation.gd proves the data layer: build_for hands back an entry
# carrying the note. This suite exists because that is exactly the shape that has shipped broken
# here before -- #103, #126, #131 -- both ends correct and nothing joining them. So it drives the
# real game scene, queues a move the way the player does, calls the real refresh, and reads the text
# on the ROW the player actually looks at.
#
# Fixture is tests/ui/test_target_pick_projection.gd's -- see tests/README.md -> Testing the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

# The crosser walks east along row 0; the watcher sits off the row and watches two of its cells.
const WATCHED: Array[Vector2i] = [Vector2i(3, 0), Vector2i(4, 0)]
const WATCHER_CELL := Vector2i(3, 2)
const CROSSER_CELL := Vector2i(0, 0)

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
		for y in range(4):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()
	unit.equipped_weapon = H.make_weapon(6)
	return unit


# Every Label the panel is actually SHOWING, by its text. Visibility walked up the whole ancestor
# chain, not read off the one node: #592 was a note written into a Label that has been
# `visible = false` since the panel's first version, so an assertion on `.text` alone was blind to
# the entire bug -- and both of this suite's cases passed against it before that was understood.
func _row_texts() -> Array[String]:
	var out: Array[String] = []
	_collect_visible_text(game.squad_action_queue_control, out)
	return out


func _collect_visible_text(node: Node, out: Array[String]) -> void:
	if node is Label and (node as Label).is_visible_in_tree():
		out.append((node as Label).text)
	for child in node.get_children():
		_collect_visible_text(child, out)


# THE case. A player walk that crosses an armed enemy watch, planned the way the player plans it,
# and the question is whether the row on screen says so.
func test_the_crossing_move_row_says_what_it_walks_into() -> void:
	var watcher := _spawn(Team.Faction.ENEMY, WATCHER_CELL)
	var crosser := _spawn(Team.Faction.PLAYER, CROSSER_CELL)
	await await_idle_frame()

	var footprint: Array[Vector2i] = WATCHED.duplicate()
	watcher.arm_watch(WATCHER_CELL, WATCHED[0], footprint, watcher.get_default_attack())
	assert_object(watcher.watch).override_failure_message("fixture failed to arm the watch").is_not_null()

	var path: Array[Vector2i] = []
	for x in range(0, 6):
		path.append(Vector2i(x, 0))
	var move := MoveAction.new()
	move.init(crosser, path, null)
	assert_bool(game.squad_manager.queue_action(crosser.squad, move)) \
		.override_failure_message("fixture failed to queue the walk").is_true()

	game.refresh_action_queue(crosser.squad)   # the real path: resolve -> build -> render
	await await_idle_frame()

	# The resolve really did fire the watch -- otherwise this suite is testing nothing.
	var plan: ResolvedPlan = game.squad_manager.resolved_plan_for(crosser.squad)
	assert_object(plan).override_failure_message("no plan was stored for the squad").is_not_null()
	assert_int(plan.watch_shots.size()).override_failure_message(
			"the walk crossed no watch -- the fixture is not exercising the rule").is_greater(0)

	var texts := _row_texts()
	assert_array(texts).override_failure_message("the panel drew no rows at all").is_not_empty()

	var said := false
	for text: String in texts:
		if text.contains("watch"):
			said = true
	assert_bool(said).override_failure_message(
			"nothing VISIBLE on the panel mentions the watch -- the note exists in the entries but the
"
			+ "player cannot see it (#592). Visible text: %s" % str(texts)).is_true()


# The same question with the watch armed the way the GAME arms it -- declared, queued, executed --
# and a turn handoff in between, which is the sequence a hotseat player actually performs. The case
# above reaches its precondition by calling arm_watch directly, and CLAUDE.md names that as the
# shape a test can be blind in: an arming path that never ran is an arming path never tested.
func test_the_note_appears_when_the_watch_was_armed_through_the_real_path() -> void:
	var watcher := _spawn(Team.Faction.ENEMY, WATCHER_CELL)
	var crosser := _spawn(Team.Faction.PLAYER, CROSSER_CELL)
	await await_idle_frame()

	# A watch-only attack with no pattern: its footprint is the aimed cell alone (Reach's fallback),
	# which is all this needs and keeps the geometry out of the question.
	var watch_attack := WeaponAttackData.new()
	watch_attack.display_name = "Overwatch"
	watch_attack.can_overwatch = true
	var weapon := watcher.get_equipped_weapon() as WeaponInstance
	weapon.template.extra_attacks = [watch_attack]
	watcher.active_attack = watch_attack

	game.queue_overwatch(watcher, WATCHED[0])
	await game.order_executor.execute_orders(watcher)
	assert_object(watcher.watch).override_failure_message(
			"the real declare->execute path armed no watch").is_not_null()

	# The player's turn begins. The enemy's watch must survive this (it lapses on the OWNER's turn).
	game._run_turn_start_ticks(Team.Faction.PLAYER)
	assert_object(watcher.watch).override_failure_message(
			"the watch lapsed on the wrong faction's turn start").is_not_null()

	var path: Array[Vector2i] = []
	for x in range(0, 6):
		path.append(Vector2i(x, 0))
	var move := MoveAction.new()
	move.init(crosser, path, null)
	assert_bool(game.squad_manager.queue_action(crosser.squad, move)) \
		.override_failure_message("fixture failed to queue the walk").is_true()

	game.refresh_action_queue(crosser.squad)
	await await_idle_frame()

	var plan: ResolvedPlan = game.squad_manager.resolved_plan_for(crosser.squad)
	assert_int(plan.watch_shots.size()).override_failure_message(
			"the walk crossed no watch -- the fixture is not exercising the rule").is_greater(0)

	var texts := _row_texts()
	var said := false
	for text: String in texts:
		if text.contains("watch"):
			said = true
	assert_bool(said).override_failure_message(
			"nothing VISIBLE on the panel mentions the watch -- the note exists in the entries but the
"
			+ "player cannot see it (#592). Visible text: %s" % str(texts)).is_true()
