# Drill Burrow's terrain consequence (#84), proven on a REAL board (BoardBuilder paints walkable
# tiles AND now carries a TerrainStateManager, so deposits actually land somewhere). Covers: a
# queued Burrow deposits a COVER tile on execute and not before; it lands on the cell the digger
# ENDS on (projected destination, so move-then-burrow entrenches the destination); the tile raises
# the digger's DEF by exactly the shared breakdown's cover term; and it's permanent — no timer
# ticks it away.
#
# The mitigation arithmetic itself (cover subtracts, stacks with armor, a revved Chainsword
# pierces it) lives in tests/law/test_def_mitigation.gd.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER


func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)


func _drill() -> WeaponInstance:
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.DRILL
	t.main_attack = WeaponAttackData.new()
	t.main_attack.power = 3
	return WeaponInstance.make(t)


# A painted board with one drill-armed digger at `cell`.
func _dig_board(cell: Vector2i, armed := true) -> Dictionary:
	var b := BoardBuilder.build(self, "BurrowRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 12, 12))
	var digger: Unit = BoardBuilder.spawn(b, _data("Digger", PLAYER), cell)
	if armed:
		digger.add_item(_drill())
	var sess = PlaySession.new(b)
	return {"board": b, "sess": sess, "digger": digger}


func test_burrow_deposits_cover_only_on_execute() -> void:
	var s := _dig_board(Vector2i(1, 1))
	var sess = s.sess
	var states: TerrainStateManager = s.board.terrain_states

	var res: Dictionary = sess.burrow(sess.handle_for(s.digger))
	assert_bool(res.ok).is_true()
	# Queued, not yet dug — the plan holds the deposit until the pass runs (R3).
	assert_bool(states.has_state(Vector2i(1, 1), Terrain.TileState.COVER)).is_false()

	sess.execute()
	assert_bool(states.has_state(Vector2i(1, 1), Terrain.TileState.COVER)).is_true()


func test_cover_lands_where_the_digger_ends_up() -> void:
	# Burrow is a main action, so it follows any move: you entrench where you STOP, not where you
	# started. Reads get_projected_destination, the same source counters and previews use.
	var s := _dig_board(Vector2i(1, 1))
	var sess = s.sess
	var states: TerrainStateManager = s.board.terrain_states
	var handle: String = sess.handle_for(s.digger)

	sess.queue_move(handle, Vector2i(3, 1))
	sess.burrow(handle)
	sess.execute()

	assert_bool(states.has_state(Vector2i(3, 1), Terrain.TileState.COVER)).is_true()
	assert_bool(states.has_state(Vector2i(1, 1), Terrain.TileState.COVER)).is_false()


func test_burrowing_raises_the_diggers_def_by_the_cover_term() -> void:
	# The end-to-end payoff, read through the SAME query the inspect panel makes.
	var s := _dig_board(Vector2i(1, 1))
	var sess = s.sess
	var digger: Unit = s.digger

	var before := RulesService.def_breakdown(digger, digger.movement.cell, sess._board())
	assert_int(before["cover"]).is_equal(0)

	sess.burrow(sess.handle_for(digger))
	sess.execute()

	var after := RulesService.def_breakdown(digger, digger.movement.cell, sess._board())
	assert_int(after["cover"]).is_equal(Terrain.COVER_DEF)
	assert_int(after["total"] - before["total"]).is_equal(Terrain.COVER_DEF)


func test_cover_shelters_whoever_stands_there_not_just_the_digger() -> void:
	# It's terrain, not a personal buff — the tile is the thing that carries the DEF.
	var s := _dig_board(Vector2i(1, 1))
	var sess = s.sess
	sess.burrow(sess.handle_for(s.digger))
	sess.execute()

	var squatter: Unit = BoardBuilder.spawn(s.board, _data("Squatter", PLAYER), Vector2i(1, 1))
	var def := RulesService.def_breakdown(squatter, Vector2i(1, 1), sess._board())
	assert_int(def["cover"]).is_equal(Terrain.COVER_DEF)


func test_cover_is_permanent_and_never_ticks_out() -> void:
	# COVER has no STATE_DURATIONS entry by design: it is removed by a destructive hit, never by
	# a timer (unlike BURNING; FROZEN joined COVER as permanent 2026-08-12). Round ticks must not
	# erode it.
	var s := _dig_board(Vector2i(1, 1))
	var sess = s.sess
	var states: TerrainStateManager = s.board.terrain_states
	sess.burrow(sess.handle_for(s.digger))
	sess.execute()

	for _round in range(6):
		states.tick_states()

	assert_bool(states.has_state(Vector2i(1, 1), Terrain.TileState.COVER)).is_true()


func test_a_unit_without_a_drill_cannot_burrow() -> void:
	var s := _dig_board(Vector2i(1, 1), false)
	var res: Dictionary = s.sess.burrow(s.sess.handle_for(s.digger))
	assert_bool(res.ok).is_false()
	assert_str(res.error).contains("drill")
