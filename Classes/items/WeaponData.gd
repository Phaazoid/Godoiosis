class_name WeaponData
extends Item

# A weapon TEMPLATE — the shared design of a family base (ChainSword.tres) or a named
# prototype (TheJaw.tres). NOT equippable: units carry a WeaponInstance, which points here
# and layers its own fitted mods on top. Every instance reads this resource live — editing
# a template updates every weapon built on it (direct-ref flavor of the jobs pattern).

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

@export var built_in_stat: int = 0
# PROSTHETIC only: the STR/DEX this limb contributes when installed (will-and-death.md
# limb-slot model). Deliberately separate from scaling_blend/power — this is what the
# limb itself reads for stat substitution, not the weapon's own damage math.

enum LimbKind { ARM, LEG }

@export var limb_kind: LimbKind = LimbKind.ARM
# PROSTHETIC only: which limb this template installs into. UnitInstance.install_prosthetic
# validates against it — no dual-purpose prosthetics, every one is exactly ARM or LEG.

# Three mod spaces, capacities 1/2/3; a prototype trades them for a single size-1 space
# (weapons.md "the archetype clause made content").
const SPACE_CAPACITIES: Array[int] = [1, 2, 3]   # playtest-tunable

@export var power: int = 0
@export var attack_pattern: AttackPattern
@export var can_counter := true
@export var hits_allies := false
@export var elemental_damage_type: Elemental.Element = Elemental.Element.NONE
@export var two_handed := false   # verb lock: a missing arm can't wield this (will-and-death.md)
@export var targets: EquippableData.TargetMode = EquippableData.TargetMode.UNIT
@export var weapon_type: WeaponType = WeaponType.NONE
@export var is_prototype := false

# Percentage weights across STR/DEX/PER/CON; missing key = 0%, should sum to 100 (not
# hard-enforced). The family's identity — instances never carry their own copy.
@export var scaling_blend: Dictionary[Stats.Stat, int] = {Stats.Stat.STR: 100}
@export var base_weight: int = 0   # playtest-tunable

func space_capacities() -> Array[int]:
	if is_prototype:
		return [1]
	return SPACE_CAPACITIES

func hits_map() -> bool:
	return targets == EquippableData.TargetMode.MAP or targets == EquippableData.TargetMode.BOTH
