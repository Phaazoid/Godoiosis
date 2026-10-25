# A paired state threads through the pass whole (#1480 stage 5): a state that carries a StatEffect
# (CHILLED's DEX, SMOKED's COH) lands on the pass's copy of the body with its effect, through the doors
# the live body uses, so every later read in the pass sees the body execution will have. Each case
# resolves, executes, and asserts the copy and the live body agree.
#
# The reactions are built here rather than read off the catalog, and every expectation is derived from
# Elemental.paired_stat_mods, so retuning the chill reds nothing.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const CHILLED := Elemental.State.CHILLED
const DEX := Stats.Stat.DEX

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _chill_shift() -> int:
	return int(Elemental.paired_stat_mods(CHILLED).get(DEX, 0))


func _attacker(element: Elemental.Element, cell: Vector2i) -> Unit:
	var a := H.spawn_solo(self, _sm, PLAYER, cell, {Stats.Stat.STR: 0}, true, 2)
	(a.get_equipped_weapon() as WeaponInstance).template.main_attack.elemental_damage_type = element
	return a


func _target(cell: Vector2i) -> Unit:
	return H.spawn_solo(self, _sm, ENEMY, cell, {Stats.Stat.MHP: 60, Stats.Stat.DEX: 6,
			Stats.Stat.CON: Stats.BAND_MID_MAX}, true, 3)


func _ice_chills() -> ElementalReaction:
	var r := ElementalReaction.new()
	r.incoming_element = Elemental.Element.ICE
	r.add_states.assign([CHILLED])
	return r


func _fire_thaws() -> ElementalReaction:
	var r := ElementalReaction.new()
	r.incoming_element = Elemental.Element.FIRE
	r.required_state = CHILLED
	r.remove_states.assign([CHILLED])
	return r


func _resolve(plan: ResolvedPlan, reactions: Array[ElementalReaction]) -> ResolvedPlan:
	PlanResolver.resolve(plan, reactions)
	return plan


func _assert_chill_moves_dex() -> void:
	assert_int(_chill_shift()).override_failure_message("fixture: CHILLED carries no DEX shift").is_not_equal(0)


# ==============================================================================

# The chill's DEX lands on the copy with the state, and the live body is untouched until playback.
func test_a_chill_lands_its_dex_on_the_pass_copy() -> void:
	_assert_chill_moves_dex()
	var target := _target(Vector2i(1, 0))
	var dex := target.get_effective_stat(DEX)
	var hit := H.stamped_attack(_attacker(Elemental.Element.ICE, Vector2i(0, 0)), target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(hit)
	var reactions: Array[ElementalReaction] = [_ice_chills()]
	_resolve(plan, reactions)
	assert_bool(hit.resolved.states_added.has(CHILLED)).override_failure_message("fixture: the hit chilled nothing").is_true()

	var copy := PlanResolver.state_of(target, plan.hypo)
	assert_int(copy.get_effective_stat(DEX)) \
		.override_failure_message("the pass's copy holds CHILLED without its DEX") \
		.is_equal(dex + _chill_shift())
	assert_int(target.get_effective_stat(DEX)).override_failure_message("the pass wrote the live body (R2)").is_equal(dex)

	await hit.execute()

	assert_int(target.get_effective_stat(DEX)).is_equal(copy.get_effective_stat(DEX))


# A counter by the body chilled earlier in the same pass scales off the chilled DEX, which is the
# number the live body would deal once the chill has landed.
func test_a_counter_after_a_chill_scales_off_the_chilled_dex() -> void:
	_assert_chill_moves_dex()
	var attacker := _attacker(Elemental.Element.ICE, Vector2i(0, 0))
	var target := _target(Vector2i(1, 0))
	var main: WeaponAttackData = (target.get_equipped_weapon() as WeaponInstance).template.main_attack
	var by_dex: Dictionary[Stats.Stat, int] = {DEX: 100}
	main.scaling_blend = by_dex
	var swing := H.stamped_attack(attacker, target)
	var counter := CounterAttackAction.new()
	counter.init_counter(target, attacker, target.movement.cell, swing)
	counter.fired_attack = target.get_counter_attack()
	var plan := ResolvedPlan.new()
	plan.attacks.append(swing)
	plan.counters.append(counter)
	var reactions: Array[ElementalReaction] = [_ice_chills()]
	_resolve(plan, reactions)
	assert_object(counter.resolved).override_failure_message("fixture: the counter did not resolve").is_not_null()

	await swing.execute()

	var weapon := target.get_equipped_weapon() as WeaponInstance
	assert_int(counter.resolved.base_damage) \
		.override_failure_message("the counter scaled off the DEX the chill had already taken") \
		.is_equal(weapon.base_damage(target.state, main))


# Fire on a chilled body ends the chill and gives the copy its DEX back.
func test_a_thaw_gives_the_copy_its_dex_back() -> void:
	_assert_chill_moves_dex()
	var target := _target(Vector2i(1, 0))
	var dex := target.get_effective_stat(DEX)
	target.add_element_state(CHILLED)
	assert_int(target.get_effective_stat(DEX)).override_failure_message("fixture: the live chill moved no DEX") \
		.is_equal(dex + _chill_shift())
	var hit := H.stamped_attack(_attacker(Elemental.Element.FIRE, Vector2i(0, 0)), target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(hit)
	var reactions: Array[ElementalReaction] = [_fire_thaws()]
	_resolve(plan, reactions)
	assert_bool(hit.resolved.states_removed.has(CHILLED)).override_failure_message("fixture: the hit thawed nothing").is_true()

	var copy := PlanResolver.state_of(target, plan.hypo)
	assert_int(copy.get_effective_stat(DEX)) \
		.override_failure_message("the pass's copy lost CHILLED and kept its DEX") \
		.is_equal(dex)

	await hit.execute()

	assert_int(target.get_effective_stat(DEX)).is_equal(dex)


# A chill that drops DEX under a piece's gate strips it on the copy, and the row shows the re-clamp
# the strip makes, as the live body takes it.
func test_a_chill_under_a_dex_gate_strips_on_the_copy() -> void:
	_assert_chill_moves_dex()
	assert_int(_chill_shift()).override_failure_message("fixture: the chill raises DEX; nothing to strip").is_less(0)
	var target := _target(Vector2i(1, 0))
	var plate := ArmorData.new()
	plate.stat_modifiers = {Stats.Stat.CON: 1}
	plate.stat_minimums = {DEX: target.get_body_stat(DEX)}
	target.add_item(plate)
	assert_bool(target.wear_armor(target.inventory.find(plate))) \
		.override_failure_message("fixture: the plate would not go on").is_true()
	target.set_current_hp(target.get_max_hp())
	var max_hp := target.get_max_hp()
	var hit := H.stamped_attack(_attacker(Elemental.Element.ICE, Vector2i(0, 0)), target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(hit)
	var reactions: Array[ElementalReaction] = [_ice_chills()]
	_resolve(plan, reactions)

	var copy := PlanResolver.state_of(target, plan.hypo)
	assert_object(copy.worn_armor).override_failure_message("the chill under the gate left the plate on the copy").is_null()
	assert_object(target.worn_armor).override_failure_message("the pass stripped the live body (R2)").is_same(plate)

	await hit.execute()

	assert_object(target.worn_armor).override_failure_message("fixture: the live chill stripped nothing").is_null()
	assert_int(target.get_max_hp()).override_failure_message("fixture: the strip moved no max HP").is_less(max_hp)
	assert_int(copy.get_max_hp()).is_equal(target.get_max_hp())
	assert_int(hit.resolved.target_hp_after) \
		.override_failure_message("the row showed the HP before the strip's re-clamp") \
		.is_equal(target.get_current_hp())
