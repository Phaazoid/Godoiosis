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
