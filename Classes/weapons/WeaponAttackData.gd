class_name WeaponAttackData
extends AttackData

# One selectable weapon attack — identity/geometry/flags inherited from AttackData; no
# sigils/flourishes/aura. Damage scaling comes from the wielded weapon (family
# scaling_blend + fitted mods). Families hold one as main_attack (+ extra_attacks); mods
# will add/replace them later (#74). Authored as .tres under WeaponAttackCatalog's dirs.
# elemental_damage_type lives HERE, not the base — a carving's elements derive from its
# sigils; giving it this field would be a lying editable surface.

@export var elemental_damage_type: Elemental.Element = Elemental.Element.NONE

@export var requires_readiness: bool = false
# This attack can only fire while its weapon is READY (#73). false = today's behavior for
# every existing attack (unaffected). The wielding WeaponInstance decides what "ready" means.

@export var consumes_readiness: bool = false
# Firing this attack leaves its weapon un-ready (#73). false = today's behavior. Independent
# of requires_readiness: an attack can spend readiness without itself needing it, though
# Spring (#73's worked example) does both.

@export var builds_readiness: bool = false
# Firing this attack RESTORES readiness to its weapon (#108). The third state the #73 pair was
# missing: requires/consumes can say "needs one and spends one" but not "banks one", so the Kinetic
# Mace inferred its charge-builder from `knockback > 0` instead — a second, private answer to a
# question these flags already own (design law #4), which made authoring either flag on that family
# silently inert. false = today's behavior for every existing attack. What "readiness" IS remains
# the wielding WeaponInstance's call: a bool for the Springspear, a magazine for the Carbine, a
# charge bank for the mace.


# The four fields this subclass adds (#473); the shared ones are AttackData's answer, merged in
# rather than restated. Forgetting the merge loses every base tip silently, which is what
# tests/dev/test_property_tips.gd's coverage law is for.
static func property_tips() -> Dictionary:
	var tips := AttackData.property_tips()
	tips.merge({
		"elemental_damage_type": "Which element this attack's damage carries, for reactions and resistances. NONE = plain physical damage.",
		"requires_readiness": "This attack can only be fired while its weapon is READY. What ready MEANS is the weapon family's own call: a magazine with shots left on a Carbine, a wound spring on a Springspear, banked charge on a Kinetic Mace.",
		"consumes_readiness": "Firing leaves the weapon un-ready -- spends a shot, releases the spring, drains the bank. Independent of Requires Readiness: an attack can spend without needing.",
		"builds_readiness": "Firing RESTORES readiness to the weapon -- reloads, winds, banks charge. The third state: needs one / spends one / banks one.",
	})
	return tips
