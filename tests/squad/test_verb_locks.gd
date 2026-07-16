# Verb locks (#56, will-and-death.md limb model): any missing arm locks two-handed
# patterns and rescue-carry. The menu hides the options; SquadManager.queue_action is
# the backstop every caller (including AI, Law #3) must pass — both are pinned here.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

func _lose_arm(unit: Unit) -> void:
	unit.unit_instance.limbs[UnitInstance.LimbSlot.ARM_L].state = UnitInstance.LimbState.EMPTY

func _give_two_handed(unit: Unit) -> void:
	var weapon := H.make_weapon(3)
	weapon.two_handed = true
	unit.equipped_weapon = weapon

func test_two_handed_lock_needs_both_arms() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	_give_two_handed(unit)
	assert_bool(unit.can_wield_equipped()).is_true()
	_lose_arm(unit)
	assert_bool(unit.can_wield_equipped()).is_false()

func test_one_handed_kit_unaffected_by_missing_arm() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))   # fixture weapon is one-handed
	_lose_arm(unit)
	assert_bool(unit.can_wield_equipped()).is_true()

func test_rescue_carry_needs_both_arms() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	assert_bool(unit.can_rescue_carry()).is_true()
	_lose_arm(unit)
	assert_bool(unit.can_rescue_carry()).is_false()

func test_queue_action_refuses_locked_two_handed_attack() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	_give_two_handed(attacker)
	_lose_arm(attacker)
	var attack := AttackAction.create(attacker, attacker.movement.cell, target, target.movement.cell)
	assert_bool(_sm.queue_action(attacker.squad, attack)).is_false()

func test_queue_action_refuses_one_armed_rescue() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var downed := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	downed.lifecycle_state = Unit.LifecycleState.DOWNED
	_lose_arm(rescuer)
	var rescue := RescueAction.new()
	rescue.init(rescuer, downed)
	assert_bool(_sm.queue_action(rescuer.squad, rescue)).is_false()

func test_intact_unit_queues_both_verbs() -> void:
	# Positive control: the backstop refuses only the locked cases.
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	_give_two_handed(attacker)
	var attack := AttackAction.create(attacker, attacker.movement.cell, target, target.movement.cell)
	assert_bool(_sm.queue_action(attacker.squad, attack)).is_true()
