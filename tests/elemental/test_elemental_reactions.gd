# Elemental stage of the resolver (docs/design/elemental-system.md E1-E8). Proves the
# v1 slice -- SHOCK x WET -- in code with INJECTED reactions (no .tres needed), so the
# logic is verified independently of authored content. PlanResolver.resolve() takes a
# reactions list precisely so these tests can supply their own deterministically.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# --- in-code reactions ---

func _water_sets_wet() -> ElementReaction:
	var r := ElementReaction.new()
	r.incoming_element = Elemental.Element.WATER
	r.required_state = Elemental.State.NONE          # setup: fires on the element alone
	var adds: Array[Elemental.State] = [Elemental.State.WET]
	r.add_states = adds
	return r

func _shock_electrocute(bonus: int = 5) -> ElementReaction:
	var r := ElementReaction.new()
	r.incoming_element = Elemental.Element.SHOCK
	r.required_state = Elemental.State.WET
	r.damage_bonus = bonus
	var removes: Array[Elemental.State] = [Elemental.State.WET]
	r.remove_states = removes
	r.popup = "Electrocuted!"
	return r

func _attack(attacker: Unit, target: Unit) -> AttackAction:
	return AttackAction.create(attacker, attacker.movement.cell, target, target.movement.cell)

# --- E1/E3/E4: WATER sets WET, the next SHOCK sees it and electrocutes ---

func test_water_then_shock_electrocutes() -> void:
	var alch := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {"STR": 0}, true, 4)
	var mech := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {"STR": 0}, true, 4)
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), {"MHP": 50})
	alch.equipped_weapon.elemental_damage_type = Elemental.Element.WATER
	mech.equipped_weapon.elemental_damage_type = Elemental.Element.SHOCK

	var water := _attack(alch, target)
	var shock := _attack(mech, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(water)
	plan.attacks.append(shock)

	var reactions: Array[ElementReaction] = [_water_sets_wet(), _shock_electrocute(5)]
	PlanResolver.resolve(plan, reactions)

	assert_int(water.resolved.damage).is_equal(4)                                   # base only
	assert_bool(water.resolved.states_added.has(Elemental.State.WET)).is_true()     # setup
	assert_int(shock.resolved.damage).is_equal(9)                                   # 4 + 5 (saw WET)
	assert_bool(shock.resolved.states_removed.has(Elemental.State.WET)).is_true()   # consumed
	assert_str(shock.resolved.popups[0]).is_equal("Electrocuted!")

# --- E6/R6: reordering the combo changes the outcome ---

func test_order_is_the_lever() -> void:
	var alch := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {"STR": 0}, true, 4)
	var mech := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {"STR": 0}, true, 4)
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), {"MHP": 50})
	alch.equipped_weapon.elemental_damage_type = Elemental.Element.WATER
	mech.equipped_weapon.elemental_damage_type = Elemental.Element.SHOCK

	var shock := _attack(mech, target)
	var water := _attack(alch, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(shock)   # SHOCK first -- target not WET yet
	plan.attacks.append(water)   # WATER too late

	var reactions: Array[ElementReaction] = [_water_sets_wet(), _shock_electrocute(5)]
	PlanResolver.resolve(plan, reactions)

	assert_int(shock.resolved.damage).is_equal(4)                                    # no bonus
	assert_bool(shock.resolved.states_removed.has(Elemental.State.WET)).is_false()

# --- R2/E2: pure -- live unit state is never touched at plan time ---

func test_resolver_leaves_live_state_untouched() -> void:
	var alch := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {"STR": 0}, true, 4)
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {"MHP": 50})
	alch.equipped_weapon.elemental_damage_type = Elemental.Element.WATER

	var water := _attack(alch, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(water)
	var reactions: Array[ElementReaction] = [_water_sets_wet()]

	assert_bool(target.element_states.is_empty()).is_true()
	PlanResolver.resolve(plan, reactions)
	assert_bool(target.element_states.is_empty()).is_true()                          # untouched (R2)
	assert_bool(water.resolved.states_added.has(Elemental.State.WET)).is_true()      # but recorded

# --- R2/E2: same plan -> same result ---

func test_determinism_same_plan_same_result() -> void:
	var mech := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {"STR": 0}, true, 4)
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {"MHP": 50})
	mech.equipped_weapon.elemental_damage_type = Elemental.Element.SHOCK
	target.add_element_state(Elemental.State.WET)

	var reactions: Array[ElementReaction] = [_shock_electrocute(5)]

	var s1 := _attack(mech, target)
	var p1 := ResolvedPlan.new()
	p1.attacks.append(s1)
	PlanResolver.resolve(p1, reactions)

	var s2 := _attack(mech, target)
	var p2 := ResolvedPlan.new()
	p2.attacks.append(s2)
	PlanResolver.resolve(p2, reactions)

	assert_int(s1.resolved.damage).is_equal(s2.resolved.damage)
	assert_int(s1.resolved.damage).is_equal(9)

# --- E8: every reaction matching the pre-hit snapshot fires; mults multiply, bonuses sum ---

func test_e8_all_matching_reactions_compose() -> void:
	var mech := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {"STR": 0}, true, 4)
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {"MHP": 99})
	mech.equipped_weapon.elemental_damage_type = Elemental.Element.SHOCK
	target.add_element_state(Elemental.State.WET)

	var r_mult := ElementReaction.new()
	r_mult.incoming_element = Elemental.Element.SHOCK
	r_mult.required_state = Elemental.State.WET
	r_mult.damage_mult = 2.0

	var r_bonus := ElementReaction.new()
	r_bonus.incoming_element = Elemental.Element.SHOCK
	r_bonus.required_state = Elemental.State.WET
	r_bonus.damage_bonus = 3

	var reactions: Array[ElementReaction] = [r_mult, r_bonus]
	var shock := _attack(mech, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(shock)
	PlanResolver.resolve(plan, reactions)

	assert_int(shock.resolved.damage).is_equal(11)   # round(4 * 2.0 + 3)

# --- E7: counters are in the chain -- they carry elements and can complete a combo ---

func test_e7_counter_can_complete_a_combo() -> void:
	var p := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {"STR": 0}, true, 4)
	var e := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {"STR": 0}, true, 4)
	e.equipped_weapon.elemental_damage_type = Elemental.Element.SHOCK
	p.add_element_state(Elemental.State.WET)        # the counter's target is already WET

	var attack := _attack(p, e)
	p.squad._queue_action(attack)

	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	plan.counters = _sm.calculate_counterattacks_for_squad(p.squad)
	var reactions: Array[ElementReaction] = [_shock_electrocute(5)]
	PlanResolver.resolve(plan, reactions)

	assert_int(plan.counters.size()).is_greater(0)
	var counter := plan.counters[0]
	assert_object(counter.target).is_same(p)                                          # e counters p
	assert_int(counter.resolved.damage).is_equal(9)                                   # SHOCK x WET (4 + 5)
	assert_bool(counter.resolved.states_removed.has(Elemental.State.WET)).is_true()

# --- E5: reactions/counters are derived every pass, never stored as player orders ---

func test_e5_resolution_does_not_mutate_the_queue() -> void:
	var p := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {"STR": 0}, true, 4)
	var e := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {"STR": 0}, true, 4)
	var attack := _attack(p, e)
	p.squad._queue_action(attack)

	var before := p.squad.action_queue.size()
	_sm.resolve_plan(p.squad)
	_sm.resolve_plan(p.squad)
	assert_int(p.squad.action_queue.size()).is_equal(before)   # only the player's order remains
