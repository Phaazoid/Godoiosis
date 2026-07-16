# Law #2 at the maim rung (#56): the MAIMED icon promises "this down costs a limb" — so
# a FULLY-maimed target (nothing left to take) must preview a plain DOWN, not a maim.
# The hypo's can_maim snapshot is exact, not approximate: within one pass a unit can maim
# at most once (a second fatal hit lands on a DOWNED unit, and that is a kill).
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# One sub-overkill fatal hit: damage exactly equals HP (power 5 + fixture STR 5 = MHP 10).
func _resolve_fatal_hit(target: Unit) -> AttackAction:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1), {}, true, 5)
	var attack := AttackAction.create(attacker, attacker.movement.cell, target, target.movement.cell)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)
	return attack

func test_unaffordable_down_previews_maim() -> void:
	# Will 0 and limbs to spare -> the down costs a limb, and the queue says so.
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 10, Stats.Stat.WIL: 0})
	var attack := _resolve_fatal_hit(target)
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.MAIMED)

func test_fully_maimed_target_previews_plain_down() -> void:
	# Nothing left to take -> promising a maim would be a lie. It is just a down.
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 10, Stats.Stat.WIL: 0})
	for slot in UnitInstance.LimbSlot.values():
		target.unit_instance.limbs[slot].state = UnitInstance.LimbState.EMPTY
	var attack := _resolve_fatal_hit(target)
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.DOWNED)
