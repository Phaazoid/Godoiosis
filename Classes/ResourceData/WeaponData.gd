class_name WeaponData
extends Item

# Weapon families — the canonical weapon_type vocabulary (docs/design/weapons.md).
# APPEND-ONLY (serialized as ints in saved .tres). NONE = 0 is the unset default.
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
@export var scaling_stat: Stats.Stat = Stats.Stat.STR
@export var attack_pattern: AttackPattern
@export var can_counter := true
@export var hits_allies := false
@export var weapon_type: WeaponType = WeaponType.NONE
@export var elemental_damage_type: Elemental.Element = Elemental.Element.NONE
