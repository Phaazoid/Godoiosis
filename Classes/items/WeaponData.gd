class_name WeaponData
extends EquippableData

# A weapon is an equippable with a BUILT-IN attack: it scales off a stat and carries its own
# pattern / element / policy. These fields used to live on EquippableData; they moved DOWN here
# so a RuneData (a bare container) no longer inherits an attack it doesn't have. .tres serialize
# @exports by NAME, so existing weapon resources are unaffected by the move.

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

@export var power: int = 0
@export var attack_pattern: AttackPattern
@export var can_counter := true
@export var hits_allies := false
@export var elemental_damage_type: Elemental.Element = Elemental.Element.NONE
@export var two_handed := false   # verb lock: a missing arm can't wield this (will-and-death.md)

# Which side of the world this weapon's attack affects (#50). Default UNIT = behaves as today;
# a terrain weapon opts into MAP/BOTH. APPEND-ONLY (serializes as an int).
@export var targets: EquippableData.TargetMode = EquippableData.TargetMode.UNIT

@export var scaling_stat: Stats.Stat = Stats.Stat.STR
@export var weapon_type: WeaponType = WeaponType.NONE

func hits_map() -> bool:
	return targets == EquippableData.TargetMode.MAP or targets == EquippableData.TargetMode.BOTH

# A weapon scales off a flat stat (power + the scaling stat). The resolver calls this on the
# unified attack source (E1 base-damage stage).
func base_damage(wielder: Unit) -> int:
	return power + wielder.get_effective_stat(scaling_stat)

# One element today, returned as a list so the resolver reads weapons and transmutations the
# same way (a transmutation carries a set). #30.
func get_elements() -> Array[Elemental.Element]:
	var result: Array[Elemental.Element] = []
	if elemental_damage_type != Elemental.Element.NONE:
		result.append(elemental_damage_type)
	return result
