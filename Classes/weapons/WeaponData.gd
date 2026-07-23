class_name WeaponData
extends Item

# A weapon TEMPLATE — the shared design of a family base (ChainSword.tres) or a named
# prototype (TheJaw.tres). NOT equippable: units carry a WeaponInstance, which points here
# and layers its own fitted mods on top. Every instance reads this resource live — editing
# a template updates every weapon built on it (direct-ref flavor of the jobs pattern).
# Since #72 the attack itself lives PER-ATTACK (WeaponAttackData carries power/pattern/
# flags); the family keeps physique (weight, spaces, two_handed) and its scaling identity.

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
# PROSTHETIC only: which limb a prosthetic installs into. The FIELD lives on
# WeaponInstance, not here (moved 2026-07-19) — different prosthetic instances of the
# same family need independent arm/leg identity, so a shared template field can't be
# the source of truth for it. This enum stays here as the shared vocabulary.

# Three mod spaces, capacities 1/2/3; a prototype trades them for a single size-1 space
# (weapons.md "the archetype clause made content").
const SPACE_CAPACITIES: Array[int] = [1, 2, 3]   # playtest-tunable

@export var main_attack: WeaponAttackData
# The family's standard attack — the one REQUIRED attack, what counters and default aim
# use. Curated content: one .tres per family in WeaponAttackCatalog.MAIN_DIR, edited via
# the Family Mains panel — editing it changes every weapon of this family everywhere.

@export var extra_attacks: Array[WeaponAttackData] = []
# Additional stock attacks (e.g. Springspear's Spring, #73). No count cap — mod spaces do
# the gating work. Mod-granted attacks are #74's job and never land here.

@export var two_handed := false   # verb lock: a missing arm can't wield this (will-and-death.md)
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

# Every stock attack, main first — the canonical order for menus and default picks.
func attacks() -> Array[WeaponAttackData]:
	var result: Array[WeaponAttackData] = []
	if main_attack != null:
		result.append(main_attack)
	result.append_array(extra_attacks)
	return result
