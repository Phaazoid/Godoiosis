# Pure-utility attacks (#126): `AttackData.deals_no_damage` suppresses SCALING, so a damageless
# effect stays damageless no matter how good its wielder is at it.
#
# The flag exists because a wind transmutation cannot otherwise reach 0 damage. A carving's damage is
# `power + aura summed over its sigils`, and channeling anchors on real aura in one of the carving's
# elements (the 2026-08-10 wildcard model; it REQUIRED temper aura before that) — so the alchemists
# who fire an AIR carving mostly ARE the ones whose aura would sneak damage into it, and even a
# wildcard-anchored outsider scales off whatever relevant aura they do hold. Same hazard one layer
# over: a `power = 0` weapon attack still collects the family's stat blend.
#
# What the flag does NOT do (dev, 2026-08-08): suppress an elemental reaction's damage_bonus. That
# bonus is not part of the original transmutation — it is what the WORLD did with the element the
# attack carried — and it stays real. Gusting a wet body with a Quickened fire carving electrocutes
# it, and if the body was downed, it dies. That is the player's mistake to avoid, and it is pinned
# here as a decision so it cannot be "tidied" into a resolver clamp later.
#
# Sibling: tests/law/test_damage_floor.gd owns the 0-damage floor itself and the amended fork 3
# ("a hit that deals nothing cannot finish a body").
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

func _alchemist(aura: Dictionary[Elemental.Element, int]) -> Unit:
	var unit: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	unit.unit_instance.aura = aura
	var affinity: Array[Elemental.Element] = []
	for element in aura:
		affinity.append(element)
	unit.unit_instance.affinity = affinity
	return unit

func _carving(element: Elemental.Element, no_damage: bool) -> TransmutationData:
	var carving := TransmutationData.new()
	carving.sigils.assign([element])
	carving.deals_no_damage = no_damage
	return carving

# Down an ally for real rather than assigning lifecycle_state: _go_downed is what clings it to 1 HP
# and spends the Will, and this suite cares about what a hit does to that state.
func _downed_ally(cell: Vector2i) -> Unit:
	var ally: Unit = H.spawn_solo(self, _sm, PLAYER, cell)
	ally.take_damage(ally.get_current_hp())
	assert_bool(ally.is_downed()).is_true()
	return ally

func _resolve(action: AttackAction, reactions: Array[ElementalReaction], board: BoardContext = null) -> ResolvedOutcome:
	var plan := ResolvedPlan.new()
	plan.attacks.append(action)
	PlanResolver.resolve(plan, reactions, board)
	return action.resolved

# ---- the flag suppresses scaling, on both attack kinds ----

func test_a_no_damage_carving_ignores_the_wielders_aura() -> void:
	var caster := _alchemist({Elemental.Element.AIR: 4})
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var no_reactions: Array[ElementalReaction] = []

	# Control: the same carving WITHOUT the flag is worth its wielder's air aura.
	var scaled := H.stamped_attack(caster, foe)
	scaled.fired_attack = _carving(Elemental.Element.AIR, false)
	assert_int(_resolve(scaled, no_reactions).damage).is_equal(4)

	var utility := H.stamped_attack(caster, foe)
	utility.fired_attack = _carving(Elemental.Element.AIR, true)
	assert_int(_resolve(utility, no_reactions).damage).is_equal(0)

func test_a_no_damage_weapon_attack_ignores_the_stat_blend() -> void:
	var attacker: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 6})
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var weapon := attacker.get_equipped_weapon() as WeaponInstance
	weapon.template.main_attack.power = 0
	var no_reactions: Array[ElementalReaction] = []

	# Control: power 0 is NOT 0 damage — the blend still pays out the wielder's STR.
	var scaled := H.stamped_attack(attacker, foe)
	assert_int(_resolve(scaled, no_reactions).damage).is_equal(6)

	weapon.template.main_attack.deals_no_damage = true
	var utility := H.stamped_attack(attacker, foe)
	assert_int(_resolve(utility, no_reactions).damage).is_equal(0)

# ---- what the flag deliberately does NOT suppress ----

func test_an_elemental_reaction_still_damages_through_a_no_damage_attack() -> void:
	# The real content shape: FIRE + QUICKENING derives SHOCK (Flourish.DERIVED), and the authored
	# shock_wet_electrocute reaction pays +5 into a WET target. The carving contributes nothing; the
	# reaction is not the carving's to suppress.
	var caster := _alchemist({Elemental.Element.FIRE: 3})
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20})
	foe.add_element_state(Elemental.State.WET)

	var carving := _carving(Elemental.Element.FIRE, true)
	carving.flourishes.assign([Flourish.Type.QUICKENING])
	assert_array(carving.get_elements()).contains([Elemental.Element.SHOCK])

	var action := H.stamped_attack(caster, foe)
	action.fired_attack = carving
	var outcome := _resolve(action, ReactionCatalog.get_all())

	assert_int(outcome.damage).is_equal(5)   # 0 scaled + the reaction's bonus

func test_a_no_damage_attack_that_a_reaction_arms_still_finishes_a_downed_body() -> void:
	# The consequence stated out loud: the exemption is keyed on the DAMAGE NUMBER, so an attack that
	# is damageless on paper but arrives carrying 5 is an ordinary killing hit.
	var caster := _alchemist({Elemental.Element.FIRE: 3})
	var ally := _downed_ally(Vector2i(1, 0))
	ally.add_element_state(Elemental.State.WET)

	var carving := _carving(Elemental.Element.FIRE, true)
	carving.flourishes.assign([Flourish.Type.QUICKENING])
	carving.hits_allies = true

	var action := H.stamped_attack(caster, ally)
	action.fired_attack = carving
	var outcome := _resolve(action, ReactionCatalog.get_all())

	assert_that(outcome.lethality).is_equal(ResolvedOutcome.Lethality.KILLED)

# ---- the payoff: a damageless shove repositions a body instead of executing it ----

func test_a_no_damage_shove_moves_a_downed_ally_instead_of_killing_it() -> void:
	# THE regression. Both halves have to hold at once and each is a separate bug if it doesn't:
	# the ladder must name NONE (fork 3 amended), and _resolve_knockback must then publish a landing
	# cell — it returns early on a KILLED target, so before #126 the body died where it lay.
	var caster := _alchemist({Elemental.Element.AIR: 4})
	var ally := _downed_ally(Vector2i(1, 0))
	var no_reactions: Array[ElementalReaction] = []

	var gust := _carving(Elemental.Element.AIR, true)
	gust.hits_allies = true
	gust.knockback = 2

	var action := H.stamped_attack(caster, ally)
	action.fired_attack = gust
	var outcome := _resolve(action, no_reactions, _sm.board_source.call())

	assert_int(outcome.damage).is_equal(0)
	assert_that(outcome.lethality).is_equal(ResolvedOutcome.Lethality.NONE)
	assert_bool(outcome.knockback_applied).is_true()
	assert_vector(outcome.knockback_to).is_equal(Vector2i(3, 0))   # shoved directly away from the caster

	# And the execution seam agrees: replaying the resolved 0 leaves the body downed, not dead.
	ally.take_damage(outcome.damage)
	assert_bool(ally.is_downed()).is_true()
	assert_bool(ally.is_dead()).is_false()
