class_name WeaponAttackData
extends AttackData

# One selectable weapon attack — identity/geometry/flags inherited from AttackData; no
# sigils/flourishes/aura. Families hold one as main_attack (+ extra_attacks); a mod may grant
# more (#74). Authored as .tres under WeaponAttackCatalog's dirs.
# elemental_damage_type lives HERE, not the base — a carving's elements derive from its
# sigils; giving it this field would be a lying editable surface.

@export var elemental_damage_type: Elemental.Element = Elemental.Element.NONE

# Which stats this attack's damage scales off, as percentage weights across STR/DEX/PER/CON.
# MOVED here off WeaponData by #485 (2026-08-25): the blend was a property of the whole FAMILY, so
# every attack a weapon owned scaled identically and there was no reason to prefer one over another.
# Per attack, a mod that grants an attack brings its own scaling with it, and the family's own
# blend is simply its main attack's — one home, no fallback on the template (Law #4).
#
# WEIGHTS, normalised at read time by WeaponInstance.effective_blend, so a sum other than 100 is
# legal arithmetic and a LIE on screen: {STR: 100, DEX: 30} reads as 77/23, not 100 and 30. The
# Attack Editor pins the sum to 100 and AttackLint refuses anything else, which is what lets a
# displayed percentage be believed.
@export var scaling_blend: Dictionary[Stats.Stat, int] = {Stats.Stat.STR: 100}

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
		"scaling_blend": "Which stats this attack's damage scales off, in percent. The sliders always total 100, so what a stat reads IS its share -- STR at 55 means 55%. A fitted mod shifts these; the weapon's tooltip shows the result.",
		"requires_readiness": "This attack can only be fired while its weapon is READY. What ready MEANS is the weapon family's own call: a magazine with shots left on a Carbine, a wound spring on a Springspear, banked charge on a Kinetic Mace.",
		"consumes_readiness": "Firing leaves the weapon un-ready -- spends a shot, releases the spring, drains the bank. Independent of Requires Readiness: an attack can spend without needing.",
		"builds_readiness": "Firing RESTORES readiness to the weapon -- reloads, winds, banks charge. The third state: needs one / spends one / banks one.",
	})
	return tips
