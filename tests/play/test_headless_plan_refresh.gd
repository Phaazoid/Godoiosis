# The headless session re-resolves a squad's plan after every change to it, as the game does (#46).
#
# game.gd hangs refresh_action_queue off SquadManager's queue signals, so every queued, cancelled or
# re-planned order is followed at once by a resolve: published knockback, the stored plan and each
# aim's verdict are always the plan as it now stands. PlaySession only resolved inside preview() and
# execute(), so a second order was judged against a board the first had not yet been resolved onto.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const BLOWBACK := "Blowback"

var _board: Dictionary


func before_test() -> void:
	_board = BoardBuilder.build(self, "PlanRefreshRoot")
	auto_free(_board.root)
	BoardBuilder.paint_rect(_board.grid, Rect2i(-3, -3, 12, 12))


# A leader with room for the squads below whatever the stat defaults are tuned to.
func _leader_data(unit_name: String) -> UnitData:
	var stats := Stats.STAT_DEFAULTS.duplicate()
	stats[Stats.Stat.COH] = 8
	stats[Stats.Stat.LDR] = 12
	return UnitFactory.create_unit_data(stats, unit_name, PLAYER)


func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)


func _arm_healer(unit: Unit) -> void:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = 4
	template.main_attack.heals = true
	template.main_attack.hits_allies = true
	unit.add_item(WeaponInstance.make(template))


# A Kinetic Mace whose charged Blowback shoves its target one cell away (test_knockback.gd's fixture).
func _arm_mace(unit: Unit) -> void:
	var blowback := WeaponAttackData.new()
	blowback.display_name = BLOWBACK
	blowback.knockback = 1
	blowback.requires_readiness = true
	blowback.consumes_readiness = true
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.KINETIC_MACE
	var smash := WeaponAttackData.new()
	smash.builds_readiness = true
	template.main_attack = smash
	var extras: Array[WeaponAttackData] = [blowback]
	template.extra_attacks = extras
	unit.add_item(WeaponInstance.make(template))
	(unit.get_equipped_weapon() as KineticMaceWeaponInstance).charge = 1


func _ok(result: Dictionary, what: String) -> void:
	assert_bool(result.ok).override_failure_message("%s was refused: %s" % [what, str(result.get("error", ""))]).is_true()


func _move(unit: Unit, to: Vector2i) -> MoveAction:
	var walk: Dictionary = RulesService.compute_move_range(unit, _board.squad_manager.board_source.call())
	var path: Array[Vector2i] = RulesService.reconstruct_path(walk.came_from, unit.movement.cell, to)
	var move := MoveAction.new()
	move.init(unit, path, null)
	return move


# The visible consequence: a re-plan that breaks a queued aim breaks it in the plan the session
# holds, with no preview asked for. B heals A where A stands; A then walks off the cell. Asserted on
# the plan, not the aim's is_valid: try_queue_action's own plan-less validate runs after the signal
# and resets an aim's flag, in the game as here.
func test_a_replan_that_breaks_an_aim_is_resolved_without_a_preview() -> void:
	var leader: Unit = BoardBuilder.spawn(_board, _leader_data("Lead"), Vector2i(0, 0))   # -> A
	var healer: Unit = BoardBuilder.spawn(_board, _data("Medic", PLAYER), Vector2i(1, 0))  # -> B
	BoardBuilder.arm(BoardBuilder.spawn(_board, _data("Foe", ENEMY), Vector2i(6, 6)), 3)
	BoardBuilder.arm(leader, 3)
	_arm_healer(healer)
	var session = PlaySession.new(_board)
	var sm: SquadManager = _board.squad_manager
	_ok(session.join("B", "A"), "the join")
	_ok(session.queue_attack("B", Vector2i(0, 0)), "the heal on A's cell")
	var heal: AttackAction = null
	for action: BaseAction in leader.squad.action_queue:
		if action.actor == healer and action is AttackAction:
			heal = action as AttackAction
	assert_object(heal).override_failure_message("fixture: the heal never reached the queue").is_not_null()
	var queued: ResolvedPlan = sm.resolved_plan_for(leader.squad)
	assert_object(queued).override_failure_message(
		"queueing the heal resolved no plan -- the session still resolves only inside preview()").is_not_null()
	if queued == null:
		return
	assert_bool(_finds_a_target(queued, heal)).override_failure_message(
		"fixture: the plan resolved with the heal does not find A on its cell").is_true()

	_ok(session.queue_move("A", Vector2i(0, 1)), "A's walk off the healed cell")

	var walked: ResolvedPlan = sm.resolved_plan_for(leader.squad)
	assert_object(walked).override_failure_message("the walk resolved no plan at all").is_not_null()
	if walked == null:
		return
	assert_bool(_finds_a_target(walked, heal)).override_failure_message(
		"the stored plan predates A's walk: the heal still finds A on the cell A left").is_false()


func _finds_a_target(plan: ResolvedPlan, aim: AttackAction) -> bool:
	for resolved: AttackAction in plan.attacks:
		if resolved.source_aim == aim and resolved.target != null:
			return true
	return false


# The order AFTER a shove is judged against the shove (the queue gate reads published knockback).
# A's Blowback throws the foe from (1,0) to (2,0); B then aims at (2,0), where only the shove puts anybody.
func test_a_second_order_is_judged_against_the_first_orders_shove() -> void:
	var hero: Unit = BoardBuilder.spawn(_board, _leader_data("Hero"), Vector2i(0, 0))    # -> A
	var mate: Unit = BoardBuilder.spawn(_board, _data("Mate", PLAYER), Vector2i(2, 1))   # -> B
	var foe: Unit = BoardBuilder.spawn(_board, _data("Foe", ENEMY), Vector2i(1, 0))      # -> a
	_arm_mace(hero)
	BoardBuilder.arm(mate, 3)
	BoardBuilder.arm(foe, 3)
	var session = PlaySession.new(_board)
	_ok(session.join("B", "A"), "the join")
	_ok(session.queue_attack("A", Vector2i(1, 0), BLOWBACK), "the Blowback")

	var res: Dictionary = session.queue_attack("B", Vector2i(2, 0))
	assert_bool(res.ok).override_failure_message(
		"B's aim at the cell the Blowback lands the foe on was refused (%s) -- the shove was never published, so the gate judged it against the board before A's order" % str(res.get("error", ""))).is_true()


# A formation is one decision: its ORDERS are judged once, when queue_batch closes, never per member --
# the queued handler sits a batch out, as game._on_unit_action_queued does. What a member's move
# DISPLACES is another signal: the hold filler it replaces (#46) is a cancel, and a cancel re-resolves
# in the game too (game._on_unit_action_cancelled). So each in-batch order is compared with the plan
# as the last signal left it, not with the plan from before the batch.
func test_a_batchs_orders_are_judged_once_when_it_closes() -> void:
	var leader: Unit = BoardBuilder.spawn(_board, _leader_data("Lead"), Vector2i(0, 0))   # -> A
	var second: Unit = BoardBuilder.spawn(_board, _data("Two", PLAYER), Vector2i(0, 1))   # -> B
	BoardBuilder.spawn(_board, _data("Three", PLAYER), Vector2i(1, 0))                    # -> C
	BoardBuilder.spawn(_board, _data("Foe", ENEMY), Vector2i(6, 6))
	var session = PlaySession.new(_board)
	var sm: SquadManager = _board.squad_manager
	_ok(session.join("B", "A"), "B's join")
	_ok(session.join("C", "A"), "C's join")
	# C's order opens the plan, so the batch below lands in a queue that is not empty.
	_ok(session.queue_move("C", Vector2i(2, 0)), "C's walk")
	var squad: Squad = leader.squad
	var before: ResolvedPlan = sm.resolved_plan_for(squad)
	assert_object(before).override_failure_message("C's order resolved no plan").is_not_null()

	# Connected AFTER the session's handlers, so each probe reads the plan the session left.
	var seen: Array[ResolvedPlan] = [before]
	var heard: Array[int] = [0]
	var judged_alone: Array[int] = [0]
	sm.squad_action_cancelled.connect(func(s: Squad, _u: Unit, _t: BaseAction.ActionType) -> void:
		seen[0] = sm.resolved_plan_for(s))
	sm.squad_action_queued.connect(func(s: Squad, _a: BaseAction) -> void:
		if not sm.batching:
			return
		heard[0] += 1
		if sm.resolved_plan_for(s) != seen[0]:
			judged_alone[0] += 1
		seen[0] = sm.resolved_plan_for(s))
	var moves: Array[MoveAction] = [_move(leader, Vector2i(0, -1)), _move(second, Vector2i(-1, 1))]
	assert_bool(sm.queue_batch(squad, moves)).override_failure_message("fixture: the batch was refused").is_true()

	assert_int(heard[0]).override_failure_message(
		"fixture: the probe heard %d in-batch orders, not 2" % heard[0]).is_equal(2)
	assert_int(judged_alone[0]).override_failure_message(
		"%d in-batch orders were re-resolved on their own -- a formation must be judged once, at its close" % judged_alone[0]).is_equal(0)
	assert_object(sm.resolved_plan_for(squad)).override_failure_message(
		"the batch closed and the plan was never re-resolved").is_not_same(seen[0])
