# #760: the AI goes looking for a removal or a squad break it can reach this turn, instead of taking
# one only when it happens to stand in the right place. Dev rulings, 2026-10-03 (on the issue): only
# those two terms pull a unit off the cell it would normally take, and the squad seeks as ONE unit --
# the leader first, then the closest member that can do it.
#
# Fixture conventions follow tests/ai/test_squad_scoring.gd: the Play API's headless board_builder
# over real TestTiles terrain, pattern-less weapons so reach is Manhattan 1, baseline stats.
#
# THE BOARD most cases use: one hole, with the target directly north of it. Only a shove from the
# cell north of the target (N) drops it in. The attacker starts west, where the nearest firing cell
# (W) pushes the target east onto ground.
#
#   x       2   3   4
#   y=3             N
#   y=4     A   W   T
#   y=5             O   <- the hole
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")

const ENEMY := Team.Faction.ENEMY
const PLAYER := Team.Faction.PLAYER

const T := Vector2i(4, 4)
const N := Vector2i(4, 3)
const W := Vector2i(3, 4)
const HOLE := Vector2i(4, 5)
const A_START := Vector2i(2, 4)


func _board(size := Rect2i(0, 0, 8, 8), hole := HOLE) -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, size)
	if hole != GridUtils.NO_CELL:
		board.grid.erase_cell(hole)   # inside the painted rect, so a hole rather than the edge
	return board


func _spawn(board: Dictionary, faction: Team.Faction, cell: Vector2i, overrides: Dictionary = {}) -> Unit:
	return BB.spawn(board, H.make_unit_data(overrides, faction), cell)


# A damageless one-tile shove: on this board it can only matter by WHERE it puts somebody.
func _shover() -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = 3
	template.main_attack.knockback = 1
	template.main_attack.deals_no_damage = true
	return WeaponInstance.make(template)


func _context(board: Dictionary) -> BoardContext:
	return board.squad_manager.board_source.call()


func _plan(unit: Unit, board: Dictionary) -> void:
	AIController.plan_squad(unit.squad, _context(board), board.squad_manager)


func _aim_of(unit: Unit) -> AttackAction:
	for action in unit.squad.action_queue:
		if action is AttackAction and action.actor == unit:
			return action as AttackAction
	return null


func _plan_removes(board: Dictionary, squad: Squad, victim: Unit) -> bool:
	var plan: ResolvedPlan = board.squad_manager.resolve_plan(squad, _context(board))
	return AITactics._plan_removes(victim, plan)


# The board above with the attacker and its target on it.
func _hole_board() -> Dictionary:
	var board := _board()
	board["target"] = _spawn(board, PLAYER, T)
	var attacker := _spawn(board, ENEMY, A_START)
	attacker.equipped_weapon = _shover()
	board["attacker"] = attacker
	return board


# ==============================================================================

func test_a_leader_steps_to_the_cell_that_shoves_its_target_into_a_hole() -> void:
	var board := _hole_board()
	var attacker: Unit = board.attacker
	var target: Unit = board.target
	assert_that(AITactics.best_attack_destination(attacker, target, _context(board))) \
		.override_failure_message("fixture: the approach alone would not take W").is_equal(W)

	_plan(attacker, board)

	assert_that(attacker.get_projected_destination()) \
		.override_failure_message("the AI did not go to the cell that drops its target in the hole").is_equal(N)
	var aim := _aim_of(attacker)
	assert_object(aim).override_failure_message("the AI queued no attack from the shove cell").is_not_null()
	assert_that(aim.target_cell).is_equal(T)
	assert_bool(_plan_removes(board, attacker.squad, target)) \
		.override_failure_message("the plan does not remove the target").is_true()


# The rule's other half: a cell that only adds DAMAGE never pulls anyone off their cell. Here the
# shove from N drops the target off a ledge -- it hurts, it does not remove.
func test_a_shove_that_only_hurts_is_not_worth_a_detour() -> void:
	var board := _board(Rect2i(0, 0, 8, 8), GridUtils.NO_CELL)
	var heights: BoardHeights = board.board_heights
	for x in 8:
		for y in 8:
			heights.set_cell(Vector2i(x, y), 2)
	heights.set_cell(HOLE, 0)   # one level down: a fall, never a hole
	var target := _spawn(board, PLAYER, T, {Stats.Stat.MHP: 99})   # survives any sane fall tuning
	var attacker := _spawn(board, ENEMY, A_START)
	attacker.equipped_weapon = _shover()

	var score := _score_from(board, attacker, N, T)
	assert_bool(score.z > 0 and score.x == 0 and score.y == 0) \
		.override_failure_message("fixture: the shove from N must hurt and remove nothing, scored %s" % score).is_true()

	_plan(attacker, board)

	assert_that(attacker.get_projected_destination()) \
		.override_failure_message("damage alone pulled the AI off its cell").is_equal(W)


# Breaking a squad is the score's second term (#761), so it is sought too. The enemy pair sits at
# the edge of its leader's range: a shove from the west knocks the member out, the AI's own approach
# cell pushes it into the board edge and changes nothing.
func test_a_cell_that_breaks_a_squad_is_sought() -> void:
	var board := _board(Rect2i(0, 0, 8, 4), GridUtils.NO_CELL)
	var lead := _spawn(board, PLAYER, Vector2i(0, 0))
	var edge := _spawn(board, PLAYER, Vector2i(4, 0))
	board.squad_manager.join_squad(edge, lead.squad)
	var attacker := _spawn(board, ENEMY, Vector2i(4, 2))
	attacker.equipped_weapon = _shover()
	var ctx := _context(board)
	assert_object(AITactics.choose_engagement_target(attacker, ctx, board.squad_manager)).is_same(edge)
	assert_that(AITactics.best_attack_destination(attacker, edge, ctx)) \
		.override_failure_message("fixture: the approach alone would already take the breaking cell") \
		.is_equal(Vector2i(4, 1))

	_plan(attacker, board)

	assert_that(attacker.get_projected_destination()) \
		.override_failure_message("the AI did not go to the cell that breaks the squad").is_equal(Vector2i(3, 0))


# A removal paid for with one of ours is no removal: the score is NET. N drops the target in the
# hole, but the target's squadmate stands beside N and its counter fells the attacker -- one each,
# net zero, so the detour is not taken. (The counter is seen at all only because the attacker is
# stood on N while N is scored; without that, nothing is scored from N, which case 1 catches.)
func test_a_cell_whose_counter_fells_us_is_not_sought() -> void:
	var board := _hole_board()
	var attacker: Unit = board.attacker
	var target: Unit = board.target
	var guard := _spawn(board, PLAYER, Vector2i(5, 3))
	guard.equipped_weapon = H.make_weapon(40)
	board.squad_manager.join_squad(guard, target.squad)

	_plan(attacker, board)

	assert_that(attacker.get_projected_destination()) \
		.override_failure_message("the AI walked into a counter that fells it for the shove").is_equal(W)


# The squad is one unit: when the leader cannot take it, the CLOSEST member that can does. The far
# member joined first, so member order alone would hand it the cell.
func test_the_closest_member_that_can_takes_the_shove() -> void:
	var board := _squad_board()
	var near: Unit = board.near
	var far: Unit = board.far

	_plan(board.leader, board)

	assert_that(near.get_projected_destination()) \
		.override_failure_message("the closest member did not take the shove cell").is_equal(N)
	assert_that(far.get_projected_destination()) \
		.override_failure_message("the far member was pulled off its formation cell too").is_not_equal(N)
	assert_bool(_plan_removes(board, near.squad, board.target)) \
		.override_failure_message("the plan does not remove the target").is_true()


# Leader first: a member closer to the cell does not take it from a leader that can.
func test_the_leader_takes_the_shove_before_a_closer_member() -> void:
	var board := _board()
	var _target := _spawn(board, PLAYER, T)
	var leader := _spawn(board, ENEMY, A_START, {Stats.Stat.LDR: 10})
	leader.equipped_weapon = _shover()
	var member := _spawn(board, ENEMY, Vector2i(4, 2))
	member.equipped_weapon = _shover()
	board.squad_manager.join_squad(member, leader.squad)

	_plan(leader, board)

	assert_that(leader.get_projected_destination()) \
		.override_failure_message("the leader did not take the shove first").is_equal(N)
	assert_that(member.get_projected_destination()).is_not_equal(N)


# A Sentry seeks only inside its leash: never from a cell it may not stand on...
func test_a_sentry_does_not_leave_its_allowed_cells_to_seek() -> void:
	var board := _hole_board()
	var attacker: Unit = board.attacker
	var allowed := {}
	for x in 8:
		for y in 8:
			allowed[Vector2i(x, y)] = true
	allowed.erase(N)
	var within := { T: true }

	AITactics.engage(attacker.squad, board.target, _context(board), board.squad_manager, allowed, within)

	assert_that(attacker.get_projected_destination()).is_equal(W)


# ...and never for someone outside its zone, which would be a sentry lured by bait.
func test_a_sentry_does_not_seek_a_target_outside_its_zone() -> void:
	var board := _hole_board()
	var attacker: Unit = board.attacker
	var within := { Vector2i(0, 0): true }

	AITactics.engage(attacker.squad, board.target, _context(board), board.squad_manager, null, within)

	assert_that(attacker.get_projected_destination()).is_equal(W)


# A leader never seeks a cell its squad cannot follow it to. The member has no legs (MOV 1), so it
# cannot get within range of the shove cell. Its twin below, with legs, proves the cell is sought.
func test_a_leader_does_not_seek_a_cell_its_squad_cannot_follow_to() -> void:
	var board := _follow_board(true)
	_plan(board.leader, board)
	assert_that((board.leader as Unit).get_projected_destination()) \
		.override_failure_message("the leader left a member it could not keep").is_equal(Vector2i(6, 4))


func test_with_a_squad_that_can_follow_the_same_cell_is_sought() -> void:
	var board := _follow_board(false)
	_plan(board.leader, board)
	assert_that((board.leader as Unit).get_projected_destination()).is_equal(Vector2i(7, 3))


# Scoring by standing on cells must hand the board back as it found it: every member on its own
# cell and nothing queued, since the seek runs before anything is.
func test_the_seek_puts_every_unit_back() -> void:
	var board := _squad_board()
	var squad: Squad = (board.leader as Unit).squad
	var before := {}
	for member in squad.get_members():
		before[member] = member.movement.cell

	var seek := AITactics.seek_positions(squad, W, _context(board), board.squad_manager)

	assert_bool(seek.pins.has(board.near)).override_failure_message("fixture: the seek pinned nobody").is_true()
	for member in squad.get_members():
		assert_that(member.movement.cell) \
			.override_failure_message("%s was left on a searched cell" % member.name).is_equal(before[member])
	assert_that((board.target as Unit).movement.cell).is_equal(T)
	assert_bool(squad.action_queue.is_empty()).is_true()


# ==============================================================================

# A squad of three against the target. The leader's own weapon cannot remove anyone, so it walks to
# W as usual; both members carry the shove, and NEAR is one step closer to N than FAR. FAR joins first.
func _squad_board() -> Dictionary:
	var board := _board()
	board["target"] = _spawn(board, PLAYER, T)
	var leader := _spawn(board, ENEMY, A_START, {Stats.Stat.LDR: 10})
	leader.equipped_weapon = H.make_weapon()
	var far := _spawn(board, ENEMY, Vector2i(1, 4))
	far.equipped_weapon = _shover()
	var near := _spawn(board, ENEMY, Vector2i(2, 2))
	near.equipped_weapon = _shover()
	board.squad_manager.join_squad(far, leader.squad)
	board.squad_manager.join_squad(near, leader.squad)
	board["leader"] = leader
	board["far"] = far
	board["near"] = near
	return board


# The hole board shifted three columns east, with a member trailing far behind the leader.
func _follow_board(legless: bool) -> Dictionary:
	var board := _board(Rect2i(0, 0, 9, 8), Vector2i(7, 5))
	var _target := _spawn(board, PLAYER, Vector2i(7, 4))
	var leader := _spawn(board, ENEMY, Vector2i(5, 4), {Stats.Stat.LDR: 10})
	leader.equipped_weapon = _shover()
	var member := _spawn(board, ENEMY, Vector2i(2, 4))
	if legless:
		member.unit_instance.limbs[UnitInstance.LimbSlot.LEG_L].state = UnitInstance.LimbState.EMPTY
		member.unit_instance.limbs[UnitInstance.LimbSlot.LEG_R].state = UnitInstance.LimbState.EMPTY
	board.squad_manager.join_squad(member, leader.squad)
	board["leader"] = leader
	return board


# What `unit`'s attack on the unit at `at` scores when fired from `cell`, by standing it there.
func _score_from(board: Dictionary, unit: Unit, cell: Vector2i, at: Vector2i) -> Vector4i:
	var ctx := _context(board)
	var start := unit.movement.cell
	unit.movement.set_cell(cell)
	var score := Vector4i.ZERO
	for candidate in AITactics._attack_candidates(unit, ctx, cell, {}):
		if candidate.target_cell == at:
			var one: Array[BaseAction] = [candidate]
			score = AITactics._score_plan(unit.get_faction(), board.squad_manager.resolve_hypothetical(unit.squad, one, ctx))
	unit.movement.set_cell(start)
	board.squad_manager.resolve_plan(unit.squad, ctx)
	return score
