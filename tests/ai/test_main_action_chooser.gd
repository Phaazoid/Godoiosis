# The main-action chooser (#78): probes selectable attacks through the player's own pick slot
# (active_attack), scores each aim with a throwaway resolver pass (Law #2 as forecast), and
# walks the archetype's priority list -- first buildable candidate wins. Fixture conventions
# mirror test_rune_firing.gd (runes), test_ability_chassis_live_kit.gd (live abilities), and
# test_weapon_instance_readiness.gd (sprung weapons). Grid-free: pattern-less reach is
# Manhattan 1; the one pattern used (ForwardLinePattern) is pure geometry.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const F := preload("res://tests/support/job_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const ATTACK_ONLY: Array = [BaseAction.ActionType.ATTACK]

var _sm: SquadManager
var _tank: JobData
var _tank_snap: Dictionary


func before_test() -> void:
	_sm = H.make_manager(self)
	_tank = JobCatalog.get_job("tank")
	_tank_snap = F.snapshot(_tank)


func after_test() -> void:
	F.restore(_tank, _tank_snap)


func _board(units: Array[Unit]) -> BoardContext:
	return BoardContext.new(_sm.grid, units, _sm)


func _ability(id: Abilities.Id) -> AbilityData:
	var a := AbilityData.new()
	a.id = id
	return a


func _fireball(power: int) -> TransmutationData:
	var t: TransmutationData = TransmutationData.new()
	t.power = power
	t.sigils.assign([Elemental.Element.FIRE])
	t.targets = EquippableData.TargetMode.UNIT
	return t


func _rune_alchemist(faction: Team.Faction, cell: Vector2i, carving: TransmutationData) -> Unit:
	var u: Unit = H.spawn_solo(self, _sm, faction, cell)
	u.unit_instance.aura = { Elemental.Element.FIRE: 4 }
	var affinity: Array[Elemental.Element] = [Elemental.Element.FIRE]
	u.unit_instance.affinity = affinity
	var rune: RuneData = RuneData.new()
	rune.size = RuneData.Size.MEDIUM
	rune.inscribe(carving)
	u.equipped_weapon = rune
	return u


# Expand and resolve one queued aim the way resolve_plan would, minus the reaction catalogs
# (deterministic damage, no .tres coupling). Returns the resolved volley.
func _resolve_aim(attacker: Unit, aim: AttackAction, units: Array[Unit]) -> ResolvedPlan:
	var affected: Array[Vector2i] = attacker.combat.get_affected_cells_from(aim.origin_cell, aim.target_cell)
	var victims: Array[Unit] = RulesService.gather_attack_victims(attacker, affected, _board(units))
	var plan: ResolvedPlan = ResolvedPlan.new()
	for a in AttackAction.create_volley(attacker, aim.origin_cell, aim.target_cell, victims, aim.fired_attack):
		plan.attacks.append(a)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)
	return plan


# --- the #78 fists regression ---

func test_ai_rune_attack_fires_the_carving_not_fists() -> void:
	var fireball: TransmutationData = _fireball(5)
	var alch: Unit = _rune_alchemist(ENEMY, Vector2i(0, 0), fireball)
	var victim: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), { Stats.Stat.MHP: 50 })

	var units: Array[Unit] = [alch, victim]
	assert_bool(AITactics.queue_main_action(alch, _board(units), _sm, ATTACK_ONLY)).is_true()
	var aim: AttackAction = alch.squad.action_queue[0] as AttackAction
	assert_object(aim.fired_attack).is_same(fireball)   # the declare stamp -- the actual bug

	# Aura-scaled (power 5 + fire aura 4), NOT the bare-STR punch the null fallback produced.
	var plan: ResolvedPlan = _resolve_aim(alch, aim, units)
	assert_int(plan.attacks[0].resolved.damage).is_equal(9)


func test_unarmed_falls_back_to_fists_like_the_player() -> void:
	# No weapon at all: the null pick IS the honest path (player parity -- _begin_attack with
	# no choices leaves active_attack null and punches at Manhattan 1).
	var attacker: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0), {}, false)
	var victim: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), { Stats.Stat.MHP: 50 })

	var units: Array[Unit] = [attacker, victim]
	assert_bool(AITactics.queue_main_action(attacker, _board(units), _sm, ATTACK_ONLY)).is_true()
	var aim: AttackAction = attacker.squad.action_queue[0] as AttackAction
	assert_object(aim.fired_attack).is_null()

	var plan: ResolvedPlan = _resolve_aim(attacker, aim, units)
	assert_int(plan.attacks[0].resolved.damage).is_equal(attacker.get_effective_stat(Stats.Stat.STR))


# --- attack selection (net-damage scoring, dev call 2026-07-22) ---

func test_picks_the_higher_damage_extra_over_main() -> void:
	var attacker: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	var weapon: WeaponInstance = attacker.get_equipped_weapon() as WeaponInstance
	var heavy: WeaponAttackData = WeaponAttackData.new()
	heavy.power = 8   # main is power 3; both pattern-less -> identical Manhattan-1 reach
	var extras: Array[WeaponAttackData] = [heavy]
	weapon.template.extra_attacks = extras
	var victim: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), { Stats.Stat.MHP: 50 })

	var units: Array[Unit] = [attacker, victim]
	assert_bool(AITactics.queue_main_action(attacker, _board(units), _sm, ATTACK_ONLY)).is_true()
	var aim: AttackAction = attacker.squad.action_queue[0] as AttackAction
	assert_object(aim.fired_attack).is_same(heavy)


func test_prefers_a_predicted_down_at_equal_damage() -> void:
	# Minimal state-awareness (dev call 2026-07-22): removals outrank raw damage, read from
	# the resolver's own lethality prediction -- the same math the queue previews.
	var attacker: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 1), {}, true, 6)
	var sturdy: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1), { Stats.Stat.MHP: 50 })
	var frail: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 1), { Stats.Stat.MHP: 5 })

	var units: Array[Unit] = [attacker, sturdy, frail]   # sturdy first: frail must OVERTAKE
	assert_bool(AITactics.queue_main_action(attacker, _board(units), _sm, ATTACK_ONLY)).is_true()
	var aim: AttackAction = attacker.squad.action_queue[0] as AttackAction
	assert_that(aim.target_cell).is_equal(frail.movement.cell)


func test_friendly_splash_can_veto_a_net_zero_candidate() -> void:
	# ForwardLine through own ally into the enemy: +6 enemy, -6 ally = net (0,0) -- not better
	# than doing nothing, so the chooser declines. Soft penalty, not a ban: see the clear-line
	# contrast below.
	var attacker: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	var weapon: WeaponInstance = attacker.get_equipped_weapon() as WeaponInstance
	weapon.template.main_attack.power = 6
	weapon.template.main_attack.hits_allies = true
	weapon.template.main_attack.attack_pattern = ForwardLinePattern.new()   # length 2
	var _friend: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), { Stats.Stat.MHP: 50 })
	var _victim: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0), { Stats.Stat.MHP: 50 })

	var units: Array[Unit] = [attacker, _friend, _victim]
	assert_bool(AITactics.queue_main_action(attacker, _board(units), _sm, ATTACK_ONLY)).is_false()
	assert_array(attacker.squad.action_queue).is_empty()


func test_clear_line_queues_the_same_attack() -> void:
	var attacker: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	var weapon: WeaponInstance = attacker.get_equipped_weapon() as WeaponInstance
	weapon.template.main_attack.power = 6
	weapon.template.main_attack.hits_allies = true
	weapon.template.main_attack.attack_pattern = ForwardLinePattern.new()
	var victim: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0), { Stats.Stat.MHP: 50 })

	var units: Array[Unit] = [attacker, victim]
	assert_bool(AITactics.queue_main_action(attacker, _board(units), _sm, ATTACK_ONLY)).is_true()
	var aim: AttackAction = attacker.squad.action_queue[0] as AttackAction
	assert_that(aim.target_cell).is_equal(victim.movement.cell)


# --- the priority walk + fallback builders ---

func test_sprung_weapon_falls_through_to_spring_load() -> void:
	# The #73 readiness economy meets the chooser: no fireable attack -> the SPRING_LOAD
	# candidate wins the walk. Next turn the spear is armed again -- no special-casing.
	var attacker: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	var template: WeaponData = WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.SPRINGSPEAR
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = 5
	template.main_attack.requires_readiness = true
	var spear: SpringWeaponInstance = WeaponInstance.make(template) as SpringWeaponInstance
	spear.ready = false   # sprung
	attacker.equipped_weapon = spear
	var _victim: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))

	var units: Array[Unit] = [attacker, _victim]
	var priority: Array = [BaseAction.ActionType.ATTACK, BaseAction.ActionType.SPRING_LOAD]
	assert_bool(AITactics.queue_main_action(attacker, _board(units), _sm, priority)).is_true()
	assert_int(attacker.squad.action_queue.size()).is_equal(1)
	assert_int(attacker.squad.action_queue[0].action_type).is_equal(BaseAction.ActionType.SPRING_LOAD)


func test_priority_order_is_respected_when_both_are_buildable() -> void:
	var unit: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 1))
	var fallen: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 1))
	fallen.take_damage(12)   # fatal, sub-overkill (MHP 10) -> DOWNED
	assert_bool(fallen.is_downed()).is_true()
	var _victim: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 1), { Stats.Stat.MHP: 50 })

	var units: Array[Unit] = [unit, fallen, _victim]
	var priority: Array = [BaseAction.ActionType.RESCUE, BaseAction.ActionType.ATTACK]
	assert_bool(AITactics.queue_main_action(unit, _board(units), _sm, priority)).is_true()
	assert_int(unit.squad.action_queue[0].action_type).is_equal(BaseAction.ActionType.RESCUE)


func test_rescue_picks_the_most_urgent_clock() -> void:
	var rescuer: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 1))
	var stable: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 1))
	var urgent: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	stable.take_damage(12)
	urgent.take_damage(12)
	assert_bool(stable.is_downed() and urgent.is_downed()).is_true()
	stable.downed_turns_remaining = 3
	urgent.downed_turns_remaining = 1   # dies soonest -- listed second, must still win

	var units: Array[Unit] = [rescuer, stable, urgent]
	assert_bool(AITactics.queue_main_action(rescuer, _board(units), _sm, [BaseAction.ActionType.RESCUE])).is_true()
	var rescue: RescueAction = rescuer.squad.action_queue[0] as RescueAction
	assert_object(rescue).is_not_null()
	assert_object(rescue.target).is_same(urgent)


func test_intimidate_targets_the_lowest_positive_will() -> void:
	var bully: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 1))
	var pool: Array[AbilityData] = [_ability(Abilities.Id.INTIMIDATION)]
	_tank.ability_pool = pool
	bully.unit_instance.add_job("tank")
	var drained: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1))
	var shaky: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 1))
	var steady: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	drained.unit_instance.set_current_will(0)   # nothing to drain -- must be skipped
	shaky.unit_instance.set_current_will(3)     # closest to the maim cliff -- the pick
	steady.unit_instance.set_current_will(8)

	var units: Array[Unit] = [bully, drained, shaky, steady]
	assert_bool(AITactics.queue_main_action(bully, _board(units), _sm, [BaseAction.ActionType.INTIMIDATE])).is_true()
	var action: IntimidateAction = bully.squad.action_queue[0] as IntimidateAction
	assert_object(action).is_not_null()
	assert_object(action.target).is_same(shaky)


func test_intimidate_declines_when_every_adjacent_will_is_empty() -> void:
	var bully: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	var pool: Array[AbilityData] = [_ability(Abilities.Id.INTIMIDATION)]
	_tank.ability_pool = pool
	bully.unit_instance.add_job("tank")
	var hollow: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	hollow.unit_instance.set_current_will(0)

	var units: Array[Unit] = [bully, hollow]
	assert_bool(AITactics.queue_main_action(bully, _board(units), _sm, [BaseAction.ActionType.INTIMIDATE])).is_false()
	assert_array(bully.squad.action_queue).is_empty()


func test_intimidate_requires_the_live_ability() -> void:
	# No job, no ability -> the builder declines even with a juicy adjacent target. (The
	# queue_action chokepoint would refuse too -- the builder mirrors the menu's gate.)
	var poser: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	var _victim: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))

	var units: Array[Unit] = [poser, _victim]
	assert_bool(AITactics.queue_main_action(poser, _board(units), _sm, [BaseAction.ActionType.INTIMIDATE])).is_false()
	assert_array(poser.squad.action_queue).is_empty()
