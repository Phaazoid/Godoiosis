# #72 slice 2: the in-battle attack-selection seam for multi-attack weapons, mirroring
# tests/runes/test_rune_firing.gd's B2/counter coverage but for WeaponAttackData. Covers:
# get_selectable_attacks (the pick-menu list), get_fired_attack (live pick, else main),
# the counter-always-uses-main guarantee (ruling #72/4) even with a live alt pick, the
# hits_allies asymmetry (reflects the live pick, NOT locked to main), and full resolution
# through PlanResolver/SquadManager for an EXTRA attack (not just main).
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

func _attack(power: int, can_counter: bool = true, hits_allies: bool = false) -> WeaponAttackData:
	var a := WeaponAttackData.new()
	a.display_name = "atk"
	a.power = power
	a.can_counter = can_counter
	a.hits_allies = hits_allies
	return a

# main = weak stab (power 1, no splash); extra = strong spring (power 9, splashes allies) —
# a Springspear-shaped fixture (#73) without depending on that unbuilt content.
func _spring_template() -> WeaponData:
	var t := WeaponData.new()
	t.main_attack = _attack(1, true, false)
	t.extra_attacks = [_attack(9, false, true)]
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.scaling_blend = {Stats.Stat.STR: 100}
	return t

# Bare unit, no squad — for the pure unit-level selection/gate helpers below (mirrors
# test_weapon_instance_fitting.gd's _wielder, which needs no squad either).
func _wielder(template: WeaponData) -> Unit:
	var unit := H.spawn_unit(self, PLAYER, Vector2i(0, 0), {}, false)
	unit.equipped_weapon = WeaponInstance.make(template)
	return unit

# Squad-wrapped unit — required by anything that reaches PlanResolver, since its per-target
# hypothetical calls get_projected_destination(), which reads `squad` directly (Unit.gd:354-358).
func _squadded_wielder(template: WeaponData, faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit := H.spawn_solo(self, _sm, faction, cell, {}, false)
	unit.equipped_weapon = WeaponInstance.make(template)
	return unit

class _StubBoard extends BoardContext:
	func _init(g: TileMapLayer, u: Array[Unit], m: SquadManager) -> void:
		super(g, u, m)

# --- selection surface ---

func test_get_selectable_attacks_lists_main_then_extras() -> void:
	var t := _spring_template()
	var unit := _wielder(t)
	assert_array(unit.get_selectable_attacks()).contains_exactly([t.main_attack, t.extra_attacks[0]])

func test_get_fired_attack_defaults_to_main_when_nothing_picked() -> void:
	var t := _spring_template()
	var unit := _wielder(t)
	assert_object(unit.get_fired_attack()).is_same(t.main_attack)

func test_get_fired_attack_returns_the_live_pick_when_set() -> void:
	var t := _spring_template()
	var unit := _wielder(t)
	unit.active_attack = t.extra_attacks[0]
	assert_object(unit.get_fired_attack()).is_same(t.extra_attacks[0])

# --- ruling #72/4: counters ALWAYS use main, even with a live alt pick ---

func test_get_counter_attack_stays_main_even_with_a_live_alt_pick() -> void:
	var t := _spring_template()
	var unit := _wielder(t)
	unit.active_attack = t.extra_attacks[0]   # simulates having last aimed with the extra
	assert_object(unit.get_counter_attack()).is_same(t.main_attack)

func test_attack_source_can_counter_reads_main_not_the_live_pick() -> void:
	var t := _spring_template()
	t.main_attack.can_counter = false   # main can't counter
	var unit := _wielder(t)
	unit.active_attack = t.extra_attacks[0]   # the extra CAN counter, but must never be consulted
	assert_bool(unit.attack_source_can_counter()).is_false()

# --- hits_allies asymmetry: reflects the LIVE pick, not locked to main ---

func test_attack_source_hits_allies_reflects_the_live_pick() -> void:
	var t := _spring_template()   # main hits_allies=false, extra hits_allies=true
	var unit := _wielder(t)
	assert_bool(unit.attack_source_hits_allies()).is_false()
	unit.active_attack = t.extra_attacks[0]
	assert_bool(unit.attack_source_hits_allies()).is_true()

# --- end-to-end: PlanResolver resolves an EXTRA attack, not just main ---

func test_extra_attack_resolves_through_plan_resolver() -> void:
	var t := _spring_template()
	var attacker := _squadded_wielder(t, PLAYER, Vector2i(0, 0))
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))

	var atk := AttackAction.create(attacker, attacker.movement.cell, foe, Vector2i(1, 0))
	atk.fired_attack = t.extra_attacks[0]   # power 9

	var plan := ResolvedPlan.new()
	plan.attacks.append(atk)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)

	assert_int(atk.resolved.damage).is_equal(14)   # power 9 + STR 5 (baseline_stats' TEST_TUNING default) — the extra's power, not main's

# Full SquadManager integration: the attacker declares with a live-picked EXTRA attack, and the
# counter it provokes fires the counterer's own MAIN — the two units' selections never cross,
# and the counter-always-main guarantee (ruling #72/4) holds through the real resolve_plan path,
# not just the unit-level helper. Mirrors test_rune_wielder_counters_with_its_carving (weapon side).
func test_declared_extra_attack_and_provoked_counter_each_use_their_own_selection() -> void:
	var attacker_template := _spring_template()
	var attacker := _squadded_wielder(attacker_template, PLAYER, Vector2i(0, 0))
	var counterer_template := _spring_template()
	var counterer := _squadded_wielder(counterer_template, ENEMY, Vector2i(1, 0))
	_sm.active_squad = attacker.squad

	attacker.active_attack = attacker_template.extra_attacks[0]   # the attacker's live pick
	var aim := AttackAction.create(attacker, attacker.movement.cell, counterer, Vector2i(1, 0))
	aim.fired_attack = attacker.get_fired_attack()
	attacker.squad._queue_action(aim)

	var units: Array[Unit] = [attacker, counterer]
	var board := _StubBoard.new(_sm.grid, units, _sm)
	var plan := _sm.resolve_plan(attacker.squad, board)

	assert_int(plan.attacks.size()).is_equal(1)
	assert_object(plan.attacks[0].fired_attack).is_same(attacker_template.extra_attacks[0])
	assert_int(plan.counters.size()).is_equal(1)
	assert_object(plan.counters[0].fired_attack).is_same(counterer_template.main_attack)
