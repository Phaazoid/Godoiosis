class_name WeaponAttackData
extends AttackData

# One selectable weapon attack — identity/geometry/flags inherited from AttackData; no
# sigils/flourishes/aura. Damage scaling comes from the wielded weapon (family
# scaling_blend + fitted mods). Families hold one as main_attack (+ extra_attacks); mods
# will add/replace them later (#74). Authored as .tres under WeaponAttackCatalog's dirs.
# elemental_damage_type lives HERE, not the base — a carving's elements derive from its
# sigils; giving it this field would be a lying editable surface.

@export var elemental_damage_type: Elemental.Element = Elemental.Element.NONE
