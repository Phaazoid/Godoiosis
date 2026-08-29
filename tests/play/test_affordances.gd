# legal_moves / legal_targets / status (#613) -- the queries that let a driver ask what is legal
# instead of guessing a cell and being refused.
#
# WHY THE HEADLINE CASES ARE AGREEMENT PROPERTIES RATHER THAN EXAMPLES. Measured over five logged
# playthroughs, a third to a half of every command came back rejected: `move` 55%, `attack` 61%.
# These queries exist to remove that, and they only do so while they answer with the SAME predicate
# the queue gates on. A second reachability walk here would fail silently and exactly -- the API
# would start offering a cell queue_move refuses, which is the original bug one layer up (Law #4).
# So the cases below drive BOTH sides and require them to agree cell for cell, in both directions:
# everything offered is accepted, and everything withheld is refused.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")
const BoardView := preload("res://play/board_view.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _board: Dictionary
var _session


func before_test() -> void:
	_board = BoardBuilder.build(self)
	auto_free(_board.root)
	BoardBuilder.paint_rect(_board.grid, Rect2i(-2, -2, 12, 12))
	var p := BoardBuilder.spawn(_board, _data("P1", PLAYER), Vector2i(0, 0))   # -> A
	var e := BoardBuilder.spawn(_board, _data("E1", ENEMY), Vector2i(2, 0))    # -> a
	BoardBuilder.arm(p, 6)
	BoardBuilder.arm(e, 4)
	_session = PlaySession.new(_board)


func _data(name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), name, fac)


# ==============================================================================
#  The agreement properties
# ==============================================================================

func test_every_cell_legal_moves_offers_is_one_queue_move_accepts() -> void:
	var offered: Dictionary = _session.legal_moves("A")
	assert_bool(offered.ok).is_true()
	assert_int(offered.cells.size()).override_failure_message(
		"the fixture unit can reach nowhere, so this case proves nothing").is_greater(0)

	# One at a time, cancelling between, so each is judged from the same starting position.
	var refused: Array[String] = []
	for cell: Vector2i in offered.cells:
		var r: Dictionary = _session.queue_move("A", cell)
		if not r.ok:
			refused.append("%s: %s" % [str(cell), str(r.error)])
		_session.cancel("A")
	assert_array(refused).override_failure_message(
		("legal_moves offered cells queue_move then refused, which is the drift these queries "
		+ "exist to prevent:\n  %s") % "\n  ".join(refused)).is_empty()


func test_and_every_cell_it_withholds_is_one_queue_move_refuses() -> void:
	# The other direction, and the one a too-SMALL answer would slip past: a query that offered
	# nothing would pass the case above vacuously.
	var offered: Dictionary = _session.legal_moves("A")
	var allowed := {}
	for cell: Vector2i in offered.cells:
		allowed[cell] = true

	var wrongly_refused: Array[String] = []
	for y in range(-2, 10):
		for x in range(-2, 10):
			var cell := Vector2i(x, y)
			if allowed.has(cell) or cell == Vector2i(0, 0):
				continue   # (0,0) is the unit's own cell: refused as "already at", not as unreachable
			var r: Dictionary = _session.queue_move("A", cell)
			if r.ok:
				wrongly_refused.append(str(cell))
			_session.cancel("A")
	assert_array(wrongly_refused).override_failure_message(
		("queue_move accepted cells legal_moves never offered, so the query is blind to part of "
		+ "the range: %s") % ", ".join(wrongly_refused)).is_empty()


func test_every_aim_legal_targets_offers_is_one_queue_attack_accepts() -> void:
	_session.queue_move("A", Vector2i(1, 0))   # step adjacent to 'a' so there is something to hit
	var offered: Dictionary = _session.legal_targets("A")
	assert_bool(offered.ok).is_true()
	assert_int(offered.aims.size()).override_failure_message(
		"no aim was offered, so this case proves nothing").is_greater(0)

	var refused: Array[String] = []
	for aim: Dictionary in offered.aims:
		var r: Dictionary = _session.queue_attack("A", aim.cell)
		if not r.ok:
			refused.append("%s: %s" % [str(aim.cell), str(r.error)])
		else:
			_session.cancel("A")
			_session.queue_move("A", Vector2i(1, 0))   # cancel drops the move too; put it back
	assert_array(refused).override_failure_message(
		"legal_targets offered aims queue_attack then refused:\n  %s" % "\n  ".join(refused)).is_empty()


func test_a_named_victim_is_the_unit_actually_standing_there() -> void:
	# The aim list carries victims so a driver can choose a target without a second round trip;
	# a handle that named the wrong unit would be worse than no handle at all.
	_session.queue_move("A", Vector2i(1, 0))
	var offered: Dictionary = _session.legal_targets("A")
	var found := false
	for aim: Dictionary in offered.aims:
		if aim.cell == Vector2i(2, 0):
			assert_array(aim.victims).contains(["a"])
			found = true
	assert_bool(found).override_failure_message(
		"the enemy's own cell was not among the offered aims").is_true()


# ==============================================================================
#  Status -- the turn state the rendered board never carried
# ==============================================================================

func test_status_names_the_faction_the_active_squad_and_what_is_queued() -> void:
	var idle: Dictionary = _session.status()
	assert_str(str(idle.faction)).is_equal("PLAYER")
	assert_int(int(idle.active_squad)).override_failure_message(
		"nothing is queued yet, so no squad should hold the activation").is_equal(-1)
	assert_int(int(idle.queued)).is_equal(0)

	_session.queue_move("A", Vector2i(1, 0))
	var armed: Dictionary = _session.status()
	assert_int(int(armed.active_squad)).override_failure_message(
		"a queued order did not show up as an active squad").is_not_equal(-1)
	assert_int(int(armed.queued)).is_greater(0)


func test_status_lists_only_the_active_faction_s_squads() -> void:
	# The enemy's squads are not the caller's business on the player's turn, and listing them is
	# how "free=" stops meaning "squads you may still order".
	var st: Dictionary = _session.status()
	var enemy: Unit = _session.unit_by_handle("a")
	var enemy_id: int = _session._squad_id(enemy.squad)
	assert_bool(st.free.has(enemy_id) or st.acted.has(enemy_id)).override_failure_message(
		"an ENEMY squad appeared in the PLAYER turn's status").is_false()


func test_the_rendered_status_says_the_same_thing_it_is_derived_from() -> void:
	_session.queue_move("A", Vector2i(1, 0))
	var line := BoardView.render_status(_session)
	var st: Dictionary = _session.status()
	assert_str(line).contains("turn=PLAYER")
	assert_str(line).override_failure_message(
		"the rendered line does not name the squad status() reports as active"
		).contains("active=sq%d" % int(st.active_squad))


# ==============================================================================
#  The refusals a driver actually hit
# ==============================================================================

func test_asking_about_a_unit_you_may_not_command_answers_why() -> void:
	# Both queries route through the same _controllable gate the mutating verbs use, so the reason
	# a query refuses and the reason an order refuses are the same sentence.
	var r: Dictionary = _session.legal_moves("a")   # enemy, on the player's turn
	assert_bool(r.ok).is_false()
	assert_str(str(r.error)).contains("active faction")


func test_a_spent_squad_is_refused_by_the_query_as_well_as_the_order() -> void:
	_session.queue_move("A", Vector2i(1, 0))
	_session.execute()
	var r: Dictionary = _session.legal_moves("A")
	assert_bool(r.ok).override_failure_message(
		"a spent squad was still offered moves").is_false()
	assert_str(str(r.error)).contains("already acted")
