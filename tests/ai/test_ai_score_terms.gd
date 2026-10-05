# The score's #1220 terms, each driven through the AI's real door (queue_main_action / the joint
# pass) rather than by asking _score_plan for a number: the floor that keeps the AI from felling its
# own, the mission-ending kill above everything, and a melt-drowning priced as the removal it is.
#
# Rulings on #117 (2026-10-04/05): 1 (never fell its own), 2 (a mission kill ranks above everything).
#
# Boards are the Play API's headless board_builder over real TestTiles terrain; weapons are built
# here (the content razor), so every number below is the fixture's own.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")
const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const ATTACK_ONLY: Array = [BaseAction.ActionType.ATTACK]


func before_test() -> void:
	AIProfiles.use_fixtures({"": AIProfile.new()})   # #1230: this suite owns its AI profile


func after_test() -> void:
	AIProfiles.clear_fixtures()


func _build_board(size := Rect2i(0, 0, 6, 6)) -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, size)
	return board


func _spawn(board: Dictionary, faction: Team.Faction, cell: Vector2i, stats := {}, power := 3) -> Unit:
	var unit: Unit = BB.spawn(board, H.make_unit_data(stats, faction), cell)
	unit.equipped_weapon = H.make_weapon(power)
	return unit


func _ctx(board: Dictionary, mission: MissionState = null) -> BoardContext:
	var units: Array[Unit] = []
	for child in board.units_root.get_children():
		units.append(child as Unit)
	return BoardContext.new(board.grid, units, board.squad_manager, board.terrain_states, board.zone_manager,
			board.board_heights, board.gas_field, mission)


func _weapon_of(unit: Unit) -> WeaponInstance:
	return unit.get_equipped_weapon() as WeaponInstance


# A weak point shot at range 2, the "clean" alternative the floor falls back to.
func _give_clean_shot(unit: Unit) -> WeaponAttackData:
	var clean := WeaponAttackData.new()
	clean.power = 1
	P.point(clean, 2)
	var extras: Array[WeaponAttackData] = [clean]
	_weapon_of(unit).template.extra_attacks = extras
	return clean


func _queued_attack(unit: Unit) -> AttackAction:
	for action in unit.squad.action_queue:
		if action.action_type == BaseAction.ActionType.ATTACK and action.actor == unit:
			return action as AttackAction
	return null


# Deep water at `cell`, iced over -- frozen before anyone stands on it.
func _ice(board: Dictionary, cell: Vector2i) -> void:
	BB.paint_cell(board.grid, cell, BB.WATER_ATLAS)
	var freeze := ResolvedCellEffect.new()
	freeze.cell = cell
	freeze.states_added.assign([Terrain.TileState.FROZEN])
	(board.terrain_states as TerrainStateManager).apply(freeze)


# --- Ruling 1: the AI never fells its own ---------------------------------------------------------

# A line through a frail squadmate into two enemies nets a removal (+2 -1); the clean shot nets
# none. Without the floor the line wins on the first term it differs in.
func _line_through(board: Dictionary, ally_hp: int) -> Dictionary:
	var attacker := _spawn(board, ENEMY, Vector2i(0, 0))
	var line: WeaponAttackData = _weapon_of(attacker).template.main_attack
	line.power = 40
	line.hits_allies = true
	P.line(line, 3)
	var clean := _give_clean_shot(attacker)
	var ally := _spawn(board, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: ally_hp})
	board.squad_manager.join_squad(ally, attacker.squad)
	_spawn(board, PLAYER, Vector2i(2, 0), {Stats.Stat.MHP: 40})
	_spawn(board, PLAYER, Vector2i(3, 0), {Stats.Stat.MHP: 40})
	return {"attacker": attacker, "line": line, "clean": clean, "ally": ally}


func test_a_swing_that_would_fell_our_own_is_never_taken() -> void:
	var board := _build_board()
	var s := _line_through(board, 2)
	var attacker: Unit = s.attacker
	AITactics.queue_main_action(attacker, _ctx(board), board.squad_manager, ATTACK_ONLY)

	var aim := _queued_attack(attacker)
	assert_object(aim).override_failure_message("fixture: the attacker queued nothing at all").is_not_null()
	if aim == null:
		return
	assert_object(aim.fired_attack).override_failure_message(
			"the AI felled its own squadmate for a net removal").is_same(s.clean)


# The control: the same line through a squadmate it only SCRATCHES is still taken. The floor
# refuses a fall, never friendly fire as such -- that stays a price in the damage term.
func test_a_swing_that_only_hurts_our_own_is_still_weighed_on_its_merits() -> void:
	var board := _build_board()
	var s := _line_through(board, 99)
	var attacker: Unit = s.attacker
	AITactics.queue_main_action(attacker, _ctx(board), board.squad_manager, ATTACK_ONLY)

	var aim := _queued_attack(attacker)
	assert_object(aim).is_not_null()
	if aim == null:
		return
	assert_object(aim.fired_attack).override_failure_message(
			"fixture: the line must win when nobody of ours falls, or the floor case measures nothing") \
		.is_same(s.line)


func test_when_its_only_swing_would_fell_our_own_it_does_not_attack() -> void:
	var board := _build_board()
	var s := _line_through(board, 2)
	var attacker: Unit = s.attacker
	var none: Array[WeaponAttackData] = []
	_weapon_of(attacker).template.extra_attacks = none
	var queued := AITactics.queue_main_action(attacker, _ctx(board), board.squad_manager, ATTACK_ONLY)

	assert_bool(queued).override_failure_message(
			"the AI took a swing that fells its own because it was the only one it had").is_false()


# #1230: the friendly-fire notch. The line DOWNS the squadmate here rather than killing it -- its HP is
# set off what the line really deals, read through a resolve, so the fixture's scaling stays unpinned.
func _line_that_downs_the_ally(board: Dictionary) -> Dictionary:
	var s := _line_through(board, 99)
	var attacker: Unit = s.attacker
	var ally: Unit = s.ally
	attacker.active_attack = s.line
	var aim := AttackAction.declare(attacker, attacker.movement.cell, Vector2i(1, 0))
	attacker.active_attack = null
	var one: Array[BaseAction] = [aim]
	var dealt := 0
	for a in board.squad_manager.resolve_hypothetical(attacker.squad, one, _ctx(board)).attacks:
		if a.target == ally and a.resolved != null:
			dealt += a.resolved.damage
	ally.set_current_hp(maxi(1, dealt - 2))
	var plan: ResolvedPlan = board.squad_manager.resolve_hypothetical(attacker.squad, one, _ctx(board))
	assert_int(PlanResolver.projected_lifecycle(ally, plan.hypo)).override_failure_message(
			"fixture: the line must DOWN the squadmate, not kill it or leave it standing") \
		.is_equal(Unit.LifecycleState.DOWNED)
	board.squad_manager.resolve_plan(attacker.squad, _ctx(board))
	return s


func test_a_swing_that_would_down_our_own_is_refused_at_the_default_notch() -> void:
	var board := _build_board()
	var s := _line_that_downs_the_ally(board)
	var attacker: Unit = s.attacker
	AITactics.queue_main_action(attacker, _ctx(board), board.squad_manager, ATTACK_ONLY)
	var aim := _queued_attack(attacker)
	assert_object(aim).is_not_null()
	if aim == null:
		return
	assert_object(aim.fired_attack).override_failure_message(
			"the default notch downed its own squadmate for a removal").is_same(s.clean)


func test_a_unit_that_only_refuses_kills_may_down_its_own() -> void:
	var sloppy := AIProfile.new()
	sloppy.friendly_fire = AIProfile.FriendlyFire.NEVER_KILLS
	AIProfiles.use_fixtures({"": sloppy})
	var board := _build_board()
	var s := _line_that_downs_the_ally(board)
	var attacker: Unit = s.attacker
	AITactics.queue_main_action(attacker, _ctx(board), board.squad_manager, ATTACK_ONLY)
	var aim := _queued_attack(attacker)
	assert_object(aim).is_not_null()
	if aim == null:
		return
	assert_object(aim.fired_attack).override_failure_message(
			"a unit that only refuses KILLS still refused to down its own").is_same(s.line)


# ...and it still never KILLS one: the same notch against the line that kills the squadmate outright.
func test_a_unit_that_only_refuses_kills_still_never_kills_its_own() -> void:
	var sloppy := AIProfile.new()
	sloppy.friendly_fire = AIProfile.FriendlyFire.NEVER_KILLS
	AIProfiles.use_fixtures({"": sloppy})
	var board := _build_board()
	var s := _line_through(board, 2)
	var attacker: Unit = s.attacker
	AITactics.queue_main_action(attacker, _ctx(board), board.squad_manager, ATTACK_ONLY)
	var aim := _queued_attack(attacker)
	assert_object(aim).is_not_null()
	if aim == null:
		return
	assert_object(aim.fired_attack).override_failure_message(
			"the NEVER_KILLS notch killed its own squadmate").is_same(s.clean)


# The floor reads the candidate's DEPOSITS too: a fire that melts the ice under a squadmate it never
# touched drowns them, and that is its work as surely as a blow.
#
#   x       1
#   y=0   ally (on ice)
#   y=1   A      <- aimed; the attacker stands at (0,1)
#   y=2   B (on ice)
func _fire_board(board: Dictionary, ally_on_ice: bool) -> Dictionary:
	if ally_on_ice:
		_ice(board, Vector2i(1, 0))
	_ice(board, Vector2i(1, 2))
	var attacker := _spawn(board, ENEMY, Vector2i(0, 1))
	var fire: WeaponAttackData = _weapon_of(attacker).template.main_attack
	fire.power = 40
	fire.elemental_damage_type = Elemental.Element.FIRE
	fire.targets = EquippableData.TargetMode.BOTH
	var column: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 0), Vector2i(0, 1)]
	P.stamped(fire, 1, column)
	var clean := _give_clean_shot(attacker)
	var ally := _spawn(board, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 40})
	board.squad_manager.join_squad(ally, attacker.squad)
	_spawn(board, PLAYER, Vector2i(1, 1), {Stats.Stat.MHP: 30})
	_spawn(board, PLAYER, Vector2i(1, 2), {Stats.Stat.MHP: 40})
	return {"attacker": attacker, "fire": fire, "clean": clean, "ally": ally}


func test_a_fire_whose_melt_would_drown_our_own_is_never_taken() -> void:
	var board := _build_board()
	var s := _fire_board(board, true)
	var attacker: Unit = s.attacker
	var fire: WeaponAttackData = s.fire
	var ally: Unit = s.ally
	var clean: WeaponAttackData = s.clean

	# The fixture's own claim first: the fire does drown the squadmate.
	var ctx := _ctx(board)
	board.squad_manager.active_squad = attacker.squad
	attacker.active_attack = fire
	var probe := AttackAction.declare(attacker, attacker.movement.cell, Vector2i(1, 1))
	attacker.active_attack = null
	var one: Array[BaseAction] = [probe]
	var plan: ResolvedPlan = board.squad_manager.resolve_hypothetical(attacker.squad, one, ctx)
	var drowns := false
	for sink in plan.sinks:
		drowns = drowns or sink.actor == ally
	board.squad_manager.resolve_plan(attacker.squad, ctx)
	assert_bool(drowns).override_failure_message("fixture: the fire does not melt the squadmate's ice").is_true()

	AITactics.queue_main_action(attacker, _ctx(board), board.squad_manager, ATTACK_ONLY)
	var aim := _queued_attack(attacker)
	assert_object(aim).is_not_null()
	if aim == null:
		return
	assert_object(aim.fired_attack).override_failure_message(
			"the AI melted the ice under its own squadmate").is_same(clean)


# --- Ruling 2: a mission-ending kill ranks above everything --------------------------------------

# A downed escort the mission says must survive, and a frail enemy still standing: finishing the
# body ends the mission, felling the other is a removal.
func _escort_and_frail(board: Dictionary) -> Dictionary:
	var attacker := _spawn(board, ENEMY, Vector2i(1, 1))
	var escort := _spawn(board, PLAYER, Vector2i(0, 1))
	escort.must_survive = true
	escort.force_down()
	var frail := _spawn(board, PLAYER, Vector2i(2, 1), {Stats.Stat.MHP: 2})
	return {"attacker": attacker, "escort": escort, "frail": frail}


func _protected_mission() -> MissionState:
	var mission := MissionState.new()
	mission.lose_conditions.assign([MissionRules.LoseCondition.PROTECTED_UNIT_LOST])
	return mission


func test_finishing_a_protected_body_beats_felling_a_standing_enemy() -> void:
	var board := _build_board()
	var s := _escort_and_frail(board)
	var attacker: Unit = s.attacker
	AITactics.queue_main_action(attacker, _ctx(board, _protected_mission()), board.squad_manager, ATTACK_ONLY)

	var aim := _queued_attack(attacker)
	assert_object(aim).is_not_null()
	if aim == null:
		return
	assert_that(aim.target_cell).override_failure_message(
			"the AI took a removal over the kill that ends the mission").is_equal((s.escort as Unit).movement.cell)


# The control: the same board on a mission that does not end on the escort's death -- a body loses
# head to head (#720), so the standing enemy is the pick.
func test_without_the_lose_condition_the_body_loses_as_ever() -> void:
	var board := _build_board()
	var s := _escort_and_frail(board)
	var attacker: Unit = s.attacker
	AITactics.queue_main_action(attacker, _ctx(board, MissionState.new()), board.squad_manager, ATTACK_ONLY)

	var aim := _queued_attack(attacker)
	assert_object(aim).is_not_null()
	if aim == null:
		return
	assert_that(aim.target_cell).override_failure_message(
			"fixture: without the stake the frail enemy must win, or the mission case measures nothing") \
		.is_equal((s.frail as Unit).movement.cell)


# #1230: a unit whose profile does not go for the mission kill weighs the escort as any body.
func test_a_unit_that_ignores_the_mission_kill_takes_the_removal() -> void:
	var careless := AIProfile.new()
	careless.goes_for_mission_kill = false
	AIProfiles.use_fixtures({"": careless})
	var board := _build_board()
	var s := _escort_and_frail(board)
	var attacker: Unit = s.attacker
	AITactics.queue_main_action(attacker, _ctx(board, _protected_mission()), board.squad_manager, ATTACK_ONLY)

	var aim := _queued_attack(attacker)
	assert_object(aim).is_not_null()
	if aim == null:
		return
	assert_that(aim.target_cell).override_failure_message(
			"a unit that ignores the mission kill still went for the escort").is_equal((s.frail as Unit).movement.cell)


# The control: the same fire with the squadmate on dry ground is the pick, so the case above is
# measuring the drowning and nothing else.
func test_the_same_fire_with_our_own_on_dry_ground_is_taken() -> void:
	var board := _build_board()
	var s := _fire_board(board, false)
	var attacker: Unit = s.attacker
	AITactics.queue_main_action(attacker, _ctx(board), board.squad_manager, ATTACK_ONLY)
	var aim := _queued_attack(attacker)
	assert_object(aim).is_not_null()
	if aim == null:
		return
	assert_object(aim.fired_attack).override_failure_message(
			"fixture: the fire must win when nobody of ours drowns").is_same(s.fire)


# The SEEK's top tier (#760 + ruling 2): a leader walks to the cell that finishes the escort, past a
# cell where a removal was already on offer. The approach heads for the standing enemy -- a body
# loses the engagement pick (#720) -- so only the seek can take it to the body.
#
#   x       0   1   2
#   y=0     A       F     A attacker, F frail enemy (the engagement target)
#   y=3     E             E the downed escort
func _seek_board() -> Dictionary:
	var board := _build_board(Rect2i(0, 0, 6, 6))
	var attacker := _spawn(board, ENEMY, Vector2i(0, 0))
	var frail := _spawn(board, PLAYER, Vector2i(2, 0), {Stats.Stat.MHP: 2})
	var escort := _spawn(board, PLAYER, Vector2i(0, 3))
	escort.must_survive = true
	escort.force_down()
	return {"board": board, "attacker": attacker, "frail": frail, "escort": escort}


func test_a_leader_walks_past_a_removal_to_finish_the_escort() -> void:
	var s := _seek_board()
	var board: Dictionary = s.board
	var attacker: Unit = s.attacker
	var escort: Unit = s.escort
	AIController.plan_squad(attacker.squad, _ctx(board, _protected_mission()), board.squad_manager)

	var aim := _queued_attack(attacker)
	assert_object(aim).override_failure_message("the leader queued no attack").is_not_null()
	if aim == null:
		return
	assert_that(aim.target_cell).override_failure_message(
			"the leader took the removal on offer instead of walking to end the mission").is_equal(escort.movement.cell)


func test_without_the_stake_the_leader_takes_the_removal_on_the_way() -> void:
	var s := _seek_board()
	var board: Dictionary = s.board
	var attacker: Unit = s.attacker
	AIController.plan_squad(attacker.squad, _ctx(board, MissionState.new()), board.squad_manager)

	var aim := _queued_attack(attacker)
	assert_object(aim).is_not_null()
	if aim == null:
		return
	assert_that(aim.target_cell).override_failure_message(
			"fixture: without the stake the leader must fight the frail enemy").is_equal((s.frail as Unit).movement.cell)


# #1230: and the seek's top tier goes with it -- the leader takes the removal on the way.
func test_a_leader_that_ignores_the_mission_kill_does_not_walk_to_the_escort() -> void:
	var careless := AIProfile.new()
	careless.goes_for_mission_kill = false
	AIProfiles.use_fixtures({"": careless})
	var s := _seek_board()
	var board: Dictionary = s.board
	var attacker: Unit = s.attacker
	AIController.plan_squad(attacker.squad, _ctx(board, _protected_mission()), board.squad_manager)

	var aim := _queued_attack(attacker)
	assert_object(aim).is_not_null()
	if aim == null:
		return
	assert_that(aim.target_cell).override_failure_message(
			"a leader that ignores the mission kill still walked to the escort").is_equal((s.frail as Unit).movement.cell)


# --- #1230: limbs -- above damage, below saves, both ways ------------------------------------------

func test_the_limb_term_sits_between_saves_and_damage() -> void:
	assert_bool(AIScore.of(0, 0, 0, 0, 1, 0, 0).beats(AIScore.of(0, 0, 0, 0, 0, 99, 0))) \
		.override_failure_message("a limb must outrank any amount of damage").is_true()
	assert_bool(AIScore.of(0, 0, 0, 1, 0, 0, 0).beats(AIScore.of(0, 0, 0, 0, 9, 0, 0))) \
		.override_failure_message("a save must outrank any number of limbs").is_true()


# Take every limb off a unit, through the door a big blow uses.
func _limbless(unit: Unit) -> void:
	while unit.unit_instance.sever_next_limb():
		pass


func _hit_on(board: Dictionary, attacker: Unit, victim: Unit) -> ResolvedOutcome:
	var one: Array[BaseAction] = [H.stamped_attack(attacker, victim)]
	for a in board.squad_manager.resolve_hypothetical(attacker.squad, one, _ctx(board)).attacks:
		if a.target == victim and a.resolved != null:
			return a.resolved
	return null


# A big hit either side of the attacker: the LIMBLESS one stands first in board order, so with no limb
# term the tie falls to it. Every number comes off the limb threshold, never typed in.
func _limb_board(board: Dictionary) -> Dictionary:
	var big := LethalityRules.LIMB_LOSS_DAMAGE
	var sturdy := {Stats.Stat.MHP: (big + 10) * 3}
	var attacker := _spawn(board, ENEMY, Vector2i(1, 1), {}, big)
	var spent := _spawn(board, PLAYER, Vector2i(0, 1), sturdy)
	spent.equipped_weapon = null   # nobody counters: the reaction ledger stays out of it
	_limbless(spent)
	var whole := _spawn(board, PLAYER, Vector2i(2, 1), sturdy)
	whole.equipped_weapon = null
	var on_whole := _hit_on(board, attacker, whole)
	var on_spent := _hit_on(board, attacker, spent)
	assert_bool(on_whole != null and on_whole.severed_limb >= 0).override_failure_message(
			"fixture: the hit on the whole target must take a limb").is_true()
	assert_bool(on_spent != null and on_spent.severed_limb < 0).override_failure_message(
			"fixture: the limbless target has no limb to take").is_true()
	assert_bool(on_spent != null and on_whole != null and on_spent.damage >= on_whole.damage) \
		.override_failure_message("fixture: the limbless target must not be the cheaper hit, or damage decides").is_true()
	board.squad_manager.resolve_plan(attacker.squad, _ctx(board))
	return {"attacker": attacker, "spent": spent, "whole": whole}


func test_a_hit_that_takes_a_limb_beats_the_same_hit_that_cannot() -> void:
	var board := _build_board()
	var s := _limb_board(board)
	var attacker: Unit = s.attacker
	AITactics.queue_main_action(attacker, _ctx(board), board.squad_manager, ATTACK_ONLY)
	var aim := _queued_attack(attacker)
	assert_object(aim).is_not_null()
	if aim == null:
		return
	assert_that(aim.target_cell).override_failure_message(
			"the AI passed up the hit that takes a limb").is_equal((s.whole as Unit).movement.cell)


func test_a_unit_that_does_not_value_limbs_lets_the_order_decide() -> void:
	var blind := AIProfile.new()
	blind.values_limbs = false
	AIProfiles.use_fixtures({"": blind})
	var board := _build_board()
	var s := _limb_board(board)
	var attacker: Unit = s.attacker
	AITactics.queue_main_action(attacker, _ctx(board), board.squad_manager, ATTACK_ONLY)
	var aim := _queued_attack(attacker)
	assert_object(aim).is_not_null()
	if aim == null:
		return
	assert_that(aim.target_cell).override_failure_message(
			"a unit that does not value limbs still went for the limb").is_equal((s.spent as Unit).movement.cell)


# Both ways (dev, 2026-10-05): a counter that takes one of OUR limbs counts against the plan.
func test_a_counter_that_takes_one_of_our_limbs_counts_against_the_plan() -> void:
	var board := _build_board()
	var big := LethalityRules.LIMB_LOSS_DAMAGE
	var sturdy := {Stats.Stat.MHP: (big + 10) * 3}
	var attacker := _spawn(board, ENEMY, Vector2i(1, 1), sturdy)
	var defender := _spawn(board, PLAYER, Vector2i(2, 1), sturdy, big)
	var swing: Array[BaseAction] = [H.stamped_attack(attacker, defender)]
	var plan: ResolvedPlan = board.squad_manager.resolve_hypothetical(attacker.squad, swing, _ctx(board))
	var takes_ours := false
	var takes_theirs := false
	for c in plan.counters:
		takes_ours = takes_ours or (c.target == attacker and c.resolved != null and c.resolved.severed_limb >= 0)
	for a in plan.attacks:
		takes_theirs = takes_theirs or (a.target == defender and a.resolved != null and a.resolved.severed_limb >= 0)
	assert_bool(takes_ours and not takes_theirs).override_failure_message(
			"fixture: only the counter may take a limb").is_true()

	assert_int(AITactics._score_plan(ENEMY, plan, null, AIProfile.new()).limbs).is_equal(-1)
	var blind := AIProfile.new()
	blind.values_limbs = false
	assert_int(AITactics._score_plan(ENEMY, plan, null, blind).limbs).is_equal(0)


# A big hit that sets a Crisis off still takes the limb (#1174), and a unit that sees both counts the
# limb and no removal.
func test_a_hit_that_sets_off_crisis_still_counts_its_limb() -> void:
	var board := _build_board()
	var big := LethalityRules.LIMB_LOSS_DAMAGE
	var attacker := _spawn(board, ENEMY, Vector2i(1, 1), {}, big)
	var berserker := _spawn(board, PLAYER, Vector2i(2, 1), {Stats.Stat.MHP: 99})
	berserker.equipped_weapon = null
	berserker.unit_instance.jobs.append("berserker")
	assert_bool(berserker.has_live_ability(Abilities.Id.CRISIS)).override_failure_message(
			"fixture: the Berserker job did not arm Crisis").is_true()
	var probe := _hit_on(board, attacker, berserker)
	berserker.set_current_hp(probe.damage)   # the hit fells it exactly, so the gambit fires
	var swing: Array[BaseAction] = [H.stamped_attack(attacker, berserker)]
	var plan: ResolvedPlan = board.squad_manager.resolve_hypothetical(attacker.squad, swing, _ctx(board))
	var row: ResolvedOutcome = null
	for a in plan.attacks:
		if a.target == berserker:
			row = a.resolved
	assert_bool(row != null and row.lethality == ResolvedOutcome.Lethality.CRISIS and row.severed_limb >= 0) \
		.override_failure_message("fixture: the hit must set Crisis off AND take a limb").is_true()

	var score := AITactics._score_plan(ENEMY, plan, null, AIProfile.new())
	assert_int(score.limbs).is_equal(1)
	assert_int(score.removals).is_equal(0)
