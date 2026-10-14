# An attack fires only from a weapon that carries it (#1283).
#
# A queued order and an armed watch each STAMP their attack when they are declared, and the resolver
# then asks "the weapon in hand" for every number. The dock can swap that weapon after the stamp, so
# before this a Slash queued with a sword played with the mace's damage, kind, elements and shove --
# an attack neither weapon throws. The fire gate now asks ownership before the economy
# (Unit.attack_block_reason), and SquadPlanValidator re-asks it of every stored order.
#
# Swaps go through GearVerbs.perform, the rule the dock's buttons, the replay and the Play API share,
# so these cases drive the door a player uses rather than writing the slot directly. The dock button
# itself, and the queue refresh it triggers, are tests/ui/test_equip_with_an_attack_queued.gd's.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const EQUIP := GearVerbs.Verb.EQUIP

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _main_of(weapon: EquippableData) -> WeaponAttackData:
	return (weapon as WeaponInstance).template.main_attack


# A unit carrying two weapons of DIFFERENT families -- a sword in hand, a mace in the pack -- in its
# own solo squad, with nothing written into the slot by hand.
func _armed(cell := Vector2i.ZERO) -> Unit:
	var unit := H.spawn_solo(self, _sm, PLAYER, cell, {}, false)
	unit.add_item(H.make_weapon(3))   # the first weapon-shaped item auto-equips
	unit.add_item(H.make_weapon(5))
	return unit


func _sword(unit: Unit) -> EquippableData:
	return unit.inventory[0] as EquippableData


func _mace(unit: Unit) -> EquippableData:
	return unit.inventory[1] as EquippableData


func _equip(unit: Unit, item: EquippableData) -> void:
	assert_str(GearVerbs.perform(unit, EQUIP, unit.inventory.find(item))) \
		.override_failure_message("fixture: the swap itself was refused").is_empty()


# What the queue panel does on every refresh: resolve, then validate WITH the plan.
func _refresh(squad: Squad) -> void:
	var plan := _sm.resolve_plan(squad, _sm.board_source.call())
	_sm.validate_squad_plan(squad, plan)


# --- the gate ---

func test_an_attack_the_weapon_in_hand_carries_is_fireable() -> void:
	var unit := _armed()
	assert_object(unit.get_equipped_weapon()).override_failure_message(
		"fixture: the sword did not auto-equip").is_same(_sword(unit))
	assert_str(unit.attack_block_reason(_main_of(_sword(unit)))).is_empty()


func test_another_weapons_attack_is_refused() -> void:
	var unit := _armed()
	var slash := _main_of(_sword(unit))
	_equip(unit, _mace(unit))
	assert_str(unit.attack_block_reason(slash)).override_failure_message(
		"the mace answered for the sword's attack, so a stamp from the sword fires through it").is_not_empty()
	assert_bool(unit.is_attack_fireable(slash)).is_false()


func test_an_empty_hand_refuses_any_attack_but_bare_fists() -> void:
	var unit := _armed()
	var slash := _main_of(_sword(unit))
	assert_str(GearVerbs.perform(unit, GearVerbs.Verb.UNEQUIP, -1)).is_empty()
	assert_str(unit.attack_block_reason(slash)).override_failure_message(
		"an empty hand answered for the sword's attack -- its shape would fire with bare-fist numbers").is_not_empty()
	assert_str(unit.attack_block_reason(null)).override_failure_message(
		"bare fists (a null attack) must stay fireable").is_empty()


# Two copies of one family share their template, so both carry the SAME attack object. A swap
# between them keeps the order: it is an attack the new copy really throws (the #1283 ruling).
func test_a_second_copy_of_the_family_carries_the_same_attack() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i.ZERO, {}, false)
	var first := H.make_weapon(3)
	var second := WeaponInstance.make(first.template)
	unit.add_item(first)
	unit.add_item(second)
	_equip(unit, second)
	assert_str(unit.attack_block_reason(first.template.main_attack)).is_empty()


# The repertoire lists the main in its LIVE form, so a hot tank hides the base form from it.
func test_both_forms_of_the_main_are_carried_while_the_tank_is_hot() -> void:
	var charged := WeaponAttackData.new()
	charged.display_name = "Pressurised Spray"
	var spray := WeaponAttackData.new()
	spray.display_name = "Spray"
	spray.empowered_form = charged
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHEMICAL_SPITTER
	t.main_attack = spray
	var spitter := WeaponInstance.make(t) as ChemicalSpitterWeaponInstance
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i.ZERO, {}, false)
	unit.add_item(spitter)
	spitter.charges = 1
	assert_bool(spitter.is_supercharged()).override_failure_message("fixture: the tank is not hot").is_true()
	assert_str(unit.attack_block_reason(spray)).is_empty()
	assert_str(unit.attack_block_reason(charged)).is_empty()


# --- a queued order ---

func _queued_aim(unit: Unit, foe: Unit) -> AttackAction:
	_sm.active_squad = unit.squad
	var aim := AttackAction.declare(unit, unit.movement.cell, foe.movement.cell)
	assert_bool(_sm.queue_action(unit.squad, aim)).override_failure_message(
		"fixture: the aim was refused at the queue").is_true()
	_refresh(unit.squad)
	assert_bool(aim.is_valid).override_failure_message(
		"fixture: the aim is red before any swap: %s" % [aim.validation_errors]).is_true()
	return aim


func test_swapping_weapons_reds_a_queued_attack_and_swapping_back_clears_it() -> void:
	var unit := _armed()
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 200}, false)
	var aim := _queued_aim(unit, foe)

	_equip(unit, _mace(unit))
	_refresh(unit.squad)
	assert_bool(aim.is_valid).override_failure_message(
		"the sword's Slash is still a valid order with the mace in hand -- it would fire with the mace's numbers").is_false()
	assert_array(aim.validation_errors).is_not_empty()
	assert_bool(_sm.squad_has_invalid_actions(unit.squad)).is_true()
	assert_bool(unit.squad.action_queue.has(aim)).override_failure_message(
		"the order was deleted -- a broken order stays queued in red").is_true()

	_equip(unit, _sword(unit))
	_refresh(unit.squad)
	assert_bool(aim.is_valid).override_failure_message(
		"the sword is back in hand and the order is still red: %s" % [aim.validation_errors]).is_true()


func test_unequipping_reds_a_queued_attack() -> void:
	var unit := _armed()
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 200}, false)
	var aim := _queued_aim(unit, foe)
	assert_str(GearVerbs.perform(unit, GearVerbs.Verb.UNEQUIP, -1)).is_empty()
	_refresh(unit.squad)
	assert_bool(aim.is_valid).is_false()


func test_swapping_weapons_reds_a_queued_watch() -> void:
	var unit := _armed()
	var watch_attack := WeaponAttackData.new()
	watch_attack.display_name = "Watch"
	watch_attack.can_overwatch = true
	var sword := _sword(unit) as WeaponInstance
	sword.template.extra_attacks = [watch_attack] as Array[WeaponAttackData]
	_sm.active_squad = unit.squad
	var order := OverwatchAction.new()
	order.init(unit, Vector2i(1, 0), watch_attack)
	assert_bool(_sm.queue_action(unit.squad, order)).override_failure_message(
		"fixture: the watch was refused at the queue").is_true()
	_refresh(unit.squad)
	assert_bool(order.is_valid).override_failure_message(
		"fixture: the watch is red before any swap: %s" % [order.validation_errors]).is_true()

	_equip(unit, _mace(unit))
	_refresh(unit.squad)
	assert_bool(order.is_valid).override_failure_message(
		"a watch stamped off the sword is still valid with the mace in hand").is_false()


# --- an armed watch ---

# Already armed, so no order is left to red: the watch itself goes DORMANT, through Watch.is_armed's
# own fire-gate read -- a dry watch's shape (#810), and back the moment the weapon is.
func test_an_armed_watch_sleeps_while_its_weapon_is_out_of_hand() -> void:
	var unit := _armed()
	var watched: Array[Vector2i] = [Vector2i(2, 0)]
	unit.arm_watch(unit.movement.cell, watched[0], watched, _main_of(_sword(unit)))
	assert_bool(unit.watch.is_armed()).override_failure_message("fixture: the watch never armed").is_true()

	_equip(unit, _mace(unit))
	assert_bool(unit.watch.is_armed()).override_failure_message(
		"the sword's watch still stands with the mace in hand -- its shot would fire through the mace").is_false()

	_equip(unit, _sword(unit))
	assert_bool(unit.watch.is_armed()).is_true()
