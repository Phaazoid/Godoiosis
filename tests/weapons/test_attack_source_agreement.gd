# #102 regression suite — geometry and content must answer "which attack?" from the SAME source.
#
# Before the fix, Reach.* and RulesService.gather_attack_victims looked the attack up themselves via
# Unit.get_fired_attack() (the live active_attack pick), while the queued order carried its own
# frozen AttackAction.fired_attack stamp. Geometry read one, damage read the other, and a pick left
# over from a previous aim silently re-shaped stored orders and counters. Both now take the attack
# as a parameter, so each call site names its source.
#
# Every case here FAILED against the pre-fix tree (probed 2026-07-28). Keep them behavioural — they
# assert through resolve_plan, not by inspecting which function got called.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

class _StubBoard extends BoardContext:
	func _init(g: TileMapLayer, u: Array[Unit], m: SquadManager) -> void:
		super(g, u, m)

# --- fixture helpers -------------------------------------------------------

func _manhattan(r: int) -> ManhattanRangePattern:
	var p := ManhattanRangePattern.new()
	p.max_range = r
	return p

func _wide(w: int, length: int = 1) -> ForwardWidePattern:
	var p := ForwardWidePattern.new()
	p.length = length
	p.width = w
	return p

func _atk(power: int, pattern: AttackPattern, can_counter: bool = true, hits_allies: bool = false) -> WeaponAttackData:
	var a := WeaponAttackData.new()
	a.display_name = "atk"
	a.power = power
	a.attack_pattern = pattern
	a.can_counter = can_counter
	a.hits_allies = hits_allies
	return a

func _template(main: WeaponAttackData, extra: WeaponAttackData) -> WeaponData:
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.scaling_blend = {Stats.Stat.STR: 100}
	t.main_attack = main
	t.extra_attacks = [extra]
	return t

# main = melee (range 1), extra = reach (range 3) — the shape that separates counter reach
# from the attack a counter actually fires.
func _reach_template() -> WeaponData:
	return _template(_atk(1, _manhattan(1)), _atk(9, _manhattan(3)))

func _armed(faction: Team.Faction, cell: Vector2i, t: WeaponData) -> Unit:
	var unit := H.spawn_solo(self, _sm, faction, cell, {}, false)
	unit.equipped_weapon = WeaponInstance.make(t)
	return unit

# --- counter reach is judged by what the counter FIRES ---------------------

func test_a_stale_pick_does_not_grant_counter_reach() -> void:
	# The every-turn case: AIController clears active_attack only at the start of the AI's OWN
	# turn, so every enemy carries its last pick through the whole player turn. A melee unit whose
	# leftover pick is a range-3 extra must NOT counter from three tiles away with a range-1 main.
	var atk_t := _reach_template()
	var attacker := _armed(PLAYER, Vector2i(0, 0), atk_t)
	attacker.active_attack = atk_t.extra_attacks[0]

	var def_t := _reach_template()
	var counterer := _armed(ENEMY, Vector2i(3, 0), def_t)
	counterer.active_attack = def_t.extra_attacks[0]   # the stale leftover
	_sm.active_squad = attacker.squad

	attacker.squad._queue_action(AttackAction.declare(attacker, Vector2i(0, 0), Vector2i(3, 0)))

	var units: Array[Unit] = [attacker, counterer]
	var plan := _sm.resolve_plan(attacker.squad, _StubBoard.new(_sm.grid, units, _sm))
	assert_int(plan.counters.size()).is_equal(0)

func test_counters_still_fire_when_main_really_does_reach() -> void:
	# The other direction — the guard above must not have simply switched counters off. Same
	# geometry, but now the attacker is adjacent, so the range-1 main legitimately reaches.
	var atk_t := _reach_template()
	var attacker := _armed(PLAYER, Vector2i(0, 0), atk_t)
	var def_t := _reach_template()
	var counterer := _armed(ENEMY, Vector2i(1, 0), def_t)
	_sm.active_squad = attacker.squad

	attacker.squad._queue_action(AttackAction.declare(attacker, Vector2i(0, 0), Vector2i(1, 0)))

	var units: Array[Unit] = [attacker, counterer]
	var plan := _sm.resolve_plan(attacker.squad, _StubBoard.new(_sm.grid, units, _sm))
	assert_int(plan.counters.size()).is_equal(1)
	assert_object(plan.counters[0].fired_attack).is_same(def_t.main_attack)
	assert_object(plan.counters[0].target).is_same(attacker)

# --- a stored order's footprint follows its OWN stamp ----------------------

func test_stored_aim_keeps_its_own_footprint_when_the_pick_is_cleared() -> void:
	# Queue a 3-wide cleave, then clear the pick (pressing Attack, an AI turn boundary, or the
	# targeting-exit reset added by #102). The order must keep BOTH its damage and its blast.
	var t := _template(_atk(1, _wide(1)), _atk(9, _wide(3)))
	var attacker := _armed(PLAYER, Vector2i(0, 0), t)
	var foes: Array[Unit] = [
		H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {}, false),
		H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 1), {}, false),
		H.spawn_solo(self, _sm, ENEMY, Vector2i(1, -1), {}, false),
	]
	_sm.active_squad = attacker.squad

	attacker.active_attack = t.extra_attacks[0]
	attacker.squad._queue_action(AttackAction.declare(attacker, Vector2i(0, 0), Vector2i(1, 0)))

	var units: Array[Unit] = [attacker, foes[0], foes[1], foes[2]]
	var board := _StubBoard.new(_sm.grid, units, _sm)
	assert_int(_sm.resolve_plan(attacker.squad, board).attacks.size()).is_equal(3)

	attacker.active_attack = null
	var after := _sm.resolve_plan(attacker.squad, board)
	assert_object(after.attacks[0].fired_attack).is_same(t.extra_attacks[0])
	assert_int(after.attacks.size()).is_equal(3)   # the cleave still cleaves

# --- friendly fire is a property of the attack being fired ----------------

func test_a_counter_does_not_splash_allies_off_a_stale_pick() -> void:
	# The counterer's main is single-target and never splashes; its leftover pick is a wide sweep
	# that does. The counter fires main, so its own squadmate must stay out of the volley.
	var atk_t := _reach_template()
	var attacker := _armed(PLAYER, Vector2i(0, 0), atk_t)
	attacker.active_attack = atk_t.extra_attacks[0]

	var def_t := _template(_atk(1, _manhattan(1), true, false), _atk(9, _wide(3, 3), true, true))
	var counterer := _armed(ENEMY, Vector2i(3, 0), def_t)
	counterer.active_attack = def_t.extra_attacks[0]
	var bystander := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), {}, false)   # counterer's ALLY
	_sm.active_squad = attacker.squad

	attacker.squad._queue_action(AttackAction.declare(attacker, Vector2i(0, 0), Vector2i(3, 0)))

	var units: Array[Unit] = [attacker, counterer, bystander]
	var plan := _sm.resolve_plan(attacker.squad, _StubBoard.new(_sm.grid, units, _sm))
	for c in plan.counters:
		assert_object(c.target).is_not_same(bystander)

# --- the Attack menu gate needs a default that actually exists ------------

func test_can_fire_default_attack_is_false_without_a_main_attack() -> void:
	# is_attack_fireable(null) answers true (null isn't a WeaponAttackData) — the right answer to
	# "is this gated?" and the wrong one to "is there anything here?". A weapon with no main is
	# the #80 data-rot shape, and it used to open the Attack entry onto nothing.
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.scaling_blend = {Stats.Stat.STR: 100}
	var unit := H.spawn_unit(self, PLAYER, Vector2i(0, 0), {}, false)
	unit.equipped_weapon = WeaponInstance.make(t)

	assert_object(unit.equipped_weapon.default_attack(unit)).is_null()
	assert_bool(unit.can_fire_default_attack()).is_false()

# --- a null stamp means NO attack, on BOTH sides ---

func test_an_unstamped_order_resolves_as_bare_fists_not_as_main() -> void:
	# `fired_attack == null` used to mean "no attack" to Reach and "fall back to main" to
	# PlanResolver — one value, two meanings, design law #4 one level down from this issue.
	# Resolved 2026-07-28 (dev): null means no attack, and a caller wanting main says so. Both
	# sides now agree on the bare-fist answer: STR damage here, adjacency-1 in Reach.
	var t := _template(_atk(50, _manhattan(1)), _atk(9, _manhattan(3)))   # a big main to be unmistakable
	var attacker := _armed(PLAYER, Vector2i(0, 0), t)
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {}, false)

	var atk := AttackAction.create(attacker, Vector2i(0, 0), foe, Vector2i(1, 0))   # deliberately unstamped
	assert_object(atk.fired_attack).is_null()

	var plan := ResolvedPlan.new()
	plan.attacks.append(atk)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)

	# STR 5 (the fixture baseline), NOT main's 50 + 5.
	assert_int(atk.resolved.damage).is_equal(attacker.get_effective_stat(Stats.Stat.STR))
