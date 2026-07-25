# Drill Burrow (#84): the capability surface and the queue gate. Burrow is the third family
# signature off the epic and the first whose consequence is TERRAIN rather than unit or weapon
# state — so unlike rev/readiness there is NO per-weapon battle state here, just a capability
# query (can_burrow) that the action's gate and the Weapon Action menu both read.
#
# The terrain consequence itself — a COVER tile deposited, its DEF mitigating a later hit,
# preview == execution — is proven on a real board in tests/play/test_burrow.gd.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _weapon(kind: WeaponData.WeaponType) -> WeaponInstance:
	var t := WeaponData.new()
	t.weapon_type = kind
	t.main_attack = WeaponAttackData.new()
	return WeaponInstance.make(t)


func _digger() -> Unit:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {}, false)
	unit.add_item(_weapon(WeaponData.WeaponType.DRILL))
	return unit


# --- the capability surface ---

func test_drill_can_burrow() -> void:
	assert_bool(_weapon(WeaponData.WeaponType.DRILL).can_burrow()).is_true()


func test_every_other_family_cannot_burrow() -> void:
	# The base-class no-op holds for all six siblings — a family without the mechanic pays nothing.
	for kind: WeaponData.WeaponType in [
			WeaponData.WeaponType.CHAINSWORD, WeaponData.WeaponType.SPRINGSPEAR,
			WeaponData.WeaponType.CARBINE, WeaponData.WeaponType.KINETIC_MACE,
			WeaponData.WeaponType.CHEMICAL_SPITTER, WeaponData.WeaponType.PROSTHETIC]:
		assert_bool(_weapon(kind).can_burrow()).is_false()


func test_burrow_carries_no_battle_state_across_a_copy() -> void:
	# Nothing to reset: the capability is a property of the family, not a per-battle counter.
	var drill := _weapon(WeaponData.WeaponType.DRILL)
	var fresh := drill.copy_equippable() as WeaponInstance
	assert_bool(fresh.can_burrow()).is_true()


# --- the Unit delegator + menu gate ---

func test_unit_delegator_reads_whatever_is_equipped() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {}, false)
	assert_bool(unit.can_burrow_weapon()).is_false()      # bare hands
	unit.add_item(_weapon(WeaponData.WeaponType.CHAINSWORD))
	assert_bool(unit.can_burrow_weapon()).is_false()      # wrong family
	unit.add_item(_weapon(WeaponData.WeaponType.DRILL))
	unit.equip_weapon_from_inventory(1)
	assert_bool(unit.can_burrow_weapon()).is_true()


func test_burrow_surfaces_under_weapon_actions() -> void:
	# A drill has no secondary attacks authored, so Burrow ALONE must light the menu entry.
	var digger := _digger()
	assert_bool(digger.has_weapon_actions()).is_true()


# --- the action ---

func test_burrow_action_gate_follows_the_weapon() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {}, false)
	var action := BurrowAction.new()
	action.init(unit)
	assert_bool(action.actor_can_perform()).is_false()    # no drill -> can't queue (Law #3 gate)
	unit.add_item(_weapon(WeaponData.WeaponType.DRILL))
	assert_bool(action.actor_can_perform()).is_true()


func test_burrow_is_a_main_action() -> void:
	var action := BurrowAction.new()
	action.init(_digger())
	assert_bool(action.is_main_action()).is_true()
	assert_that(action.action_type).is_equal(BaseAction.ActionType.BURROW)


func test_queueing_burrow_locks_the_units_main_action() -> void:
	var digger := _digger()
	var action := BurrowAction.new()
	action.init(digger)
	assert_bool(_sm.queue_action(digger.squad, action)).is_true()
	assert_bool(digger.has_main_action_queued()).is_true()
