# MissionController — the LATCHES, the objective composer, the capture state and the ending (#96).
#
# The pure predicate is pinned next door in test_mission_rules.gd, and the zone geometry in
# tests/ai/test_zone_manager.gd. What was never covered is everything a pure function structurally
# cannot hold, which is exactly the half where the load-bearing doctrine lives:
#
#   * the ended-latch and the _ending re-entrancy guard
#   * the `contested` latch — "both sides were up at once", remembered because the board forgets
#   * captured-zone state (whole-zone claim, battle-scoped)
#   * the objective composer (AND across every declared objective)
#   * unpainted geometry reading PENDING, not NONE — a broken map must stay unwinnable
#   * extraction counting the DOWNED
#
# It needs a real game scene, which was believed to segfault in the runner until #114 showed it
# does not. Fixture is the one from tests/ui/test_game_scene_smoke.gd — the instanced root MUST be
# named "Main" under /root, or game.gd's absolute /root/Main/DevOverlay lookup returns null and
# ScenarioManager.clear_board() dies on it. See tests/README.md → Testing the game scene.
#
# Every board here is built cell by cell rather than loaded, so each test states its own situation.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

var _main: Node
var game: Node2D
var mc: MissionController


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	# An empty board, not the sandbox: clear_board() also routes through mission_controller.reset(),
	# which is the real mission-start path.
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	mc = game.mission_controller
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


# A unit of `faction` standing on `cell`. Goes through game.spawn_unit so it lands in the real
# board context, with a real squad, exactly as a scenario load would leave it.
func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()   # off-map or unwalkable cell — the test's own setup is wrong
	return unit


func _paint(zone_name: String, kind: ZoneManager.Kind, cells: Array) -> void:
	for cell: Vector2i in cells:
		game.zone_manager.paint_cell(zone_name, kind, cell)


func _objectives(list: Array) -> void:
	var typed: Array[MissionRules.Objective] = []
	typed.assign(list)
	mc.set_objectives(typed)


# ==============================================================================
#  reset() — mission START clears battle-scoped state
# ==============================================================================

func test_reset_clears_every_battle_scoped_field() -> void:
	_paint("Point", ZoneManager.Kind.CAPTURE, [Vector2i(1, 1)])
	_objectives([MissionRules.Objective.CAPTURE])
	mc.capture("Point")
	mc.outcome = MissionRules.Outcome.VICTORY
	assert_bool(mc.is_over()).is_true()

	mc.reset()

	assert_that(mc.outcome).is_equal(MissionRules.Outcome.ONGOING)
	assert_bool(mc.is_over()).is_false()
	assert_bool(mc.is_zone_captured("Point")).is_false()
	assert_array(mc.objectives).is_empty()


func test_clear_board_resets_the_controller() -> void:
	# The one real caller of reset() today — the #87 seam. A mission START resets; only a
	# mid-battle save restore should ever put battle state back.
	mc.outcome = MissionRules.Outcome.DEFEAT
	game.scenario_manager.clear_board()
	assert_bool(mc.is_over()).is_false()


# ==============================================================================
#  The two latches
# ==============================================================================

func test_check_is_latched_once_the_mission_is_over() -> void:
	# The ended-latch: once a mission has ended, a later check() must not re-decide it. Win first,
	# then make the board read as a DEFEAT — a won mission must stay won.
	var player := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var enemy := _spawn(Team.Faction.ENEMY, Vector2i(4, 4))
	mc.check()
	enemy.die()
	mc.check()
	assert_that(mc.outcome).is_equal(MissionRules.Outcome.VICTORY)

	player.die()
	mc.check()
	assert_that(mc.outcome).is_equal(MissionRules.Outcome.VICTORY)


func test_is_over_latches_check_on_its_own_once_the_banner_is_gone() -> void:
	# check()'s guard is `is_over() or _ending`, and the halves cover different moments: _ending
	# holds only while the banner is up, so the test above cannot tell them apart. Once the
	# player dismisses the banner _ending drops and is_over() has to bail by itself. That state
	# is set directly here because a banner cannot be dismissed headlessly.
	var player := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	_spawn(Team.Faction.ENEMY, Vector2i(4, 4))
	mc.check()                                   # latches contested while both stand
	mc.outcome = MissionRules.Outcome.VICTORY    # ... as if the banner had been shown and dismissed
	player.die()                                 # the board now reads as a DEFEAT

	mc.check()
	assert_that(mc.outcome).is_equal(MissionRules.Outcome.VICTORY)


func test_contested_latches_and_is_not_re_read_live() -> void:
	# THE reason the latch exists. Once both sides have been up, wiping one side must still end
	# the mission — a live is_contested() read would go false at that exact moment and no mission
	# could ever end.
	var player := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var enemy := _spawn(Team.Faction.ENEMY, Vector2i(3, 3))
	mc.check()   # latches contested while both stand
	assert_that(mc.outcome).is_equal(MissionRules.Outcome.ONGOING)

	enemy.die()
	mc.check()
	assert_that(mc.outcome).is_equal(MissionRules.Outcome.VICTORY)
	assert_object(player).is_not_null()


func test_an_enemies_only_board_never_ends_because_it_was_never_contested() -> void:
	# A dev scratchpad is not a mission: spawning only enemies satisfies "the player has no active
	# units" perfectly. This is what keeps sandbox boards inert with no dev_mode flag.
	_spawn(Team.Faction.ENEMY, Vector2i(2, 2))
	mc.check()
	assert_that(mc.outcome).is_equal(MissionRules.Outcome.ONGOING)
	assert_bool(mc.is_over()).is_false()


func test_a_player_only_board_never_ends_either() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(2, 2))
	mc.check()
	assert_that(mc.outcome).is_equal(MissionRules.Outcome.ONGOING)


# ==============================================================================
#  The objective composer
# ==============================================================================

func test_no_declared_objectives_is_progress_none() -> void:
	assert_that(mc.objective_progress(game._board())).is_equal(MissionRules.Progress.NONE)


func test_objectives_compose_by_and() -> void:
	# ROUT is met (no hostiles on the board) but CAPTURE is not, so the whole thing is PENDING.
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	_paint("Point", ZoneManager.Kind.CAPTURE, [Vector2i(5, 5)])
	_objectives([MissionRules.Objective.ROUT, MissionRules.Objective.CAPTURE])
	assert_that(mc.objective_progress(game._board())).is_equal(MissionRules.Progress.PENDING)

	mc.capture("Point")
	assert_that(mc.objective_progress(game._board())).is_equal(MissionRules.Progress.MET)


func test_routing_a_capture_map_wins_nothing() -> void:
	# Doctrine: an authored objective is the ONLY way to win. Killing everything on a map that
	# asks for a capture point is not a consolation victory — lockout is a level-design problem.
	var player := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var enemy := _spawn(Team.Faction.ENEMY, Vector2i(4, 4))
	_paint("Point", ZoneManager.Kind.CAPTURE, [Vector2i(6, 6)])
	_objectives([MissionRules.Objective.CAPTURE])
	mc.check()

	enemy.die()
	mc.check()
	assert_that(mc.outcome).is_equal(MissionRules.Outcome.ONGOING)
	assert_bool(player.is_active()).is_true()


func test_defeat_beats_a_completed_objective_in_the_same_pass() -> void:
	# Doctrine: DEFEAT is checked first. Losing your last unit on the turn you take the point
	# is a loss, not a win.
	var player := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	_spawn(Team.Faction.ENEMY, Vector2i(4, 4))
	_paint("Point", ZoneManager.Kind.CAPTURE, [Vector2i(6, 6)])
	_objectives([MissionRules.Objective.CAPTURE])
	mc.check()

	mc.capture("Point")
	player.die()
	mc.check()
	assert_that(mc.outcome).is_equal(MissionRules.Outcome.DEFEAT)


# ==============================================================================
#  Capture state
# ==============================================================================

func test_capture_claims_the_whole_zone_from_any_cell() -> void:
	_paint("Point", ZoneManager.Kind.CAPTURE, [Vector2i(2, 2), Vector2i(2, 3), Vector2i(3, 2)])
	_objectives([MissionRules.Objective.CAPTURE])
	assert_that(mc.objective_progress(game._board())).is_equal(MissionRules.Progress.PENDING)

	mc.capture("Point")   # a multi-tile objective is ONE objective, not N of them

	assert_bool(mc.is_zone_captured("Point")).is_true()
	assert_that(mc.objective_progress(game._board())).is_equal(MissionRules.Progress.MET)


func test_capturing_twice_does_not_double_register() -> void:
	_paint("Point", ZoneManager.Kind.CAPTURE, [Vector2i(2, 2)])
	mc.capture("Point")
	mc.capture("Point")
	assert_int(mc._captured_zones.size()).is_equal(1)


func test_a_non_capture_zone_cannot_be_captured() -> void:
	# A patrol zone is Sentry geometry, not an objective. Capturing it would silently rewrite
	# the win condition — the same failure the explicit-objectives design exists to prevent.
	_paint("Patrol", ZoneManager.Kind.PATROL, [Vector2i(2, 2)])
	mc.capture("Patrol")
	assert_bool(mc.is_zone_captured("Patrol")).is_false()


func test_capturing_an_unknown_or_empty_zone_is_a_no_op() -> void:
	mc.capture("")
	mc.capture("NoSuchZone")
	assert_array(mc._captured_zones).is_empty()


func test_is_capture_zone_at_distinguishes_kind() -> void:
	_paint("Point", ZoneManager.Kind.CAPTURE, [Vector2i(2, 2)])
	_paint("Patrol", ZoneManager.Kind.PATROL, [Vector2i(7, 7)])
	assert_bool(mc.is_capture_zone_at(Vector2i(2, 2))).is_true()
	assert_bool(mc.is_capture_zone_at(Vector2i(7, 7))).is_false()
	assert_bool(mc.is_capture_zone_at(Vector2i(9, 9))).is_false()


func test_all_capture_zones_must_be_taken() -> void:
	_paint("North", ZoneManager.Kind.CAPTURE, [Vector2i(2, 2)])
	_paint("South", ZoneManager.Kind.CAPTURE, [Vector2i(6, 6)])
	_objectives([MissionRules.Objective.CAPTURE])

	mc.capture("North")
	assert_that(mc.objective_progress(game._board())).is_equal(MissionRules.Progress.PENDING)
	mc.capture("South")
	assert_that(mc.objective_progress(game._board())).is_equal(MissionRules.Progress.MET)


# ==============================================================================
#  Extraction
# ==============================================================================

func test_extraction_needs_every_survivor_inside() -> void:
	_paint("Exit", ZoneManager.Kind.EXTRACTION, [Vector2i(1, 1), Vector2i(1, 2)])
	_objectives([MissionRules.Objective.EXTRACT])
	var inside := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var outside := _spawn(Team.Faction.PLAYER, Vector2i(5, 5))
	assert_that(mc.objective_progress(game._board())).is_equal(MissionRules.Progress.PENDING)

	outside.movement.cell = Vector2i(1, 2)
	assert_that(mc.objective_progress(game._board())).is_equal(MissionRules.Progress.MET)
	assert_bool(inside.is_active()).is_true()


func test_a_downed_unit_inside_the_zone_counts_as_extracted() -> void:
	# Doctrine: "surviving" is not-DEAD. Alive and in the zone means they got out.
	_paint("Exit", ZoneManager.Kind.EXTRACTION, [Vector2i(1, 1), Vector2i(1, 2)])
	_objectives([MissionRules.Objective.EXTRACT])
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var downed := _spawn(Team.Faction.PLAYER, Vector2i(1, 2))
	downed.lifecycle_state = Unit.LifecycleState.DOWNED   # state only, as test_mission_rules does
	assert_bool(downed.is_downed()).is_true()

	assert_that(mc.objective_progress(game._board())).is_equal(MissionRules.Progress.MET)


func test_a_downed_unit_outside_the_zone_blocks_extraction() -> void:
	# ... and cannot walk in on its own — this is the rescue-under-pressure mission.
	_paint("Exit", ZoneManager.Kind.EXTRACTION, [Vector2i(1, 1)])
	_objectives([MissionRules.Objective.EXTRACT])
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var stranded := _spawn(Team.Faction.PLAYER, Vector2i(6, 6))
	stranded.lifecycle_state = Unit.LifecycleState.DOWNED

	assert_that(mc.objective_progress(game._board())).is_equal(MissionRules.Progress.PENDING)


func test_a_dead_unit_outside_the_zone_does_not_block_extraction() -> void:
	_paint("Exit", ZoneManager.Kind.EXTRACTION, [Vector2i(1, 1)])
	_objectives([MissionRules.Objective.EXTRACT])
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var lost := _spawn(Team.Faction.PLAYER, Vector2i(6, 6))
	lost.die()

	assert_that(mc.objective_progress(game._board())).is_equal(MissionRules.Progress.MET)


func test_enemies_outside_the_extraction_zone_are_irrelevant() -> void:
	_paint("Exit", ZoneManager.Kind.EXTRACTION, [Vector2i(1, 1)])
	_objectives([MissionRules.Objective.EXTRACT])
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	_spawn(Team.Faction.ENEMY, Vector2i(6, 6))

	assert_that(mc.objective_progress(game._board())).is_equal(MissionRules.Progress.MET)


func test_several_extraction_zones_are_alternatives_not_a_split() -> void:
	_paint("North", ZoneManager.Kind.EXTRACTION, [Vector2i(1, 1)])
	_paint("South", ZoneManager.Kind.EXTRACTION, [Vector2i(6, 6)])
	_objectives([MissionRules.Objective.EXTRACT])
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	_spawn(Team.Faction.PLAYER, Vector2i(6, 6))

	assert_that(mc.objective_progress(game._board())).is_equal(MissionRules.Progress.MET)


# ==============================================================================
#  Declared-but-unpainted: the guard on the second source of truth
# ==============================================================================

func test_a_declared_objective_with_no_painted_zone_reads_pending_not_met() -> void:
	# The whole point of the guard: the map really IS unwinnable, and silently dropping the
	# objective would quietly convert a broken map into a different, playable one.
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	mc.objectives.assign([MissionRules.Objective.CAPTURE] as Array[MissionRules.Objective])
	assert_that(mc.objective_progress(game._board())).is_equal(MissionRules.Progress.PENDING)

	mc.objectives.assign([MissionRules.Objective.EXTRACT] as Array[MissionRules.Objective])
	assert_that(mc.objective_progress(game._board())).is_equal(MissionRules.Progress.PENDING)


func test_an_unwinnable_map_cannot_be_won_by_routing() -> void:
	var player := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var enemy := _spawn(Team.Faction.ENEMY, Vector2i(4, 4))
	mc.objectives.assign([MissionRules.Objective.CAPTURE] as Array[MissionRules.Objective])   # no zone painted
	mc.check()

	enemy.die()
	mc.check()
	assert_that(mc.outcome).is_equal(MissionRules.Outcome.ONGOING)
	assert_bool(player.is_active()).is_true()


func test_objectives_missing_geometry_names_each_unpainted_objective() -> void:
	mc.objectives.assign([MissionRules.Objective.ROUT, MissionRules.Objective.CAPTURE, MissionRules.Objective.EXTRACT] as Array[MissionRules.Objective])
	var missing := mc.objectives_missing_geometry()
	# ROUT has no geometry to paint, so it can never appear here.
	assert_array(missing).contains_exactly([MissionRules.Objective.CAPTURE, MissionRules.Objective.EXTRACT])

	_paint("Point", ZoneManager.Kind.CAPTURE, [Vector2i(2, 2)])
	assert_array(mc.objectives_missing_geometry()).contains_exactly([MissionRules.Objective.EXTRACT])


func test_a_painted_map_reports_no_missing_geometry() -> void:
	_paint("Point", ZoneManager.Kind.CAPTURE, [Vector2i(2, 2)])
	_paint("Exit", ZoneManager.Kind.EXTRACTION, [Vector2i(8, 8)])
	_objectives([MissionRules.Objective.CAPTURE, MissionRules.Objective.EXTRACT])
	assert_array(mc.objectives_missing_geometry()).is_empty()


func test_a_patrol_zone_does_not_satisfy_a_capture_objective() -> void:
	# Kind is what makes geometry count. A mis-picked Kind must not quietly arm the objective.
	_paint("Patrol", ZoneManager.Kind.PATROL, [Vector2i(2, 2)])
	mc.objectives.assign([MissionRules.Objective.CAPTURE] as Array[MissionRules.Objective])
	assert_array(mc.objectives_missing_geometry()).contains_exactly([MissionRules.Objective.CAPTURE])


# ==============================================================================
#  The ending
# ==============================================================================

func test_ending_a_mission_locks_the_board_for_the_player() -> void:
	# _end_mission awaits the banner, so it is deliberately un-awaited by check(): is_over() must
	# already be true for every caller the moment check() returns, with the board locked.
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var enemy := _spawn(Team.Faction.ENEMY, Vector2i(4, 4))
	mc.check()
	enemy.die()
	mc.check()

	assert_bool(mc.is_over()).is_true()
	assert_int(game.game_state).is_equal(game.GameState.MISSION_OVER)
	assert_bool(game._board_locked_for_player()).is_true()


func test_a_locked_board_ignores_clicks() -> void:
	# What the lock is FOR. _unhandled_input returns early, so no order can be queued after the
	# banner is up — checked through the same guard the input handler reads.
	var player := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var enemy := _spawn(Team.Faction.ENEMY, Vector2i(4, 4))
	mc.check()
	enemy.die()
	mc.check()

	assert_bool(game._board_locked_for_player()).is_true()
	assert_object(game.selected_unit).is_null()
	assert_bool(player.is_active()).is_true()


func test_the_ai_stands_down_once_the_mission_is_over() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var enemy := _spawn(Team.Faction.ENEMY, Vector2i(4, 4))
	mc.check()
	enemy.die()
	mc.check()
	# AIController.take_faction_turn guards on this; a mission that ended must not keep planning.
	assert_bool(mc.is_over()).is_true()
