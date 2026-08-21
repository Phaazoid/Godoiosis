# Group Move must vanish from the menu the moment the leader locks a main action (#443), exactly
# as Move already did. The dev found it the way a player would: queue an Attack, reopen the menu,
# Group Move is still listed -- and taking it walked the squad off and left the leader behind,
# because only the LEADER's move is refused one layer down (move-before-main) and the rest queue.
#
# The two rows are one question, so this suite asserts them TOGETHER: they shared a gate's worth of
# clauses by hand-copy, which is how Group Move's copy came to be missing one. A test that watched
# only Group Move would pass a future fix that broke Move instead.
#
# Real game scene (the #114 fixture -- root MUST be named "Main"), because populate() reads game.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

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
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


# A leader with one squadmate: has_squad() is what separates a real squad from the solo squad
# every unit is born into, and Group Move is only offered to the former.
func _spawn_squad() -> Unit:
	var leader: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 8}, Team.Faction.PLAYER), Vector2i(0, 0))
	var member: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(1, 0))
	game.squad_manager.join_squad(member, leader.squad)
	game.turn_manager.set_active_faction(Team.Faction.PLAYER)
	return leader


# Rally is the cheapest real main action to author: it only needs Will to restore.
func _lock_a_main_action(unit: Unit) -> void:
	unit.unit_instance.set_current_will(1)
	var rally := RallyAction.new()
	rally.init(unit)
	assert_bool(game.squad_manager.queue_action(unit.squad, rally)).is_true()


func test_both_movement_rows_are_offered_before_the_main_action() -> void:
	# Positive control: without it, a gate that refuses everything would pass the real test.
	var leader := _spawn_squad()

	var options: Array = game.main_action_menu.populate(leader)

	assert_array(options).contains([MainActionMenu.MOVE, MainActionMenu.GROUP_MOVE])


func test_group_move_is_withdrawn_once_a_main_action_is_queued() -> void:
	var leader := _spawn_squad()
	_lock_a_main_action(leader)

	var options: Array = game.main_action_menu.populate(leader)

	assert_bool(options.has(MainActionMenu.GROUP_MOVE)) \
		.override_failure_message("Group Move was still offered to a leader holding a main action") \
		.is_false()


func test_move_is_withdrawn_alongside_it() -> void:
	# The row Group Move's gate was copied from. Both must go, and go for the same reason.
	var leader := _spawn_squad()
	_lock_a_main_action(leader)

	var options: Array = game.main_action_menu.populate(leader)

	assert_bool(options.has(MainActionMenu.MOVE)) \
		.override_failure_message("Move survived a queued main action") \
		.is_false()


func test_a_squadmate_without_a_main_action_still_gets_move() -> void:
	# The gate is per-UNIT, not per-squad: the leader spending its main must not freeze the
	# squadmates who haven't. Only the leader is offered Group Move either way.
	var leader := _spawn_squad()
	_lock_a_main_action(leader)
	var member: Unit = leader.squad.get_members()[1]

	var options: Array = game.main_action_menu.populate(member)

	assert_array(options).contains([MainActionMenu.MOVE])
	assert_bool(options.has(MainActionMenu.GROUP_MOVE)).is_false()
