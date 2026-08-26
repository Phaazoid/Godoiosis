# Rescue re-validation (SquadPlanValidator._revalidate_rescues, #33). A queued rescue must
# stay adjacent to a STILL-downed ally; if a re-planned move carries the rescuer out of range,
# or the target is picked up / killed first, the rescue invalidates — and the existing
# invalid-action gate then blocks execution. Mirrors the AoE victim re-derivation debt.
#
# Validation is pure logic (no overlay redraw), so it's safe in this node harness.
#
# EXTENDED 2026-08-08 (#126). A downed body can now be SHOVED by a damageless attack, which makes
# "where is the target?" a question with two different answers mid-plan. Three sites used to read the
# live one — the candidate query, the validator's adjacency test, and execute() (which had no test at
# all) — and each is wrong in the same direction: it refuses the rescue aimed where the body lands and
# accepts the one aimed at the cell it just cleared. The shove cases below drive a REAL resolve, because
# that is what publishes the projected knockback; hand-stamping it would skip the thing being tested.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# Spawn an ally and put it in the DOWNED state (exactly-lethal hit, zero overkill -> down).
func _downed_ally(cell: Vector2i) -> Unit:
	var ally := H.spawn_solo(self, _sm, PLAYER, cell)
	ally.take_damage(ally.get_current_hp())
	assert_bool(ally.is_downed()).is_true()
	return ally

func _queue_rescue(rescuer: Unit, ally: Unit) -> RescueAction:
	var rescue := RescueAction.new()
	# The landing every case here wants is the body's own cell -- these are all DRY-GROUND rescues,
	# so #116's haul never fires and the stamp is what rescue_landings itself would answer.
	rescue.init(rescuer, ally, ally.get_projected_destination())
	rescuer.squad._queue_action(rescue)
	return rescue

# Adjacent to a downed ally -> the rescue validates.
func test_rescue_is_valid_when_adjacent_to_a_downed_ally() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := _downed_ally(Vector2i(1, 0))
	var rescue := _queue_rescue(rescuer, ally)

	_sm.validate_squad_plan(rescuer.squad)

	assert_bool(rescue.is_valid).is_true()

# A move that carries the rescuer out of range invalidates the rescue: validation reads the
# PROJECTED (post-move) position, so the body is no longer adjacent.
func test_rescue_invalidated_when_a_move_leaves_the_ally() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := _downed_ally(Vector2i(1, 0))
	var rescue := _queue_rescue(rescuer, ally)

	var move := MoveAction.new()
	var path: Array[Vector2i] = [rescuer.movement.cell, Vector2i(6, 6)]
	move.init(rescuer, path, null)
	rescuer.squad._queue_action(move)

	_sm.validate_squad_plan(rescuer.squad)

	assert_bool(rescue.is_valid).is_false()

# If the target is picked up first (no longer downed), the queued rescue invalidates. PLAN-ARMED
# since #124: the lifecycle half of rescue validity moved out of the fixed-point loop beside the
# attack whiff clause, so it only runs when a resolve is handed in -- which is what every in-game
# validate does (game.refresh_action_queue).
func test_rescue_invalidated_when_target_is_no_longer_down() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := _downed_ally(Vector2i(1, 0))
	var rescue := _queue_rescue(rescuer, ally)

	ally.revive()
	assert_bool(ally.is_downed()).is_false()

	var plan: ResolvedPlan = _sm.resolve_plan(rescuer.squad, _sm.board_source.call())
	_sm.validate_squad_plan(rescuer.squad, plan)

	assert_bool(rescue.is_valid).is_false()

# ---- #126: the body moves, and the rescue has to follow it ----

# A Gust: damageless, so it repositions a downed unit instead of finishing it, and ally-hitting, so
# the volley gather picks a friendly body up at all. No pattern -> Reach's adjacency fallback affects
# exactly the aimed cell.
func _gust(distance: int) -> TransmutationData:
	var carving := TransmutationData.new()
	carving.sigils.assign([Elemental.Element.AIR])
	carving.deals_no_damage = true
	carving.hits_allies = true
	carving.knockback = distance
	return carving

# Shove `ally` two cells directly away from a caster standing at the origin, through the real
# resolve that publishes the landing cell. Returns once the projection is live.
func _shove_the_body(ally: Unit) -> void:
	var caster := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var aim := AttackAction.create(caster, caster.movement.cell, null, ally.movement.cell)
	aim.fired_attack = _gust(2)
	caster.squad._queue_action(aim)
	_sm.resolve_plan(caster.squad, _sm.board_source.call())

func test_a_rescue_follows_a_shoved_body() -> void:
	var ally := _downed_ally(Vector2i(1, 0))
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(4, 0))   # beside the LANDING cell (3, 0)
	var rescue := _queue_rescue(rescuer, ally)

	_shove_the_body(ally)
	_sm.validate_squad_plan(rescuer.squad)

	assert_vector(ally.get_projected_destination()).is_equal(Vector2i(3, 0))
	assert_bool(rescue.is_valid).is_true()

func test_a_rescue_aimed_at_the_cell_the_body_vacates_is_refused() -> void:
	var ally := _downed_ally(Vector2i(1, 0))
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 1))   # beside where the body STARTED
	var rescue := _queue_rescue(rescuer, ally)

	_shove_the_body(ally)
	_sm.validate_squad_plan(rescuer.squad)

	assert_bool(rescue.is_valid).is_false()

# The same rule one layer earlier: the menu must OFFER the body where it will land, or the legal
# rescue can never be authored in the first place (queue_action's gate reads the same validity).
func test_the_candidate_query_offers_the_body_at_its_landing_cell() -> void:
	var ally := _downed_ally(Vector2i(1, 0))
	var by_landing := H.spawn_solo(self, _sm, PLAYER, Vector2i(4, 0))
	var by_vacated := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 1))

	_shove_the_body(ally)

	assert_array(RulesService.adjacent_downed_allies(by_landing, _sm.board_source.call())).contains([ally])
	assert_array(RulesService.adjacent_downed_allies(by_vacated, _sm.board_source.call())).is_empty()

# execute()'s own guard — a Law #2 backstop, and the only one there is once the pass is running.
# Before #126 this revived at any range, because the validator's stamp was the sole check and it is
# computed before a single order runs.
func test_rescue_does_not_revive_a_body_it_is_no_longer_beside() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := _downed_ally(Vector2i(3, 0))
	var rescue := _queue_rescue(rescuer, ally)

	rescue.execute()

	assert_bool(ally.is_downed()).is_true()

func test_rescue_revives_a_body_it_is_still_beside() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := _downed_ally(Vector2i(1, 0))
	var rescue := _queue_rescue(rescuer, ally)

	rescue.execute()

	assert_bool(ally.is_downed()).is_false()

# ---- #124: rescuing a PREDICTED down -- the target is still standing when the order is authored ----

# An ally one hit from dropping, plus a squad (attacker + rescuer) whose plan delivers that hit.
# The attacker's exact-lethality doesn't matter: the victim sits at 1 HP, so any damaging hit is a
# would-be-down and the fixture weapon's overkill (power 3 - 1 = 2) is far under the ceiling.
func _bloodied_ally(cell: Vector2i, overrides: Dictionary = {}) -> Unit:
	var ally := H.spawn_solo(self, _sm, PLAYER, cell, overrides)
	ally.take_damage(ally.get_current_hp() - 1)
	assert_bool(ally.is_active()).override_failure_message("fixture downed the ally too early").is_true()
	return ally

# Queue the attacker's friendly-fire aim at the victim's cell, stamped the way declare() stamps.
func _lethal_aim(attacker: Unit, victim: Unit) -> AttackAction:
	(attacker.equipped_weapon as WeaponInstance).template.main_attack.hits_allies = true
	var aim := AttackAction.create(attacker, attacker.movement.cell, null, victim.movement.cell)
	aim.fired_attack = attacker.get_fired_attack()
	attacker.squad._queue_action(aim)
	return aim

func test_a_rescue_against_a_predicted_down_validates() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(3, 0))
	_sm.join_squad(rescuer, attacker.squad)
	var victim := _bloodied_ally(Vector2i(2, 0))

	_lethal_aim(attacker, victim)
	var rescue := _queue_rescue(rescuer, victim)
	var plan: ResolvedPlan = _sm.resolve_plan(attacker.squad, _sm.board_source.call())

	assert_that(PlanResolver.projected_lifecycle(victim, plan.hypo)) \
		.override_failure_message("fixture's aim does not predict a DOWN") \
		.is_equal(Unit.LifecycleState.DOWNED)

	_sm.validate_squad_plan(attacker.squad, plan)

	assert_bool(rescue.is_valid) \
		.override_failure_message("a rescue against a predicted down must validate (#124)").is_true()

# The propagation half of #124: cancel the attack and the down is no longer predicted, so the
# rescue FALLS into red -- still queued, never deleted (strict queueing's one-way validity).
func test_cancelling_the_attack_reddens_the_rescue_but_keeps_it_queued() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(3, 0))
	_sm.join_squad(rescuer, attacker.squad)
	var victim := _bloodied_ally(Vector2i(2, 0))

	var aim := _lethal_aim(attacker, victim)
	var rescue := _queue_rescue(rescuer, victim)
	_sm.validate_squad_plan(attacker.squad, _sm.resolve_plan(attacker.squad, _sm.board_source.call()))
	assert_bool(rescue.is_valid).is_true()

	attacker.squad._remove_action(aim)
	_sm.validate_squad_plan(attacker.squad, _sm.resolve_plan(attacker.squad, _sm.board_source.call()))

	assert_bool(rescue.is_valid) \
		.override_failure_message("the rescue's precondition is gone and the row stayed green").is_false()
	assert_bool(attacker.squad.action_queue.has(rescue)) \
		.override_failure_message("an invalidated order must stay queued in red, never be deleted").is_true()

# The candidate list one layer earlier: with the plan, a STANDING ally the pass will drop is
# offered; without one (the AI's builder, a bare fixture), the live rule holds and it is not.
func test_the_candidate_query_offers_a_predicted_down_ally() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(3, 0))
	_sm.join_squad(rescuer, attacker.squad)
	var victim := _bloodied_ally(Vector2i(2, 0))

	_lethal_aim(attacker, victim)
	var plan: ResolvedPlan = _sm.resolve_plan(attacker.squad, _sm.board_source.call())

	assert_array(RulesService.adjacent_downed_allies(rescuer, _sm.board_source.call(), plan)).contains([victim])
	assert_array(RulesService.adjacent_downed_allies(rescuer, _sm.board_source.call())).is_empty()

# The #158 successor to the old interim clause: a Crisis-ARMED full-Will ally predicts CRISIS --
# it stands back up, so it was never going to be a body -- and falls out of candidacy through the
# ordinary DOWNED filter, no special case anywhere. (Until #158, an is_crisis_eligible carve-out
# in is_rescueable did this job for the live prompt.)
func test_a_crisis_armed_ally_is_not_offered_because_it_stands_back_up() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(3, 0))
	_sm.join_squad(rescuer, attacker.squad)
	var victim := _bloodied_ally(Vector2i(2, 0), {Stats.Stat.WIL: 20})
	victim.unit_instance.jobs.append("berserker")   # arms Abilities.Id.CRISIS via the job pool

	_lethal_aim(attacker, victim)
	var plan: ResolvedPlan = _sm.resolve_plan(attacker.squad, _sm.board_source.call())

	assert_that(PlanResolver.projected_lifecycle(victim, plan.hypo)).is_equal(Unit.LifecycleState.ACTIVE)
	assert_bool(RulesService.is_rescueable(victim, plan)).is_false()
	assert_array(RulesService.adjacent_downed_allies(rescuer, _sm.board_source.call(), plan)).is_empty()
