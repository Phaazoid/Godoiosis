class_name WeaponData
extends EquippableData

# Weapon families — canonical weapon_type vocabulary (docs/design/weapons.md).
# APPEND-ONLY (serialized as ints). NONE = 0 is the unset default.
enum WeaponType {
	NONE,
	CHAINSWORD,
	DRILL,
	SPRINGSPEAR,
	CARBINE,
	KINETIC_MACE,
	CHEMICAL_SPITTER,
	PROSTHETIC,
}

@export var scaling_stat: Stats.Stat = Stats.Stat.STR
@export var weapon_type: WeaponType = WeaponType.NONE

# A weapon scales off a flat stat (the existing formula, now polymorphic).
func base_damage(wielder: Unit) -> int:
	return power + wielder.get_effective_stat(scaling_stat)
