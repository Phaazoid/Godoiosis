# ResolvedOutcome.elevation_delta (#258): target height minus attacker height, stamped by the
# resolver. No rule reads it in v1 -- these cases pin the WIRE a future height-damage rule (and
# the queue row's uphill/downhill token) attaches to, and above all its Law #2 shape: frozen
# origin, THREADED target position.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func test_the_delta_is_target_minus_attacker() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 2)
	var sm := H.make_manager(self, heights)
	var low := H.spawn_solo(self, sm, PLAYER, Vector2i(0, 0))
	var high := H.spawn_solo(self, sm, ENEMY, Vector2i(1, 0))

	var uphill := H.stamped_attack(low, high)
	var downhill := H.stamped_attack(high, low)
	var plan := ResolvedPlan.new()
	var attacks: Array[AttackAction] = [uphill, downhill]
	plan.attacks = attacks
	PlanResolver.resolve(plan, ReactionCatalog.get_all(), sm.board_source.call())

	assert_int(uphill.resolved.elevation_delta).is_equal(2)
	assert_int(downhill.resolved.elevation_delta).is_equal(-2)


func test_no_board_stamps_zero() -> void:
	var sm := H.make_manager(self)
	var a := H.spawn_solo(self, sm, PLAYER, Vector2i(0, 0))
	var d := H.spawn_solo(self, sm, ENEMY, Vector2i(1, 0))

	var attack := H.stamped_attack(a, d)
	var plan := ResolvedPlan.new()
	var attacks: Array[AttackAction] = [attack]
	plan.attacks = attacks
	PlanResolver.resolve(plan)

	assert_int(attack.resolved.elevation_delta).is_equal(0)


# A heal short-circuits every hurt-only stage; the stamp sits above that fork on purpose, so an
# uphill heal says so too.
func test_a_heal_carries_the_delta() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 2)
	var sm := H.make_manager(self, heights)
	var healer := H.spawn_solo(self, sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, sm, PLAYER, Vector2i(1, 0))
	(healer.get_equipped_weapon() as WeaponInstance).template.main_attack.heals = true
	ally.set_current_hp(1)

	var heal := H.stamped_attack(healer, ally)
	var plan := ResolvedPlan.new()
	var attacks: Array[AttackAction] = [heal]
	plan.attacks = attacks
	PlanResolver.resolve(plan, ReactionCatalog.get_all(), sm.board_source.call())

	assert_int(heal.resolved.heal_amount).is_greater(0)
	assert_int(heal.resolved.elevation_delta).is_equal(2)


# The Law #2 case: a shove earlier in the pass moves the victim's LEVEL, and the later hit's
# delta must describe where the victim STANDS when it lands -- the threaded hypo position, never
# the live board cell. Since #259 a shove cannot climb (the brace), so the level change is a DROP:
# the victim starts on a terrace and is knocked off it; the live cell still reads elevation 2 for
# the whole preview pass, which is exactly what the mutant (a live read) reports.
func test_a_later_hit_reads_the_shoved_position() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 2)
	heights.set_cell(Vector2i(2, 0), 2)   # the victim's terrace; (3,0) is ground level
	var sm := H.make_manager(self, heights)
	var shover := H.spawn_solo(self, sm, PLAYER, Vector2i(1, 0))
	var victim := H.spawn_solo(self, sm, ENEMY, Vector2i(2, 0))
	var second := H.spawn_solo(self, sm, PLAYER, Vector2i(2, 1))
	(shover.get_equipped_weapon() as WeaponInstance).template.main_attack.knockback = 1

	var shove := H.stamped_attack(shover, victim)
	var follow_up := H.stamped_attack(second, victim)
	var plan := ResolvedPlan.new()
	var attacks: Array[AttackAction] = [shove, follow_up]
	plan.attacks = attacks
	PlanResolver.resolve(plan, ReactionCatalog.get_all(), sm.board_source.call())

	assert_bool(shove.resolved.knockback_applied).is_true()
	assert_bool(shove.resolved.knockback_to == Vector2i(3, 0)).is_true()
	# second stands at ground level; the victim LANDS at ground level -> 0. The live read says 2.
	assert_int(follow_up.resolved.elevation_delta).is_equal(0)
