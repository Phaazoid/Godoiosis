# A squad leader's movement through the headless Play API (#46): the strand gate the game puts on a
# leader's move (#1069), and Group Move, the verb the bridge never had.
#
# The game refuses a leader's destination its squad cannot follow to at the CLICK
# (game._click_choosing_move reads leader_followable, built from GroupMoveSolver.stranding), so the
# order chokepoint never sees it -- and a headless queue_move used to accept it. Every expectation
# below is read off that same sweep rather than off a cell this fixture happens to produce, so a
# retuned MOV band or COH default moves the cells and not the verdicts.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

# Fixture knobs, not tuned values: a quick leader on a short leash and a slow member, so the leader
# can walk where the member cannot follow. Nothing below asserts what they produce.
const QUICK_DEX := 10
const SLOW_DEX := 0
const SHORT_COH := 1

var _board: Dictionary


func before_test() -> void:
	_board = BoardBuilder.build(self, "GroupMoveRoot")
	auto_free(_board.root)
	BoardBuilder.paint_rect(_board.grid, Rect2i(-4, -4, 18, 18))


func _data(unit_name: String, fac: Team.Faction, overrides: Dictionary = {}) -> UnitData:
	var stats := Stats.STAT_DEFAULTS.duplicate()
	for stat in overrides:
		stats[stat] = overrides[stat]
	return UnitFactory.create_unit_data(stats, unit_name, fac)


# Leader A at (0,0), member B at (0,1), a foe far off so the board has an enemy. Returns the session.
func _squad(leader_overrides: Dictionary, member_overrides: Dictionary) -> PlaySession:
	BoardBuilder.spawn(_board, _data("Lead", PLAYER, leader_overrides), Vector2i(0, 0))   # -> A
	BoardBuilder.spawn(_board, _data("Mate", PLAYER, member_overrides), Vector2i(0, 1))   # -> B
	BoardBuilder.spawn(_board, _data("Foe", ENEMY), Vector2i(12, 12))
	var session = PlaySession.new(_board)
	var joined: Dictionary = session.join("B", "A")
	assert_bool(joined.ok).override_failure_message("fixture: B could not join A: %s" % str(joined.get("error", ""))).is_true()
	return session


func _stranding_squad() -> PlaySession:
	return _squad({Stats.Stat.DEX: QUICK_DEX, Stats.Stat.COH: SHORT_COH}, {Stats.Stat.DEX: SLOW_DEX})


func _ctx() -> BoardContext:
	return (_board.squad_manager as SquadManager).board_source.call()


# The leader's walkable cells, split by the sweep the game's move mode greys out.
func _split(session) -> Dictionary:
	var leader: Unit = session.unit_by_handle("A")
	var reachable: Array[Vector2i] = []
	reachable.assign(RulesService.compute_move_range(leader, _ctx()).reachable.keys())
	var stranded := GroupMoveSolver.stranding(leader.squad, _ctx(), reachable)
	var followable: Array[Vector2i] = []
	var stranding: Array[Vector2i] = []
	for cell: Vector2i in reachable:
		if (stranded[cell] as Array).is_empty():
			followable.append(cell)
		else:
			stranding.append(cell)
	return {"followable": followable, "stranding": stranding, "who": stranded}


# Followable destinations B need not move for -- so a hold leaves the plan valid and a lone walk by
# the leader is the whole of it.
func _in_place(session) -> Array[Vector2i]:
	var leader: Unit = session.unit_by_handle("A")
	var mate: Unit = session.unit_by_handle("B")
	var out: Array[Vector2i] = []
	for cell: Vector2i in _split(session).followable:
		if SquadCohesion.in_range(leader.squad, cell, mate, mate.movement.cell, _ctx()):
			out.append(cell)
	return out


func _real_moves(squad: Squad) -> Array[MoveAction]:
	var out: Array[MoveAction] = []
	for action: BaseAction in squad.action_queue:
		if action is MoveAction and not (action as MoveAction).is_hold_position:
			out.append(action as MoveAction)
	return out


# ==============================================================================
#  The strand gate
# ==============================================================================

func test_a_leader_move_that_would_strand_a_squadmate_is_refused_naming_who() -> void:
	var session = _stranding_squad()
	var split := _split(session)
	var stranding: Array[Vector2i] = split.stranding
	assert_int(stranding.size()).override_failure_message(
		"fixture: the leader can strand nobody, so this case proves nothing").is_greater(0)
	var cell: Vector2i = stranding[0]
	var leader: Unit = session.unit_by_handle("A")

	var r: Dictionary = session.queue_move("A", cell)

	assert_bool(r.ok).override_failure_message(
		"the leader walked to %s, where B cannot follow -- the game refuses that click" % str(cell)).is_false()
	for left: Unit in (split.who[cell] as Array):
		assert_str(str(r.get("error", ""))).override_failure_message(
			"the refusal does not name %s, who could not follow: %s" % [session.handle_for(left), str(r.get("error", ""))]
			).contains(session.handle_for(left))
	assert_array(_real_moves(leader.squad)).override_failure_message("the refused move landed in the queue").is_empty()
	assert_object(session.squad_manager.active_squad).override_failure_message(
		"the refused move opened the squad's plan").is_null()


func test_legal_moves_holds_the_stranding_cells_out_of_cells() -> void:
	var session = _stranding_squad()
	var split := _split(session)
	var offered: Dictionary = session.legal_moves("A")
	assert_bool(offered.ok).is_true()
	var cells: Array[Vector2i] = []
	cells.assign(offered.cells)
	var withheld: Array[Vector2i] = []
	withheld.assign(offered.stranding)
	assert_int(withheld.size()).override_failure_message(
		"fixture: the leader can strand nobody, so this case proves nothing").is_greater(0)

	for cell: Vector2i in split.stranding:
		assert_bool(cells.has(cell)).override_failure_message(
			"legal_moves offered %s, where B cannot follow" % str(cell)).is_false()
	assert_array(withheld).contains_exactly_in_any_order(split.stranding)
	assert_array(cells).contains_exactly_in_any_order(split.followable)

	# The affordance law (test_affordances.gd) for a leader: everything offered is accepted, and
	# everything held out as stranding is refused. A squadmate's own cell is the one exception and not
	# this gate's: it is offered (a squad rotates through itself) and refused by the plan-context gate
	# while its occupant has no move away, which is a question about the plan, not the range.
	var mates := {}
	for member: Unit in (session.unit_by_handle("A") as Unit).squad.get_members():
		mates[member.movement.cell] = true
	var refused: Array[String] = []
	for cell: Vector2i in cells:
		if mates.has(cell):
			continue
		var r: Dictionary = session.queue_move("A", cell)
		if not r.ok:
			refused.append("%s: %s" % [str(cell), str(r.error)])
		session.cancel("A")
	assert_array(refused).override_failure_message(
		"legal_moves offered cells queue_move then refused:\n  %s" % "\n  ".join(refused)).is_empty()
	var accepted: Array[String] = []
	for cell: Vector2i in withheld:
		if (session.queue_move("A", cell) as Dictionary).ok:
			accepted.append(str(cell))
			session.cancel("A")
	assert_array(accepted).override_failure_message(
		"queue_move accepted cells legal_moves held out as stranding: %s" % ", ".join(accepted)).is_empty()


# ==============================================================================
#  Group Move
# ==============================================================================

func test_group_move_places_the_whole_squad_and_execute_moves_every_member() -> void:
	var session = _stranding_squad()
	var leader: Unit = session.unit_by_handle("A")
	var mate: Unit = session.unit_by_handle("B")
	# A destination the squad can follow to that B cannot reach by standing still: B has to move.
	var dest := GridUtils.NO_CELL
	for cell: Vector2i in _split(session).followable:
		if not SquadCohesion.in_range(leader.squad, cell, mate, mate.movement.cell, _ctx()):
			dest = cell
			break
	assert_that(dest).override_failure_message(
		"fixture: every followable destination keeps B where it stands, so no member would move").is_not_equal(GridUtils.NO_CELL)
	var starts := {leader: leader.movement.cell, mate: mate.movement.cell}

	var r: Dictionary = session.group_move("A", dest)

	assert_bool(r.ok).override_failure_message("the group move was refused: %s" % str(r.get("error", ""))).is_true()
	var headed := {}
	for member: Unit in [leader, mate]:
		headed[member] = member.get_projected_destination()
		assert_that(headed[member]).override_failure_message(
			"%s was given no move by the formation" % session.handle_for(member)).is_not_equal(starts[member])
		assert_str(str(r.get("summary", ""))).override_failure_message(
			"the summary does not say where %s is headed" % session.handle_for(member)).contains(session.handle_for(member))
	assert_that(headed[leader]).is_equal(dest)

	var done: Dictionary = session.execute()

	assert_bool(done.ok).override_failure_message("the formation would not execute: %s" % str(done.get("error", ""))).is_true()
	for member: Unit in [leader, mate]:
		assert_that(member.movement.cell).override_failure_message(
			"%s did not walk to where the formation sent it" % session.handle_for(member)).is_equal(headed[member])


# The door asks every question BEFORE it cancels a queued formation: refusing after the cancel would
# throw away a plan the player never asked to lose.
func test_a_group_move_refused_by_a_members_main_action_leaves_the_plan_intact() -> void:
	BoardBuilder.spawn(_board, _data("Near", ENEMY), Vector2i(-1, 1))   # beside B
	var session = _squad({}, {})
	var leader: Unit = session.unit_by_handle("A")
	var mate: Unit = session.unit_by_handle("B")
	BoardBuilder.arm(mate, 3)
	var followable := _in_place(session)
	assert_int(followable.size()).override_failure_message("fixture: the leader can follow nowhere").is_greater(1)
	var walked: Dictionary = session.queue_move("A", followable[0])
	assert_bool(walked.ok).override_failure_message("fixture: A's walk was refused: %s" % str(walked.get("error", ""))).is_true()
	var aimed: Dictionary = session.queue_attack("B", Vector2i(-1, 1))
	assert_bool(aimed.ok).override_failure_message("fixture: B's attack was refused: %s" % str(aimed.get("error", ""))).is_true()
	var before: Array[BaseAction] = leader.squad.action_queue.duplicate()
	var walk: MoveAction = _real_moves(leader.squad)[0]

	var r: Dictionary = session.group_move("A", followable[1])

	assert_bool(r.ok).override_failure_message("a formation was led off while B holds a main action").is_false()
	assert_str(str(r.get("error", ""))).contains(session.handle_for(mate))
	assert_array(_real_moves(leader.squad)).override_failure_message(
		"the refused group move cancelled A's queued walk first").contains_exactly([walk])
	assert_array(leader.squad.action_queue).override_failure_message(
		"the refused group move changed the plan").contains_exactly(before)


# ==============================================================================
#  Status
# ==============================================================================

func test_status_counts_the_orders_given_not_the_hold_fillers() -> void:
	var session = _squad({}, {})
	var leader: Unit = session.unit_by_handle("A")
	var followable := _in_place(session)
	assert_int(followable.size()).override_failure_message("fixture: the leader can follow nowhere").is_greater(0)
	assert_bool((session.queue_move("A", followable[0]) as Dictionary).ok).is_true()
	var holds := 0
	for action: BaseAction in leader.squad.action_queue:
		if action is MoveAction and (action as MoveAction).is_hold_position:
			holds += 1
	assert_int(holds).override_failure_message(
		"fixture: B grew no hold filler, so this case is not exercising the exclusion").is_greater(0)

	assert_int(int(session.status().queued)).override_failure_message(
		"status counted the hold fillers as orders").is_equal(1)
