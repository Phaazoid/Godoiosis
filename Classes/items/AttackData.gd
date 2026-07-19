class_name AttackData
extends Resource

# Shared base for anything a unit can FIRE: a weapon attack (WeaponAttackData) or an
# inscribed carving (TransmutationData). Carries the attack's identity, geometry, and
# combat flags — what every consumer (pattern reach, counter gate, ally-splash, target
# mode) reads without caring which kind it is. Damage math deliberately stays on the
# subclasses: carvings scale off the wielder's AURA, weapon attacks off the wielding
# WEAPON (scaling_blend + mods) — there is no shared damage surface. #72.

@export var display_name: String = ""
@export var power: int = 0
@export var attack_pattern: AttackPattern
@export var can_counter := true
@export var hits_allies := false
@export var targets: EquippableData.TargetMode = EquippableData.TargetMode.UNIT

func hits_map() -> bool:
	return targets == EquippableData.TargetMode.MAP or targets == EquippableData.TargetMode.BOTH
