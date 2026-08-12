# The FIRE half of the thermal loop, tested against the AUTHORED catalog (unlike
# test_elemental_reactions.gd, which injects in-code reactions to verify the resolver's logic
# alone): fire on a WET target dries it off at reduced damage (fire_wet_quickdry.tres), and the
# Blow Dry carving is a damageless FIRE delivery whose only effect IS that reaction. A wrong enum
# int in a .tres fails here, where an injected twin would stay green.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const BASE := 4

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# The authored reaction for one (element x state) route, read off the live catalog.
static func _authored(element: Elemental.Element, state: Elemental.State) -> ElementalReaction:
	for r in ReactionCatalog.get_all():
		if r.incoming_element == element and r.required_state == state:
			return r
	return null

func _fire_attacker(cell: Vector2i) -> Unit:
	var u := H.spawn_solo(self, _sm, PLAYER, cell, {Stats.Stat.STR: 0}, true, BASE)
	(u.get_equipped_weapon() as WeaponInstance).template.main_attack.elemental_damage_type = Elemental.Element.FIRE
	return u

func _resolve_single(attacker: Unit, target: Unit) -> AttackAction:
	var attack := H.stamped_attack(attacker, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)   # default reactions = the authored catalog
	return attack

func test_the_quickdry_reaction_is_authored() -> void:
	var r := _authored(Elemental.Element.FIRE, Elemental.State.WET)
	assert_object(r).is_not_null()
	assert_bool(r.remove_states.has(Elemental.State.WET)).is_true()
	assert_float(r.damage_mult).is_less(1.0)   # "one hit of protection" — direction, not a pinned number
	assert_bool(r.add_states.has(Elemental.State.CHILLED)).is_false()

func test_fire_dries_a_wet_target_at_reduced_damage() -> void:
	var attacker := _fire_attacker(Vector2i(0, 0))
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})
	target.add_element_state(Elemental.State.WET)

	var attack := _resolve_single(attacker, target)

	var r := _authored(Elemental.Element.FIRE, Elemental.State.WET)
	assert_int(attack.resolved.damage).is_equal(int(round(BASE * r.damage_mult)))
	assert_bool(attack.resolved.states_removed.has(Elemental.State.WET)).is_true()

func test_fire_on_a_dry_target_is_plain_damage() -> void:
	var attacker := _fire_attacker(Vector2i(0, 0))
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})

	var attack := _resolve_single(attacker, target)

	assert_int(attack.resolved.damage).is_equal(BASE)
	assert_bool(attack.resolved.states_removed.is_empty()).is_true()

func test_blow_dry_is_a_damageless_ally_safe_fire_delivery() -> void:
	# The carving carries no payload of its own: deals_no_damage suppresses scaling, hits_allies
	# lets it aim at a friend, and the QuickDry reaction does the actual drying.
	var carving: TransmutationData = load("res://Resources/TransmutationData/BlowDry.tres")
	assert_bool(carving.deals_no_damage).is_true()
	assert_bool(carving.hits_allies).is_true()
	assert_bool(carving.get_elements().has(Elemental.Element.FIRE)).is_true()

	var alch := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 0}, true, BASE)
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.MHP: 50})
	ally.add_element_state(Elemental.State.WET)

	var dry := AttackAction.create(alch, alch.movement.cell, ally, ally.movement.cell)
	dry.fired_attack = carving
	var plan := ResolvedPlan.new()
	plan.attacks.append(dry)
	PlanResolver.resolve(plan)

	assert_int(dry.resolved.damage).is_equal(0)
	assert_bool(dry.resolved.states_removed.has(Elemental.State.WET)).is_true()
